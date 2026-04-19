import http from "node:http";
import { spawn } from "node:child_process";

const HOST = "127.0.0.1";
const PORT = 4311;
const REPO_ROOT = "C:\\dev\\triad";
const BRIDGE_SCRIPT = "C:\\dev\\triad\\scripts\\triad_workbench_bridge_v1.ps1";

function sendJson(res, statusCode, obj) {
  const body = JSON.stringify(obj);
  res.writeHead(statusCode, {
    "Content-Type": "application/json; charset=utf-8",
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Methods": "POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type"
  });
  res.end(body);
}

function readBody(req) {
  return new Promise((resolve, reject) => {
    let raw = "";
    req.on("data", (chunk) => {
      raw += chunk.toString("utf8");
      if (raw.length > 1024 * 1024) {
        reject(new Error("REQUEST_TOO_LARGE"));
      }
    });
    req.on("end", () => resolve(raw));
    req.on("error", reject);
  });
}

function runBridge(payload) {
  return new Promise((resolve) => {
    const args = [
      "-NoProfile",
      "-NonInteractive",
      "-ExecutionPolicy",
      "Bypass",
      "-File",
      BRIDGE_SCRIPT,
      "-RepoRoot",
      REPO_ROOT,
      "-Action",
      payload.action || ""
    ];

    if (payload.inputPath) {
      args.push("-InputPath", payload.inputPath);
    }
    if (payload.outputPath) {
      args.push("-OutputPath", payload.outputPath);
    }
    if (payload.archiveDir) {
      args.push("-ArchiveDir", payload.archiveDir);
    }
    if (payload.transformType) {
      args.push("-TransformType", payload.transformType);
    }
    if (payload.manifestPath) {
      args.push("-ManifestPath", payload.manifestPath);
    }

    const child = spawn("powershell.exe", args, {
      windowsHide: true,
      cwd: REPO_ROOT
    });

    let stdout = "";
    let stderr = "";

    child.stdout.on("data", (chunk) => {
      stdout += chunk.toString("utf8");
    });

    child.stderr.on("data", (chunk) => {
      stderr += chunk.toString("utf8");
    });

    child.on("close", () => {
      const trimmed = stdout.trim();
      if (!trimmed) {
        resolve({
          ok: false,
          action: payload.action || "unknown",
          exit_code: 1,
          stdout,
          stderr: stderr || "BRIDGE_EMPTY_RESPONSE"
        });
        return;
      }

      try {
        const parsed = JSON.parse(trimmed);
        resolve(parsed);
      } catch {
        resolve({
          ok: false,
          action: payload.action || "unknown",
          exit_code: 1,
          stdout,
          stderr: stderr || "BRIDGE_JSON_PARSE_FAILED"
        });
      }
    });

    child.on("error", (err) => {
      resolve({
        ok: false,
        action: payload.action || "unknown",
        exit_code: 1,
        stdout,
        stderr: err.message
      });
    });
  });
}

const server = http.createServer(async (req, res) => {
  if (!req.url) {
    sendJson(res, 400, { ok: false, error: "MISSING_URL" });
    return;
  }

  if (req.method === "OPTIONS") {
    res.writeHead(204, {
      "Access-Control-Allow-Origin": "*",
      "Access-Control-Allow-Methods": "POST, OPTIONS",
      "Access-Control-Allow-Headers": "Content-Type"
    });
    res.end();
    return;
  }

  if (req.method === "GET" && req.url === "/api/health") {
    sendJson(res, 200, { ok: true, service: "triad-workbench-bridge", port: PORT });
    return;
  }

  if (req.method === "POST" && req.url === "/api/triad-action") {
    try {
      const raw = await readBody(req);
      const payload = raw ? JSON.parse(raw) : {};
      const result = await runBridge(payload);
      sendJson(res, 200, result);
      return;
    } catch (err) {
      sendJson(res, 500, {
        ok: false,
        action: "unknown",
        exit_code: 1,
        stdout: "",
        stderr: err instanceof Error ? err.message : "BRIDGE_REQUEST_FAILURE"
      });
      return;
    }
  }

  sendJson(res, 404, { ok: false, error: "NOT_FOUND" });
});

server.listen(PORT, HOST, () => {
  console.log(`TRIAD_WORKBENCH_BRIDGE_OK http://${HOST}:${PORT}`);
});

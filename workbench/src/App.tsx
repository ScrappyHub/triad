import React, { useEffect, useMemo, useState } from "react";

type Artifact = { name: string; path: string; sha256: string; bytes: number };
type Bundle = { bundle_id: string; label: string; path: string; pinned: boolean; latest: boolean; created_utc: string; artifacts: Artifact[] };
type Engine = { id: string; title: string; status: string; summary: string; proof_lane_count: number };
type ActionItem = { id: string; label: string; kind: string };
type CommandItem = { id: string; label: string; command: string };
type ExportModel = {
  schema: string;
  product: { name: string; release_label: string; workbench_label: string; mode: string };
  summary: { release_state: string; latest_verified_run_utc: string; canonical_bundle_id: string; bundle_count: number; engine_count: number };
  canonical_bundle: { bundle_id: string; display_name: string; path: string; created_utc: string; artifacts: Artifact[] };
  bundles: Bundle[];
  engines: Engine[];
  actions: ActionItem[];
  commands: CommandItem[];
};
type NavKey = "overview" | "bundles" | "engines" | "commands" | "verification";
type BridgeResponse = {
  ok: boolean;
  action: string;
  exit_code: number;
  stdout: string;
  stderr: string;
  archive_input?: string;
  archive_dir?: string;
  extract_dir?: string;
  input_path?: string;
  output_path?: string;
  manifest_path?: string;
};

const shellStyle: React.CSSProperties = {
  minHeight: "100vh",
  background: "#09090b",
  color: "#fafafa",
  fontFamily: "Inter, ui-sans-serif, system-ui, -apple-system, Segoe UI, Roboto, Arial, sans-serif",
};

const cardStyle: React.CSSProperties = {
  border: "1px solid rgba(255,255,255,0.08)",
  borderRadius: 24,
  background: "rgba(255,255,255,0.03)",
  boxShadow: "0 20px 60px rgba(0,0,0,0.25)",
};

const inputStyle: React.CSSProperties = {
  width: "100%",
  borderRadius: 14,
  border: "1px solid rgba(255,255,255,0.10)",
  background: "rgba(255,255,255,0.04)",
  color: "#fafafa",
  padding: "12px 14px",
  outline: "none",
};

function formatBytes(bytes: number): string {
  if (bytes < 1024) return bytes + " B";
  if (bytes < 1024 * 1024) return (bytes / 1024).toFixed(1) + " KB";
  return (bytes / (1024 * 1024)).toFixed(2) + " MB";
}

function SectionTitle({ title, text }: { title: string; text: string }) {
  return (
    <div style={{ marginBottom: 18 }}>
      <div style={{ fontSize: 26, fontWeight: 700 }}>{title}</div>
      <div style={{ marginTop: 8, color: "#a1a1aa", lineHeight: 1.7 }}>{text}</div>
    </div>
  );
}

export default function App() {
  const [data, setData] = useState<ExportModel | null>(null);
  const [error, setError] = useState<string>("");
  const [selectedBundleId, setSelectedBundleId] = useState<string>("");
  const [activeNav, setActiveNav] = useState<NavKey>("overview");
  const [running, setRunning] = useState<boolean>(false);
  const [result, setResult] = useState<BridgeResponse | null>(null);

  const [archiveInputDir, setArchiveInputDir] = useState("C:\\\\dev\\\\triad\\\\workbench\\\\demo\\\\archive_input");
  const [archiveDir, setArchiveDir] = useState("C:\\\\dev\\\\triad\\\\workbench\\\\demo\\\\archive_out");
  const [extractOutputDir, setExtractOutputDir] = useState("C:\\\\dev\\\\triad\\\\workbench\\\\demo\\\\archive_extract");

  const [transformType, setTransformType] = useState("trim_trailing_whitespace");
  const [transformInputPath, setTransformInputPath] = useState("C:\\\\dev\\\\triad\\\\workbench\\\\demo\\\\transform_input.txt");
  const [transformOutputPath, setTransformOutputPath] = useState("C:\\\\dev\\\\triad\\\\workbench\\\\demo\\\\transform_output.txt");
  const [transformManifestPath, setTransformManifestPath] = useState("C:\\\\dev\\\\triad\\\\workbench\\\\demo\\\\transform_output.txt.transform_manifest.json");

  async function loadExport() {
    const res = await fetch("/triad.workbench.export.v1.json", { cache: "no-store" });
    if (!res.ok) throw new Error("Failed to load workbench export");
    const json: ExportModel = await res.json();
    setData(json);
    setSelectedBundleId((prev) => prev || json.canonical_bundle.bundle_id);
  }

  useEffect(() => {
    loadExport().catch((err: Error) => setError(err.message));
  }, []);

  const selectedBundle = useMemo(() => {
    if (!data) return null;
    return data.bundles.find((b) => b.bundle_id === selectedBundleId) ?? data.bundles[0] ?? null;
  }, [data, selectedBundleId]);

  const navItems: { key: NavKey; label: string }[] = [
    { key: "overview", label: "Overview" },
    { key: "bundles", label: "Bundles" },
    { key: "engines", label: "Engines" },
    { key: "commands", label: "Commands" },
    { key: "verification", label: "Verification" },
  ];

  async function runAction(payload: Record<string, string>) {
    setRunning(true);
    setResult(null);
    try {
      const res = await fetch("/api/triad-action", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });

      if (!res.ok) throw new Error("Bridge request failed");

      const json: BridgeResponse = await res.json();
      setResult(json);

      if (json.archive_input) setArchiveInputDir(json.archive_input);
      if (json.archive_dir) setArchiveDir(json.archive_dir);
      if (json.extract_dir) setExtractOutputDir(json.extract_dir);
      if (json.input_path) setTransformInputPath(json.input_path);
      if (json.output_path) setTransformOutputPath(json.output_path);
      if (json.manifest_path) setTransformManifestPath(json.manifest_path);

      if (json.ok) {
        const exportUrl = "/triad.workbench.export.v1.json?ts=" + Date.now().toString();
        const exportRes = await fetch(exportUrl, { cache: "no-store" });
        if (exportRes.ok) {
          const exportJson: ExportModel = await exportRes.json();
          setData(exportJson);
        }
      }
    } catch (err) {
      const message = err instanceof Error ? err.message : "Unknown bridge error";
      setResult({
        ok: false,
        action: payload.action ?? "unknown",
        exit_code: 1,
        stdout: "",
        stderr: message,
      });
    } finally {
      setRunning(false);
    }
  }

  if (error) {
    return (
      <div style={shellStyle}>
        <div style={{ maxWidth: 960, margin: "0 auto", padding: 32 }}>
          <div style={{ ...cardStyle, padding: 28 }}>
            <div style={{ fontSize: 14, color: "#fca5a5" }}>Workbench load error</div>
            <h1 style={{ marginTop: 8, marginBottom: 0, fontSize: 36 }}>TRIAD Workbench</h1>
            <pre style={{ marginTop: 20, padding: 16, borderRadius: 18, background: "rgba(0,0,0,0.3)", color: "#e4e4e7", overflowX: "auto" }}>
{error}
            </pre>
          </div>
        </div>
      </div>
    );
  }

  if (!data) {
    return (
      <div style={shellStyle}>
        <div style={{ maxWidth: 960, margin: "0 auto", padding: 32 }}>
          <div style={{ ...cardStyle, padding: 28 }}>
            <div style={{ fontSize: 14, color: "#a1a1aa" }}>Loading</div>
            <h1 style={{ marginTop: 8, marginBottom: 0, fontSize: 36 }}>TRIAD Workbench</h1>
          </div>
        </div>
      </div>
    );
  }

  const renderResultPanel = () => (
    <div style={{ ...cardStyle, padding: 22, marginTop: 22 }}>
      <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", gap: 12 }}>
        <div style={{ fontSize: 22, fontWeight: 700 }}>Run Console</div>
        {running ? (
          <div style={{ fontSize: 13, color: "#fde68a" }}>Running…</div>
        ) : result ? (
          <div style={{ fontSize: 13, color: result.ok ? "#86efac" : "#fca5a5" }}>
            {result.ok ? "Success" : "Failed"} · exit {result.exit_code}
          </div>
        ) : (
          <div style={{ fontSize: 13, color: "#a1a1aa" }}>Idle</div>
        )}
      </div>

      {!result ? (
        <div style={{ marginTop: 14, color: "#a1a1aa", lineHeight: 1.7 }}>
          Trigger a workbench action to see stdout, stderr, and result state here.
        </div>
      ) : (
        <div style={{ display: "grid", gap: 14, marginTop: 16 }}>
          <div style={{ borderRadius: 18, background: "rgba(255,255,255,0.03)", padding: 14 }}>
            <div style={{ fontSize: 13, color: "#a1a1aa" }}>Action</div>
            <div style={{ marginTop: 6, fontSize: 15, fontWeight: 600 }}>{result.action}</div>
          </div>
          <div style={{ borderRadius: 18, background: "rgba(0,0,0,0.24)", padding: 14 }}>
            <div style={{ fontSize: 13, color: "#a1a1aa" }}>stdout</div>
            <pre style={{ marginTop: 8, whiteSpace: "pre-wrap", color: "#d4d4d8", overflowX: "auto" }}>
{result.stdout || "(empty)"}
            </pre>
          </div>
          <div style={{ borderRadius: 18, background: "rgba(0,0,0,0.24)", padding: 14 }}>
            <div style={{ fontSize: 13, color: "#a1a1aa" }}>stderr</div>
            <pre style={{ marginTop: 8, whiteSpace: "pre-wrap", color: "#f5b4b4", overflowX: "auto" }}>
{result.stderr || "(empty)"}
            </pre>
          </div>
        </div>
      )}
    </div>
  );

  const renderOverview = () => (
    <>
      <div
        style={{
          ...cardStyle,
          padding: 32,
          background:
            "radial-gradient(circle at top left, rgba(16,185,129,0.18), transparent 30%), linear-gradient(180deg, rgba(255,255,255,0.04), rgba(255,255,255,0.02))",
        }}
      >
        <div style={{ fontSize: 14, color: "#a1a1aa" }}>{data.product.name} · {data.product.release_label}</div>
        <h1 style={{ marginTop: 10, marginBottom: 0, fontSize: 44, lineHeight: 1.05 }}>TRIAD Workbench</h1>
        <p style={{ marginTop: 16, maxWidth: 760, color: "#a1a1aa", lineHeight: 1.8 }}>
          Premium local-first operator surface for verified runs, proof bundles, transcripts, hashes, and external verification workflows.
        </p>

        <div style={{ display: "grid", gridTemplateColumns: "repeat(4, minmax(0,1fr))", gap: 16, marginTop: 24 }}>
          <div style={{ ...cardStyle, padding: 18 }}>
            <div style={{ fontSize: 12, color: "#a1a1aa", textTransform: "uppercase", letterSpacing: "0.14em" }}>Release state</div>
            <div style={{ marginTop: 10, fontSize: 26, fontWeight: 700 }}>{data.summary.release_state}</div>
          </div>
          <div style={{ ...cardStyle, padding: 18 }}>
            <div style={{ fontSize: 12, color: "#a1a1aa", textTransform: "uppercase", letterSpacing: "0.14em" }}>Latest run</div>
            <div style={{ marginTop: 10, fontSize: 16, fontWeight: 600 }}>{data.summary.latest_verified_run_utc}</div>
          </div>
          <div style={{ ...cardStyle, padding: 18 }}>
            <div style={{ fontSize: 12, color: "#a1a1aa", textTransform: "uppercase", letterSpacing: "0.14em" }}>Bundles</div>
            <div style={{ marginTop: 10, fontSize: 26, fontWeight: 700 }}>{data.summary.bundle_count}</div>
          </div>
          <div style={{ ...cardStyle, padding: 18 }}>
            <div style={{ fontSize: 12, color: "#a1a1aa", textTransform: "uppercase", letterSpacing: "0.14em" }}>Engines</div>
            <div style={{ marginTop: 10, fontSize: 26, fontWeight: 700 }}>{data.summary.engine_count}</div>
          </div>
        </div>
      </div>

      <div style={{ ...cardStyle, padding: 22, marginTop: 22 }}>
        <div style={{ fontSize: 22, fontWeight: 700 }}>Quick Actions</div>
        <div style={{ marginTop: 8, color: "#a1a1aa" }}>Verified release flows the downloadable workbench should support.</div>
        <div style={{ display: "grid", gap: 12, marginTop: 18 }}>
          <button
            onClick={() => runAction({ action: "run_verified_release" })}
            disabled={running}
            style={{
              borderRadius: 18,
              padding: 14,
              border: "1px solid rgba(16,185,129,0.35)",
              background: "rgba(16,185,129,0.10)",
              color: "#fafafa",
              textAlign: "left",
              cursor: "pointer",
              opacity: running ? 0.65 : 1,
            }}
          >
            Run Verified Full-System Pass
          </button>
        </div>
      </div>

      {renderResultPanel()}
    </>
  );

  const renderBundles = () => (
    <div style={{ display: "grid", gridTemplateColumns: "1.25fr 1fr", gap: 18 }}>
      <div style={{ ...cardStyle, padding: 22 }}>
        <SectionTitle title="Proof Bundles" text="Canonical release evidence and recent verified runs." />
        <div style={{ display: "grid", gap: 12 }}>
          {data.bundles.map((bundle) => (
            <button
              key={bundle.bundle_id}
              onClick={() => setSelectedBundleId(bundle.bundle_id)}
              style={{
                textAlign: "left",
                borderRadius: 20,
                border: selectedBundle?.bundle_id === bundle.bundle_id
                  ? "1px solid rgba(16,185,129,0.35)"
                  : "1px solid rgba(255,255,255,0.08)",
                background: selectedBundle?.bundle_id === bundle.bundle_id
                  ? "rgba(16,185,129,0.08)"
                  : "rgba(255,255,255,0.03)",
                padding: 16,
                color: "#fafafa",
                cursor: "pointer",
              }}
            >
              <div style={{ display: "flex", alignItems: "start", justifyContent: "space-between", gap: 12 }}>
                <div>
                  <div style={{ fontSize: 16, fontWeight: 600 }}>{bundle.label}</div>
                  <div style={{ marginTop: 4, fontSize: 13, color: "#a1a1aa" }}>{bundle.created_utc}</div>
                </div>
                {bundle.pinned ? <div style={{ fontSize: 12, color: "#86efac" }}>Pinned</div> : bundle.latest ? <div style={{ fontSize: 12, color: "#d4d4d8" }}>Latest</div> : null}
              </div>
            </button>
          ))}
        </div>
      </div>

      <div style={{ ...cardStyle, padding: 22 }}>
        <SectionTitle title={selectedBundle?.label ?? "Bundle"} text={selectedBundle?.path ?? ""} />
        <div style={{ display: "grid", gap: 12 }}>
          {(selectedBundle?.artifacts ?? []).map((artifact) => (
            <div key={artifact.name} style={{ borderRadius: 18, background: "rgba(0,0,0,0.24)", padding: 14 }}>
              <div style={{ fontSize: 15, fontWeight: 600 }}>{artifact.name}</div>
              <div style={{ marginTop: 6, fontSize: 12, color: "#a1a1aa" }}>{artifact.path}</div>
              <div style={{ marginTop: 8, fontSize: 12, color: "#d4d4d8" }}>{formatBytes(artifact.bytes)} · {artifact.sha256}</div>
            </div>
          ))}
        </div>
      </div>
    </div>
  );

  const renderEngines = () => (
    <div style={{ display: "grid", gap: 18 }}>
      <div style={{ ...cardStyle, padding: 22 }}>
        <SectionTitle title="Restore Engine" text="Use the release runner as the current verified restore surface." />
        <button
          onClick={() => runAction({ action: "run_verified_release" })}
          disabled={running}
          style={{
            borderRadius: 18,
            padding: 14,
            border: "1px solid rgba(16,185,129,0.35)",
            background: "rgba(16,185,129,0.10)",
            color: "#fafafa",
            textAlign: "left",
            cursor: "pointer",
            opacity: running ? 0.65 : 1,
          }}
        >
          Run Verified Full-System Pass
        </button>
      </div>

      <div style={{ ...cardStyle, padding: 22 }}>
        <SectionTitle title="Archive Engine" text="Reset a clean demo workspace first, then pack, verify, and extract." />
        <div style={{ display: "grid", gap: 12 }}>
          <input value={archiveInputDir} onChange={(e) => setArchiveInputDir(e.target.value)} placeholder="Input directory" style={inputStyle} />
          <input value={archiveDir} onChange={(e) => setArchiveDir(e.target.value)} placeholder="Archive directory" style={inputStyle} />
          <input value={extractOutputDir} onChange={(e) => setExtractOutputDir(e.target.value)} placeholder="Extract output directory" style={inputStyle} />

          <div style={{ display: "grid", gridTemplateColumns: "repeat(4, minmax(0,1fr))", gap: 12 }}>
            <button onClick={() => runAction({ action: "archive_reset_demo" })} disabled={running} style={{ ...inputStyle, cursor: "pointer", textAlign: "center", background: "rgba(255,255,255,0.08)" }}>Reset Demo</button>
            <button onClick={() => runAction({ action: "archive_pack", inputPath: archiveInputDir, archiveDir })} disabled={running} style={{ ...inputStyle, cursor: "pointer", textAlign: "center", background: "rgba(255,255,255,0.08)" }}>Pack</button>
            <button onClick={() => runAction({ action: "archive_verify", archiveDir })} disabled={running} style={{ ...inputStyle, cursor: "pointer", textAlign: "center", background: "rgba(255,255,255,0.08)" }}>Verify</button>
            <button onClick={() => runAction({ action: "archive_extract", archiveDir, outputPath: extractOutputDir })} disabled={running} style={{ ...inputStyle, cursor: "pointer", textAlign: "center", background: "rgba(255,255,255,0.08)" }}>Extract</button>
          </div>
        </div>
      </div>

      <div style={{ ...cardStyle, padding: 22 }}>
        <SectionTitle title="Transform Engine" text="Reset a clean demo input first, then apply and verify transforms." />
        <div style={{ display: "grid", gap: 12 }}>
          <input value={transformType} onChange={(e) => setTransformType(e.target.value)} placeholder="Transform type" style={inputStyle} />
          <input value={transformInputPath} onChange={(e) => setTransformInputPath(e.target.value)} placeholder="Input path" style={inputStyle} />
          <input value={transformOutputPath} onChange={(e) => setTransformOutputPath(e.target.value)} placeholder="Output path" style={inputStyle} />
          <input value={transformManifestPath} onChange={(e) => setTransformManifestPath(e.target.value)} placeholder="Manifest path" style={inputStyle} />

          <div style={{ display: "grid", gridTemplateColumns: "repeat(3, minmax(0,1fr))", gap: 12 }}>
            <button onClick={() => runAction({ action: "transform_reset_demo" })} disabled={running} style={{ ...inputStyle, cursor: "pointer", textAlign: "center", background: "rgba(255,255,255,0.08)" }}>Reset Demo</button>
            <button onClick={() => runAction({ action: "transform_apply", transformType, inputPath: transformInputPath, outputPath: transformOutputPath })} disabled={running} style={{ ...inputStyle, cursor: "pointer", textAlign: "center", background: "rgba(255,255,255,0.08)" }}>Apply</button>
            <button onClick={() => runAction({ action: "transform_verify", manifestPath: transformManifestPath })} disabled={running} style={{ ...inputStyle, cursor: "pointer", textAlign: "center", background: "rgba(255,255,255,0.08)" }}>Verify</button>
          </div>
        </div>
      </div>

      {renderResultPanel()}
    </div>
  );

  const renderCommands = () => (
    <div style={{ ...cardStyle, padding: 22 }}>
      <SectionTitle title="Commands" text="Raw technical commands stay available behind the cleaner product shell." />
      <div style={{ display: "grid", gap: 12 }}>
        {data.commands.map((command) => (
          <div key={command.id} style={{ borderRadius: 18, background: "rgba(0,0,0,0.24)", padding: 14 }}>
            <div style={{ fontSize: 15, fontWeight: 600 }}>{command.label}</div>
            <pre style={{ marginTop: 10, whiteSpace: "pre-wrap", color: "#d4d4d8", overflowX: "auto" }}>
{command.command}
            </pre>
          </div>
        ))}
      </div>
    </div>
  );

  const renderVerification = () => (
    <div style={{ display: "grid", gap: 18 }}>
      <div style={{ ...cardStyle, padding: 22 }}>
        <SectionTitle title="Verification" text="Use this surface to guide clean-machine validation and proof review." />
        <div style={{ display: "grid", gap: 12 }}>
          <div style={{ borderRadius: 18, background: "rgba(255,255,255,0.03)", padding: 16 }}>
            <div style={{ fontSize: 15, fontWeight: 600 }}>Release state</div>
            <div style={{ marginTop: 8, color: "#a1a1aa" }}>{data.summary.release_state}</div>
          </div>
          <div style={{ borderRadius: 18, background: "rgba(255,255,255,0.03)", padding: 16 }}>
            <div style={{ fontSize: 15, fontWeight: 600 }}>Canonical proof bundle</div>
            <div style={{ marginTop: 8, color: "#a1a1aa" }}>{data.canonical_bundle.path}</div>
          </div>
          <div style={{ borderRadius: 18, background: "rgba(255,255,255,0.03)", padding: 16 }}>
            <div style={{ fontSize: 15, fontWeight: 600 }}>External verification clone</div>
            <pre style={{ marginTop: 10, whiteSpace: "pre-wrap", color: "#d4d4d8", overflowX: "auto" }}>git clone https://github.com/ScrappyHub/triad.git{"\n"}cd triad</pre>
          </div>
        </div>
      </div>
      {renderResultPanel()}
    </div>
  );

  return (
    <div style={shellStyle}>
      <div style={{ display: "flex", minHeight: "100vh" }}>
        <aside style={{ width: 270, borderRight: "1px solid rgba(255,255,255,0.08)", background: "rgba(0,0,0,0.2)", padding: 20 }}>
          <div style={{ ...cardStyle, padding: 18, marginBottom: 20 }}>
            <div style={{ fontSize: 13, color: "#a1a1aa" }}>{data.product.release_label}</div>
            <div style={{ marginTop: 8, fontSize: 22, fontWeight: 700 }}>{data.product.workbench_label}</div>
            <div style={{ marginTop: 8, color: "#a1a1aa", fontSize: 14 }}>Local-first operator surface</div>
          </div>

          <div style={{ display: "grid", gap: 10 }}>
            {navItems.map((item) => (
              <button
                key={item.key}
                onClick={() => setActiveNav(item.key)}
                style={{
                  borderRadius: 16,
                  padding: "12px 14px",
                  background: activeNav === item.key ? "rgba(16,185,129,0.12)" : "rgba(255,255,255,0.04)",
                  border: activeNav === item.key ? "1px solid rgba(16,185,129,0.28)" : "1px solid rgba(255,255,255,0.08)",
                  color: "#e4e4e7",
                  fontSize: 14,
                  textAlign: "left",
                  cursor: "pointer",
                }}
              >
                {item.label}
              </button>
            ))}
          </div>

          <div style={{ ...cardStyle, padding: 18, marginTop: 20 }}>
            <div style={{ fontSize: 12, color: "#a1a1aa", textTransform: "uppercase", letterSpacing: "0.14em" }}>Canonical bundle</div>
            <div style={{ marginTop: 10, fontSize: 15, fontWeight: 600 }}>{data.canonical_bundle.display_name}</div>
            <div style={{ marginTop: 8, fontSize: 13, color: "#a1a1aa" }}>{data.canonical_bundle.created_utc}</div>
          </div>
        </aside>

        <main style={{ flex: 1, padding: 28 }}>
          {activeNav === "overview" && renderOverview()}
          {activeNav === "bundles" && renderBundles()}
          {activeNav === "engines" && renderEngines()}
          {activeNav === "commands" && renderCommands()}
          {activeNav === "verification" && renderVerification()}
        </main>
      </div>
    </div>
  );
}

\# TRIAD Release Steps v1



\## 1. Confirm CLI entrypoint exists



Required file:





scripts\\triad\_cli\_v1.ps1





\---



\## 2. Confirm verified release passes



```powershell

powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass `

&#x20; -File .\\scripts\\triad\_cli\_v1.ps1 `

&#x20; -RepoRoot . `

&#x20; -Command verify-release



Expected output:



TRIAD\_TIER0\_FULL\_GREEN

3\. Confirm proof bundle is emitted



Inspect latest directory under:



proofs\\freeze\\



Required artifacts:



transcript (full\_green\_transcript.txt)

sha256 inventory (sha256sums.txt)

freeze receipt (triad.freeze.receipt.json)


\# TRIAD Release Checklist v1



\## Required Conditions



\- FULL\_GREEN runner passes

\- restore positives and negatives pass

\- archive positives and negatives pass

\- transform positives and negatives pass

\- freeze bundle generated

\- canonical freeze pinned

\- README present

\- operator runbook present

\- proof map present

\- external verification instructions present



\## Release Gate



Release is valid only if:



\- a fresh clone can run the full-green runner

\- `TRIAD\_TIER0\_FULL\_GREEN` is emitted

\- freeze bundle artifacts are written

\- verification requires no mutation



\## Canonical Freeze



\- `proofs\\freeze\\triad\_tier0\_green\_20260409`



\## Release Tag



\- `triad-tier0-v1`


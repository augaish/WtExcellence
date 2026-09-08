# Rollback checkpoints

Tag pushes are rejected by this git proxy, so use the **commit SHA** — every one
of these is on `origin/claude/determined-euler-gkr9sv`.

| Checkpoint | SHA | What it is |
|---|---|---|
| `baseline-before-pp` | `669e0e3` | Before any P&P work. Module entitlements shipped. |
| `pp-phase1-complete` | `7b1af0c` | Phase 0 (nav) + Phase 1 (Org Structure, Process Architecture). |
| `suite-green` | `b1a721c` | Audit-log savepoint fix; whole test suite green for the first time. |
| `pp-phase2-complete` | `d8c37c6` | Phase 2 (Records + Packages). |
| `pp-phase3-complete` | `fc89941` | Phase 3 (Documenter: 17-stage lifecycle). |
| `pp-phase4-complete` | `ab95189` | Phase 4 (Process Architect: structured editor + SVG swimlanes). |
| `pp-phase5-complete` | `e4be5fa` | Phase 5 (Efficiency Evaluation). |
| `pp-phase6-complete` | *(this commit)* | Phase 6 (Monitoring widgets). P&P module complete. |
| `review-phase0a` | `4e432c1` | Review fixes: the two 500s (ActiveStorage URL options), evidence-reuse heading, record links on documents. |
| `review-phase0b` | `f94570e` | One permission-aware navigation definition behind the sidebar and the mobile menu. |
| `review-phase0c` | `43974d6` | Upload folder destination, document metadata editing, AI credit ledger. |
| `review-phase0d` | `2cc054a` | Editable AI drafts; risk closure requires a justification. |
| `phase-a-foundations` | *(this commit)* | Authority levels, classification, DoA/SLA/glossary record types, glossary + references, company branding. |
| `phase-b-procedure` | *(this commit)* | Procedure steps with computed totals; operational authority matrix with its rules. |
| `governance-slice-1` | *(this commit)* | Commitment timing vs workflow state, fulfilment basis, locale guard, English audit-log repair. |
| `phase-c-documents` | *(this commit)* | Governed document assembly and branded print-ready rendering. |
| `phase-d-executive-doa` | *(this commit)* | Executive authority matrix: categories, authorities, threshold bands, dynamic roles, findings. |

## Roll the code back
```bash
ssh wtexcel
cd /root && rm -rf wtdeploy \
  && git clone https://github.com/augaish/wtexcellence.git wtdeploy \
  && cd wtdeploy && git checkout <SHA> \
  && bash scripts/server_deploy.sh
```

## Back up the database (do this BEFORE every deploy)
```bash
bash scripts/backup_db.sh <label>     # writes /root/backups/wtexcel_<label>_<stamp>.sql.gz
```

## Restore a database dump
```bash
gunzip -c /root/backups/<file>.sql.gz | docker exec -i wtexcel-db psql -U postgres -d way_to_excellence
```

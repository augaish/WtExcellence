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
| `pp-phase6-complete` | `ce502ec` | Phase 6 (Monitoring widgets). P&P module complete. |
| `review-phase0a` | `4e432c1` | Review fixes: the two 500s (ActiveStorage URL options), evidence-reuse heading, record links on documents. |
| `review-phase0b` | `f94570e` | One permission-aware navigation definition behind the sidebar and the mobile menu. |
| `review-phase0c` | `43974d6` | Upload folder destination, document metadata editing, AI credit ledger. |
| `review-phase0d` | `2cc054a` | Editable AI drafts; risk closure requires a justification. |
| `phase-a-foundations` | `38a99a9` | Authority levels, classification, DoA/SLA/glossary record types, glossary + references, company branding. |
| `phase-b-procedure` | `d51238f` | Procedure steps with computed totals; operational authority matrix with its rules. |
| `governance-slice-1` | `165db96` | Commitment timing vs workflow state, fulfilment basis, locale guard, English audit-log repair. |
| `phase-c-documents` | `defb17a` | Governed document assembly and branded print-ready rendering. |
| `phase-d-executive-doa` | `aec6e90` | Executive authority matrix: categories, authorities, threshold bands, dynamic roles, findings. |
| `phase-e-intelligence` | `f9a863a` | Conformance check, matrix version diff, consultation rounds. |
| `phase-f-delegations` | `1cc7898` | Delegations: position-to-position, expiry, sub-delegation, effective authority. |
| `phase-g-governance` | *(this commit)* | Activity trail, governance evidence, risk methodology, F12. |
| `phase-g-orgchart` | *(this commit)* | Org chart view; thread-local actor leak fixed. |
| `sla-and-expiry` | *(this commit)* | Service levels on agreements; delegation expiry notices; register filters. |
| `docx-export` | *(this commit)* | Word export of governed documents, right-to-left aware. |
| `retest-batches` | *(this commit)* | Second-review fixes: answer persistence, pools vs lanes, matrix redesign, executive matrix in documents, SLA output, diagram drawn from steps. |
| `retest-batch-three` | *(this commit)* | Retry this question; rejected forms keep values; formatted AI answers and live balance; accessibility pass; Gate C delegation matrix; published-version immutability. |
| Phase 1 of records/documenter plan: Arabic chart labels, library folders from org, settings tabs, per-tab add button | `71a0c1b` | Additive migration: `org_unit_id` on folders |
| Phase 2: Process Architecture Level 0/1/2, model view, architecture settings | `39a45af` | **Destructive migration**: empties pp_processes, steps, authorities, process diagrams (test data, per owner); adds `number` to pp_processes and band names/objective to companies. Restore from the pre-deploy backup to get the rows back. |
| Phase 3: Records journeys per type, auto codes, "Update existing" versions, authoring rule | `72e266f` | Additive migration: journey fields on pp_records, pp_record_links, pp_record_participants. Procedures now require a level-2 process. |
| Phase 4: Documenter flows (roles, clauses, steps on procedures, stakeholder/final approvals, publishing with PDF) | `9bb61dd` | **Destructive migration**: clears every record except the authority matrices, plus stage history, approvals, tasks, record diagrams (test data, per owner). Adds `pp_manager` on company_users, clause/comment/task tables, decision columns on approvals, journey columns on records, `pp_record_id` on steps. Docker image now installs Chromium (`CHROMIUM_BIN`). Restore from the pre-deploy backup to get rows back. |
| Phase 5: branding preview + app-served logo, Authorities redesign (no bands, ordered categories, review round, Governance Manager), operational DoA on procedure steps, org tab polish | `058a73f` | Additive migration: `gov_manager` on company_users, `limit_text` on authorities, `authority_matrix_reviews`, record/step links on pp_process_authorities. Level names for org units are no longer shown (table kept). |
| Licence rule across modules + P&P split into three switches (Process Architecture, P&P, Authorities & Delegations) | `8a0a4fc` | No migration. New module keys default to on. |

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
The script verifies its own output — table count before the dump, then size,
gzip integrity, pg_dump's completion marker and a CREATE TABLE count after it —
and exits non-zero rather than leaving an archive that cannot be restored. If it
prints "Verified", the backup is real. Anything else means you have no backup.

## Restore a database dump
The database is `wtexcel_prod`, owned by `wtexcel` — not the `postgres` defaults
an earlier version of this file assumed. Read the credentials from the container
rather than typing them, so a rename cannot silently break the restore:
```bash
DB_USER=$(docker exec wtexcel-db printenv POSTGRES_USER)
DB_NAME=$(docker exec wtexcel-db printenv POSTGRES_DB)
DB_PASSWORD=$(docker exec wtexcel-db printenv POSTGRES_PASSWORD)

gunzip -c /root/backups/<file>.sql.gz \
  | docker exec -i -e PGPASSWORD="$DB_PASSWORD" wtexcel-db \
      psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1
```
`ON_ERROR_STOP=1` matters: without it psql reports success after skipping every
statement it could not apply, which is how a half-restored database gets
mistaken for a restored one.

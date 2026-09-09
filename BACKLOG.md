# Parked work

Things deliberately not done, with the reason. Kept here rather than in a
conversation, so nothing depends on anyone remembering it.

Ordered by what I would do first.

## Security

**Rotate the leaked development database password.** The literal password has
been removed from `config/database.yml` — credentials now come from
`DATABASE_USER`, `DATABASE_PASSWORD`, `DATABASE_HOST` — but removing it from the
file does not remove it from git history. Anyone with repository access can
still read it, so the password itself has to be changed anywhere it was used.
Production was never exposed: it connects through `DATABASE_URL` from Kamal
secrets.

To run locally after this change:
```
export DATABASE_HOST=localhost DATABASE_PASSWORD=<your local password>
```

The wider point is reuse: a password in a repository is only dangerous where it
still opens something. If that value was used anywhere else — a server login,
another database, an account — change it there too.

Checked and clean: config/master.key is not committed, .env files are ignored,
and no API keys or production credentials appear in tracked files. Production
connects with different credentials entirely.

**Security review of the repository and platform — after testing.** Deferred
deliberately, because doing it properly needs decisions rather than commands:

  * whether the repository should be private, and who currently has access to it;
  * whether the leaked development password was reused anywhere that still
    matters (a server login, another database, an account) — this is the only
    part with real exposure, since the database it guarded is local-only and
    production uses different credentials entirely;
  * whether to rewrite git history to remove the value. The steps work, but
    every commit hash changes, so every SHA in ROLLBACK.md stops resolving,
    existing clones break, and old commits stay reachable by URL until GitHub
    collects them. It removes the embarrassment rather than the risk;
  * secret handling more broadly: where Kamal secrets live, who can read them,
    and whether anything else would be exposed by repository access.

Nothing here blocks testing. Checked and currently clean: config/master.key is
not committed, .env files are ignored, no API keys or production credentials
appear in tracked files, and the demo seeds can no longer run outside
development.

## From the second review (retest)

Gates A and B are addressed on this branch, and the Gate C delegation matrix is
proven by tests with a controllable clock. What remains:

| | Item | State |
|---|---|---|
| R17 (part) | Full WCAG 2.2 AA audit | The sampled gaps are closed: every CAPA modal control is named, the row menu is a named keyboard control, the org chart exposes its nodes and offers a textual tree, statuses are translated and dates carry no time. A full audit with a screen reader has not been done. |
| Gate C (part) | Effective-authority enforcement at decision points | The question "who may decide this today" is answered (EffectiveAuthority); no screen yet refuses an action on that basis. |
| Email | Delegation expiry by email | Needs the platform notification policy decided first. |

## Correctness — review findings not yet fixed

From the 8 September platform review. All P1s are done; these are the P2s and
P3s, with the ones that mislead a user first.

| | Finding | Why it is still open |
|---|---|---|
| F08 | CAPA document picker rendered blank | **Believed already fixed, needs confirming in the browser.** The API now returns .txt, .pdf and .docx correctly and is covered by tests, and the client has working empty and error states. The most likely original cause was the ActiveStorage URL failure that made two other pages return 500, repaired in the first batch of review fixes. Retest with a PDF before closing. |
| F18 | Incomplete accessible names | A targeted observation, not a full audit. Worth doing properly against WCAG 2.2 AA rather than patching the named controls. |
| F22-b | Saved views and export on the registers | Search and work queues are done. Saving a view, and exporting with the filters applied, are not. |
| F23 | Library form feedback and folder context | Partly addressed by the F04 destination notice; the empty-upload error and the "Everyone" visibility label remain. |
| F24 | Dense tables hide actions at 1280px | |

**Two `saveRootCause` methods** are defined in
`app/javascript/controllers/capas/questionnaire_controller.js`; the second
silently overrides the first. Only one is reachable, so behaviour is correct,
but the dead one should go once someone can confirm which was intended.

**Average resolution time is approximate.** It measures `created_at` to
`updated_at` on closed CAPAs, and `updated_at` moves on any edit, so the figure
is a proxy rather than a resolution time. Fixing it properly needs a `closed_at`
stamped when the status changes, at which point the number can be trusted and
the caption can say so.

## Data integrity

**`PROCESS_REQUIRED_TYPES` is declared but only enforced for `operational_doa`.**
The rule has existed since the P&P module was built without ever being
validated, so procedures, work instructions and forms may exist in production
with no process attached. Enforcing it retroactively would make those records
uneditable. Needs a production count first:

```
PpRecord.where(record_type: %w[procedure work_instruction form], pp_process_id: nil).count
```

If it is zero, enforce it. If not, the records need fixing before the rule can
apply.

## Delegation of Authority — completing the module

**Expiry emails.** In-app notification is done — DelegationExpiryNoticeJob runs
daily and tells the heads of both positions. Email delivery of the same notice
is not, and needs a decision about which notifications should reach an inbox at
all rather than adding one mailer in isolation.

**Authority breaches into CAPA.** The source document has Internal Audit produce
an annual report of non-compliance with the matrix. The findings are already
computed continuously by `AuthorityMatrixReport` and
`AuthorityConformanceCheck`; what is missing is raising a CAPA from one, which
the governance→CAPA path already supports for risks and vendors.

**Exercise log.** Recording that an authority was used — by whom, on what
decision — which is what turns the matrix from a statement of intent into
evidence. Sized as its own phase.

## Documents

**Images in the Word version.** The .docx carries every section except the
procedure diagram, which says in the file that it is only in the browser.
Embedding it needs the SVG converted to a raster or EMF and added as a media
part with its own relationship — worth doing once someone has said the Word
output is otherwise right.

**SLA reporting.** Service levels are recorded and printed — parties, targets,
measurement method, coverage and remedy. What does not exist is measuring
against them: recording actual performance per period and reporting attainment.
That is a module of its own, and worth scoping only once real agreements exist.

## Governance modules

**Risk, Vendor and Customer Commitments lifecycles** — sections 5 to 8 of the
review. The shared chassis (ownership, evidence, activity history,
relationships, notifications) plus each module's own lifecycle. Comparable in
size to the whole P&P module. This is the current phase.

## Deployment

**Sidekiq containers run `db:migrate` on boot.** They share the web
entrypoint, so every container migrates on start. Rails takes an advisory lock
so it is safe, but on a multi-migration deploy they queue behind each other.
Belongs in a Kamal pre-deploy hook instead.

**No CI deploy pipeline.** Deployment depends on someone with SSH access
running a script. A GitHub Actions workflow would remove that dependency.

## Product

**Level 3 of the process tree.** Fills in as procedures attach to level-2
processes; nothing to build until there is content to hang on it.

## Records journeys (Phase 3) — follow-ups
- Glossary: the "glossary" record type now holds term + definition. The older `GlossaryTerm` table (terms linked to documents for the Definitions section) still exists; when the glossary flow is built in Phase 4, an approved glossary record should create/refresh its `GlossaryTerm` so documents keep pulling definitions from one place.
- Procedure steps still hang off `PpProcess`; Phase 4 moves them to the procedure record (and the diagram with them).
- Existing procedure records without a level-2 process are now invalid on edit (rule requested by the owner). Prod had only test data.

## Documenter (Phase 4) — follow-ups
- Chromium is installed by the Dockerfile; the first deploy after this rebuilds the image. If `RecordPdfRenderer.available?` is false in production the record publishes without a PDF and the log says so — check `kamal app exec 'bin/rails runner "puts RecordPdfRenderer.available?"'` after deploy.
- Help topics still describe the old lifecycle stages; rewrite `_policies_procedures` for the new flows.
- The Records index "stage" column and the monitoring funnel use the new stages; the P&P dashboard tiles were not redesigned.
- Email for Documenter notices stays in-app only (owner's choice).

## Phase 5 — follow-ups
- Licence rule is applied across Governance, P&P, Standards and the Library. CAPA and the AI tools stay closed to risk-manager licences (the owner named Standards and P&P only); say if CAPA should open for reading too.
- `authority_bands` table is kept with one default band per authority (the page no longer shows bands). Collapsing the table is a later cleanup.
- `org_level_definitions` table is kept but unused since levels are numbered only.


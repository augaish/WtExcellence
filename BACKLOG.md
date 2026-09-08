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

## Correctness — review findings not yet fixed

From the 8 September platform review. All P1s are done; these are the P2s and
P3s, with the ones that mislead a user first.

| | Finding | Why it is still open |
|---|---|---|
| F08 | CAPA document picker renders blank | Needs reproducing with PDF and DOCX before it can be called fixed; the review could only test a .txt file. |
| F14 | AI cost is not disclosed before the action | Inconsistent with Generate Actions, which does show its cost. |
| F15 | Ask AI describes controls that do not exist | Needs the answer grounded in the product manual and the current role's actions. |
| F18 | Incomplete accessible names | A targeted observation, not a full audit. Worth doing properly against WCAG 2.2 AA rather than patching the named controls. |
| F19 | Risk matrices swap axis convention between screens | Also needs an inherent/residual selector and an open/all population toggle. |
| F22 | Governance registers have no work queues | Filters, saved views, export. Best done once the shared governance chassis exists, or it gets built twice. |
| F23 | Library form feedback and folder context | Partly addressed by the F04 destination notice; the empty-upload error and the "Everyone" visibility label remain. |
| F24 | Dense tables hide actions at 1280px | |
| F25 | Help does not match navigation | The manual omits Org Structure, Process Architecture, Records and Packages. |

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

**Expiry notifications.** The data and the queries exist
(`AuthorityDelegation#expiring_soon?`, `.expiring_before`), and the matrix shows
the warning. What is missing is the scheduled job and the email, so a delegation
lapsing is only noticed by someone looking at the page.

**Authority breaches into CAPA.** The source document has Internal Audit produce
an annual report of non-compliance with the matrix. The findings are already
computed continuously by `AuthorityMatrixReport` and
`AuthorityConformanceCheck`; what is missing is raising a CAPA from one, which
the governance→CAPA path already supports for risks and vendors.

**Exercise log.** Recording that an authority was used — by whom, on what
decision — which is what turns the matrix from a statement of intent into
evidence. Sized as its own phase.

## Documents

**Real `.docx` output.** Phase C produces a branded, print-ready page and the
browser's Save as PDF. `RecordDocument` returns sections rather than markup
specifically so a DOCX writer is a second consumer rather than a rewrite. The
work is a new dependency or hand-rolled WordprocessingML, and Arabic RTL is the
hard part in either. Not started because there is no client template to fill.

**SLA content.** `sla` exists as a record type and inherits the whole document
chassis, but has no SLA-specific fields yet: service catalogue, parties,
response and resolution targets, measurement method, escalation, penalties.

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

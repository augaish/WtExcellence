# Plan: Org chart fixes, Process Architecture levels, Records journeys, Documenter flows

Status: DRAFT — awaiting answers to the open questions at the end. Nothing here is built yet.

## What exists today (relevant facts)

- Org chart: `OrgChartRenderer` draws SVG boxes with left-anchored text and character truncation. Arabic text is not right-anchored, so it runs outside the box.
- Library: `Folder` tree per company (parent/child, colour). No link between a folder and an org unit.
- Process Architecture: `PpProcess` has levels 1–3, category core/support/management, an "Add process" button and a list view only. Procedures are `PpRecord` rows linked to a process by `pp_process_id`.
- Records: one list with 11 types (policy, procedure, work_instruction, form, service, guideline, charter, executive_doa, operational_doa, sla, glossary). Versions: `version_number` + `previous_version_id` exist; only the authority matrix has "open next version".
- Documenter: 17 fixed stages in `PpStage` (s1_verify … s5_closed), one sequence for all types with a design branch for procedures. Stakeholder and final approvals are per org unit but are "marked received" by the quality manager, not answered by the unit head. Stage assignees are per record per stage. Settings page lives under Documenter.
- Roles: company_admin, company_quality_manager, company_risk_manager, company_auditor, company_contributor, company_viewer. Org units have a `head_user`; users belong to one org unit.
- Documents: `RecordDocument` builds the policy/procedure/SLA/DoA sections; `RecordDocxRenderer` produces Word. No PDF generator yet. Docker image has Poppler/Tesseract but no LibreOffice or headless Chromium.
- Steps (`PpProcessStep`) hang off `PpProcess`, not off the procedure record. Diagram ↔ steps sync exists (`DiagramStepSync`).
- No clause model. Glossary terms exist (`GlossaryTerm`) and can be linked to records.

## Phases (each: tests green, ROLLBACK checkpoint, deploy, you test)

### Phase 1 — Small fixes
1. Org chart Arabic: right-anchor text with `direction="rtl"`, wrap names to two lines, size boxes from text length.
2. "Build library folders" button on Org Structure: creates a folder tree mirroring the org tree (idempotent, folders remember their org unit via a new `org_unit_id` column; re-running adds missing units and renames moved ones, never deletes).
3. Move Documenter settings (targets, holidays) into a tab in General Settings.
4. "Add record" button reads "Add policy / Add procedure / …" per tab; a "Packages" button beside it.

### Phase 2 — Process Architecture
1. Top boxes become Level 0 / Level 1 / Level 2 with a "+" on each level that can be added (no "Add process" button).
2. Two views: List (current) and Model (bands Managerial / Core / Support as in the picture, Level 1 boxes, expand to Level 2, objective circle at the right).
3. Level 3 = procedures; they are created from Records, not here.
4. Data migration for existing level-3 processes (see Q3).

### Phase 3 — Records journeys
Tabs: All, Policies, Procedures, Forms, Services, Glossaries.
- New record vs Update existing: "Update" copies the current version into a new draft, bumps the version number, and requires "Reason for change".
- Policy / Form: title, auto code, description, scope, ownership (unit + user), version (auto), reason for change (on update).
- Procedure (picture 3): category → Level 1 → Level 2 dependent dropdowns, auto code, purpose, owner (unit), trigger, inputs, outputs, previous / next procedure (from records, editable later), frequency, total time (from steps), automation status, related policies (from records), systems used, forms used (from records), KPIs.
- Service (picture 4): name, auto code SEV-XX-XX, type internal/external, description, requirements, beneficiaries, delivery period, channels, providing unit (units), participating units (units), delivery stages.
- Glossary: term + definition only.

### Phase 4 — Documenter flows
Policy: Data Verification → Approved Addition → Initial Draft Preparation → Initial Draft Review → Stakeholder Review → Final Approval → Send for Publishing → Published.
Procedure: same, with Procedure Design → Design Review inserted after Stakeholder Review.
- New company setting: P&P Manager (a quality manager chosen by the admin in Account Management).
- Clauses model (main clause + sub-clauses) with per-clause comments; procedures use steps instead of clauses (steps move to the procedure record).
- Unit head screens: assign a contributor from the unit, review, approve / push back.
- Stakeholder Review and Final Approval: the chosen unit heads answer in their own worklist (read, comment, approve / reject); QM sees green / red / orange; options: auto-approve after N days of silence, parallel / sequential / mixed sending, "Skip — no stakeholders".
- Send for Publishing: either assign a publisher contributor (pastes link, presses Publish, QM confirms) or "publish in system only" (straight to Published).
- Published: PDF generated from the filled template, saved in the owner unit's library folder, notification to all company users.

## Open questions
See the chat message; answers will be recorded here before work starts.

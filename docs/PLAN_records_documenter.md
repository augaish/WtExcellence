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

## Decisions (answered)
- P&P Manager = a user with the QM licence, one or more per company, set by company admin in Account Management.
- Level 0 is fixed to the three bands; the company may rename them. Plus sign on Level 1 and Level 2 only.
- Anything typed in English or Arabic is translated by the system into the other language; the client may edit the translation.
- All existing process data is test data: delete it in the migration. Procedures are level 3 and live in Records.
- The objective text (circle) is set on the Process Architecture page.
- SLA, guideline, charter, work instruction: not needed now (will become library folders later).
- Codes: TYPE-UNIT-NUMBER-Vn, e.g. POL-HR-001-V1; procedures use the architecture number: PROC-HR-1.2.4.12-V1.
- Glossary: a record with a short flow: any contributor under a P&P Manager can log a term; approval by the P&P Manager makes it visible to all users.
- Packages unchanged; records are added from the package window.
- Old versions readable by QMs and company admins only; others see only the latest version.
- "Same function" = the unit head's reporters as defined in the org structure (everyone in the company holds a contributor licence and is placed in the org).
- Auto-approval counts working days; the option exists for Final Approval too.
- After a stakeholder rejection the P&P Manager chooses whether to re-send to the rejecting units only or to all.
- A Final Approval rejection keeps the record in place unless the P&P Manager or company admin sends it back to a chosen stage, fixes it, then re-sends to the refuser.
- Data Verification contributor is chosen by the person who logs the record.
- PDF: headless Chromium printing the document page (design can be improved later).
- Publish notification: in-app only. Published records are read-only; changes go through "Update existing".
- Only the team under the company admin may add records, not any contributor.

## Still open
- What is "the team under the company admin"? (proposal: company admins, quality managers and the contributors assigned under a P&P Manager)
- Translation engine: use the existing LLM provider (OpenRouter) and charge credits, or free of charge?
- Procedure number: how is 1.2.4.12 composed? (proposal: L1 number . L2 number . procedure sequence)

# Task 1: EFQM Scoring Implementation — Requirements Document

**Version:** 1.0
**Date:** 2026-04-15
**Source:** WTE - EFQM Scoring & Tools Specification v1.0 (April 3, 2026), UI mockups (`evaluating_journey.html.erb`, `tool_builder.html.erb`)
**Branch:** `task-1-implement-efqm-scoring`

---

## Table of Contents

1. [Overview](#1-overview)
2. [Feature A: Terminal Clause Assessment Page](#2-feature-a-terminal-clause-assessment-page)
3. [Feature B: Tool Admin — Configurable Attributes](#3-feature-b-tool-admin--configurable-attributes)
4. [Feature C: Scoring Section on Assessment Page](#4-feature-c-scoring-section-on-assessment-page)
5. [Feature D: Score Calculation — Weights & Caps](#5-feature-d-score-calculation--weights--caps)
6. [Data Model Changes](#6-data-model-changes)
7. [API / Endpoint Changes](#7-api--endpoint-changes)
8. [Non-Functional Requirements](#8-non-functional-requirements)
9. [Edge Cases & Error Scenarios](#9-edge-cases--error-scenarios)
10. [Dependencies & Assumptions](#10-dependencies--assumptions)
11. [Acceptance Criteria](#11-acceptance-criteria)

---

## 1. Overview

### Problem

The current WTE platform evaluates at the **subcheckpoint level** (`ToolSubcheckpoint`), where users upload evidence and write comments per subcheckpoint. The EFQM standard (and similar standards like KAQA) require evaluation at the **terminal clause level** (e.g., "1.1 Define Purpose and Vision"), with evidence and notes organized by checkpoint, and scoring applied to the whole terminal clause using configurable weights and caps.

### Goals

1. Create a single consolidated assessment page per terminal clause that groups all checkpoint work.
2. Make the number and type of text fields per checkpoint driven by the tool's Assessment Categories (existing `ToolCheckpoint` records).
3. Add a scoring section at the terminal clause level with configurable weights and score caps.
4. Replace the simple average-percentage scoring formula with a weighted-sum + cap formula.
5. Keep the existing auditor review flow (approve/reject with comments) unchanged.
6. Support EFQM (percentage sliders), KAQA (similar), and ISO (yes/no or simple scoring) from v1.

### Existing Data Model (Relevant)

| Table | Purpose |
|---|---|
| `tools` | Evaluation tool definition (e.g., "EFQM Excellence Model") |
| `tool_checkpoints` | Assessment categories / attribute groups within a tool |
| `tool_subcheckpoints` | Individual scoring attributes (e.g., Sound, Aligned) |
| `tool_clauses` | Links a tool to a clause (1:1 per clause) |
| `tool_clause_subcheckpoint_assignments` | Per-company work container for a (tool_clause, subcheckpoint) pair |
| `assignment_evaluations` | Auditor review records |
| `clause_score_caches` | Cached computed scores per clause per company |
| `clauses` | Hierarchical clause tree (parent_id); terminal = leaf nodes |
| `checklist_items` | Checkpoint descriptions within a clause |
| `checkpoint_summaries` | Per-checkpoint, per-tool-checkpoint, per-company text summaries (added in this task) |

---

## 2. Feature A: Terminal Clause Assessment Page

### FR-A1: Page Entry Point

- **FR-A1.1:** When a user clicks the action button on a terminal (leaf) clause in the clause hierarchy view, the system shall navigate to the terminal clause assessment page.
- **FR-A1.2:** Terminal clauses are identified by `clause.leaf?` (no child clauses).
- **FR-A1.3:** The page URL shall follow the pattern: `GET /standards/:standard_id/clauses/:clause_id/assessment`.

### FR-A2: Clause Header Section

- **FR-A2.1:** Display the clause code and title (e.g., "1.1 Define Purpose and Vision") as an `<h1>`.
- **FR-A2.2:** Display breadcrumb navigation: Standard Name > Parent Clause > Terminal Clause.
- **FR-A2.3:** Display the overall status indicator for this clause, derived from the aggregate status of its checkpoint assignments. Status badges: "Not Started" (gray), "In Progress" (yellow), "Under Review" (blue), "Complete" (green).
- **FR-A2.4:** Display the clause summary text from `ClauseTranslation` (locale-aware) when available.
- **FR-A2.5:** Display metadata: Allocated Points (from `clause.calculated_points`), Current Score (percentage from scoring calculation), and linked Tool name.
- **FR-A2.6:** Display Previous/Next navigation buttons to move between sibling terminal clauses within the same parent.

### FR-A3: Checkpoint Boxes Section

- **FR-A3.1:** For each `ChecklistItem` associated with this clause (ordered by `sort_order`), render a checkpoint box.
- **FR-A3.2:** Each checkpoint box header shall display: checkpoint number (sequential), checkpoint name/title, and a status badge for that checkpoint.
- **FR-A3.3:** Each checkpoint box shall display inline guidance text from the `ChecklistItem` description (or `ChecklistItemTranslation` body for the current locale). The guidance is always visible (not behind a toggle).
- **FR-A3.4:** Each checkpoint box shall render N labeled text areas, where N = the number of `ToolCheckpoint` records on the linked tool. The label for each text area is the `ToolCheckpoint.name` (locale-aware via `name_in`). Example: EFQM tool with 3 ToolCheckpoints ("Approach", "Deployment", "Assessment & Refinement") produces 3 text areas per checkpoint box.
- **FR-A3.5:** Each text area shall enforce a 100-character limit (`maxlength="100"`). A live character counter shall display `X/100` below each field.
- **FR-A3.6:** Text area values map to `ToolClauseSubcheckpointAssignment.summary` — one assignment record per (tool_clause, tool_subcheckpoint, company). The subcheckpoint represents the attribute.
- **FR-A3.7:** Each checkpoint box shall include an Evidence section with:
  - An "Upload File" button for direct file uploads (stored as `EvidenceAttachment`, polymorphic on the assignment, using Active Storage).
  - An "Add Link" button for linking external URLs.
  - A list of previously uploaded files and links, each with a filename/title display and a delete (X) button.
- **FR-A3.8:** Each checkpoint box shall include an Owner/Assignee picker — a dropdown or user picker to assign a user as the owner for that checkpoint. Uses the existing `ToolClauseSubcheckpointAssignmentsUser` model. Display the assigned user's avatar initials, name, and role when assigned.
- **FR-A3.9:** Text area layout: on desktop (lg+), text areas display side-by-side in a grid (`grid-cols-{N}` up to 3 columns). On tablet/mobile, text areas stack vertically.

### FR-A4: Comments & Activity Log Section

- **FR-A4.1:** Retain the existing comments component — no changes. Users can post new comments, and existing comments are displayed in chronological order.
- **FR-A4.2:** Retain the existing activity log component — no changes. Shows audit trail of changes, status updates, evaluations, assignments, and uploads.
- **FR-A4.3:** The auditor review flow (approve/reject with comments via `AssignmentEvaluation`) remains unchanged and continues to function within this section.

### FR-A5: Bottom Actions

- **FR-A5.1:** A "Back to Clause List" link navigating back to the clause hierarchy view.
- **FR-A5.2:** A "Save Draft" button that persists all text field values and assignee selections without changing the assignment status.
- **FR-A5.3:** A "Submit for Review" button that persists all values and transitions the assignment status to `under_review`.

### FR-A6: Removals

- **FR-A6.1:** Remove the "EFQM Links" field from the assessment UI (confirmed removed per April 3 meeting).
- **FR-A6.2:** Remove the "Guidance" toggle button — guidance text is now shown inline per checkpoint (FR-A3.3).

---

## 3. Feature B: Tool Admin — Configurable Attributes

### FR-B1: Assessment Categories (ToolCheckpoints)

- **FR-B1.1:** When an admin creates or edits a tool, the `ToolCheckpoint` entries under that tool define the labeled text areas that appear per checkpoint on the assessment page.
- **FR-B1.2:** Each `ToolCheckpoint` has: name (required), description/guidance text, display_order (drag-to-reorder).
- **FR-B1.3:** Adding a `ToolCheckpoint` named "Approach" means every checkpoint box on the assessment page gets a text area labeled "Approach".
- **FR-B1.4:** Removing a `ToolCheckpoint` removes the corresponding text area from all checkpoint boxes on assessment pages using that tool.
- **FR-B1.5:** The admin UI shall support adding, editing, reordering (drag handle), and deleting Assessment Categories.

### FR-B2: Scoring Attributes (ToolSubcheckpoints)

- **FR-B2.1:** Under each `ToolCheckpoint` (Assessment Category), the admin can define `ToolSubcheckpoint` records — these are the scoring attributes that appear in the scoring section (Section 4 of the assessment page).
- **FR-B2.2:** Each scoring attribute has: name (required), description (tooltip text shown as `?` icon in scoring section), scoring_type (Percentage / Number / Multiple Choice), weight (decimal 0.0–1.0), is_cap (boolean toggle), display_order.
- **FR-B2.3:** The scoring attribute table in the admin shows columns: Attribute Name, Description, Weight, Cap (toggle switch), Delete button.
- **FR-B2.4:** The admin can add new scoring attributes within each category via "+ Add Attribute" link.

### FR-B3: General Tool Information

- **FR-B3.1:** Tool creation/edit form includes: Tool Name, Linked Standard (dropdown), Description (textarea), Scoring Type (Percentage/Number/Yes-No/Multiple Choice), Scoring Level (Terminal Clause Level / Checkpoint Level).
- **FR-B3.2:** The "Scoring Level" field is informational for v1 — assessment always happens at the terminal clause level. Future versions may support checkpoint-level scoring.

### FR-B4: Weight & Cap Summary Panel

- **FR-B4.1:** The tool admin form shall display a "Weight & Cap Summary" section showing:
  - A visual weight distribution bar chart (attribute name + percentage bar + value).
  - Total weight sum with validity indicator: green "100% (Valid)" or red/amber warning if sum != 1.0.
  - A list of cap-enabled attributes with visual indicator.
  - A formula preview showing the actual formula that will be applied (e.g., `overall = MIN(weighted_sum, Sound)`).
- **FR-B4.2:** If weights do not sum to 1.0, the admin UI shall show a warning message but shall NOT block saving.

### FR-B5: Admin UI Label Changes

- **FR-B5.1:** The admin UI shall display an info banner explaining the relationship: "Assessment Categories define the text areas that appear per checkpoint on the evaluation page (e.g., Approach, Deployment). Scoring Attributes define the sliders/inputs in the scoring section (e.g., Sound, Aligned). Each attribute can have a weight and can optionally act as a score cap."
- **FR-B5.2:** Consider labeling the sections as "Assessment Categories" (for ToolCheckpoints) and "Scoring Attributes" (for ToolSubcheckpoints) in the admin UI, as shown in the mockup.

### FR-B6: Preview Panel

- **FR-B6.1:** The tool admin form shall include a "Preview: Assessment Page Layout" section that shows a wireframe preview of what each checkpoint will look like on the assessment page based on the current tool configuration (number and names of text areas, evidence upload area, assignee picker).

---

## 4. Feature C: Scoring Section on Assessment Page

### FR-C1: Scoring Section Location & Structure

- **FR-C1.1:** The scoring section appears at the bottom of the terminal clause assessment page, after the checkpoint boxes and before the comments section.
- **FR-C1.2:** The section header is "Scoring" with helper text: "Rate each attribute using the sliders. The overall score is calculated automatically using configured weights and caps."
- **FR-C1.3:** Scoring attributes are grouped by their parent `ToolCheckpoint`. Each group has a header showing the ToolCheckpoint name in uppercase with a decorative accent bar (e.g., "APPROACH", "DEPLOYMENT").
- **FR-C1.4:** Under each group header, render each `ToolSubcheckpoint` as a scoring row.

### FR-C2: Scoring Row UI

- **FR-C2.1:** Each scoring row displays:
  - Attribute name (e.g., "Sound", "Aligned").
  - A `?` tooltip icon that shows the `ToolSubcheckpoint.description` (locale-aware) on hover.
  - A "CAP" badge (amber) if `is_cap` is true for this attribute.
  - A scoring input control (type depends on `scoring_type` — see FR-C3).
  - The current value displayed in a styled box.
- **FR-C2.2:** Each scoring row is wrapped in a `bg-gray-50 rounded-lg p-3` container for visual grouping.

### FR-C3: Scoring Input Types

- **FR-C3.1:** `Percentage` scoring_type: Render a horizontal range slider (`<input type="range">`) with min=0, max=100 (or custom min/max from `ToolSubcheckpoint`). Alongside the slider, display the current value as `X%` in a bordered box. Slider accent color: `#5C3984`.
- **FR-C3.2:** `Number` scoring_type: Render a numeric input field (`<input type="number">`) with min/max from `ToolSubcheckpoint.min_score`/`max_score`.
- **FR-C3.3:** `Multiple Choice` scoring_type: Render radio buttons or a dropdown with options from `ToolSubcheckpoint.multiple_choice_options`. Each option maps to a numeric score value.

### FR-C4: Overall Score Bar

- **FR-C4.1:** Below all scoring groups, separated by a top border, display the "OVERALL" score in a highlighted container (`bg-[#F7F7FD]` with border).
- **FR-C4.2:** The overall score is displayed as a read-only progress bar (filled width = percentage) with the numeric value in a bold purple badge.
- **FR-C4.3:** Below the overall score bar, display the formula breakdown showing the calculation steps. Example: `Formula: weighted_sum = (65x0.2)+(70x0.2)+(55x0.2)+(60x0.2)+(50x0.1)+(45x0.1) = 59.5 | Cap (Sound) = 65 | Overall = MIN(59.5, 65) = 59.5%`
- **FR-C4.4:** The overall score shall update in real-time (no page reload) as the user changes individual attribute scores. This requires a Stimulus controller that recalculates on slider/input change and updates the overall bar + formula text.

### FR-C5: Score Persistence

- **FR-C5.1:** Individual attribute scores are saved to `ToolClauseSubcheckpointAssignment.percentage_score` (for Percentage type) or `ToolClauseSubcheckpointAssignment.score` (for Number type).
- **FR-C5.2:** Saving is triggered by the "Save Draft" or "Submit for Review" buttons (not auto-save for v1, to stay consistent with the bottom-action approach).
- **FR-C5.3:** On save, the backend recalculates the Overall score using the weighted + cap formula (Feature D).
- **FR-C5.4:** After backend calculation, `ClauseScorePropagator.propagate_from_terminal_clause()` updates parent clause score caches.
- **FR-C5.5:** The save response shall include the computed overall score so the frontend can update the display if the server-computed value differs from the client-side preview.

---

## 5. Feature D: Score Calculation — Weights & Caps

### FR-D1: Weight System

- **FR-D1.1:** Each `ToolSubcheckpoint` has a `weight` field (decimal, precision 5, scale 4, default: null). Range: 0.0 to 1.0.
- **FR-D1.2:** Weight represents the contribution of this attribute to the overall weighted sum.
- **FR-D1.3:** If no weights are configured (all `weight` values are null), fall back to equal weighting: `1.0 / number_of_attributes`.
- **FR-D1.4:** Weights should ideally sum to 1.0 across all `ToolSubcheckpoint` records for a tool. The admin UI warns if they don't, but saving is not blocked.

### FR-D2: Cap System

- **FR-D2.1:** Each `ToolSubcheckpoint` has an `is_cap` field (boolean, default: false).
- **FR-D2.2:** When `is_cap` is true for an attribute, the overall score cannot exceed that attribute's current score value.
- **FR-D2.3:** If multiple attributes are caps, the overall score cannot exceed the **minimum** value among all capped attributes.

### FR-D3: Overall Score Formula

The formula for the overall score of a terminal clause:

```
weighted_sum = SUM(attribute_score[i] * weight[i]) for all attributes i
cap_value = MIN(attribute_score[j]) for all attributes j where is_cap = true
overall_score = MIN(weighted_sum, cap_value)
```

If no caps are defined: `overall_score = weighted_sum`.

### FR-D4: ClauseScoreCalculator Changes

- **FR-D4.1:** Replace the current average-percentage formula in `ClauseScoreCalculator#calculate_score` with the weighted-sum + cap formula from FR-D3.
- **FR-D4.2:** The calculator shall read `weight` and `is_cap` from each `ToolSubcheckpoint` associated with the tool.
- **FR-D4.3:** For unevaluated (unscored) attributes, treat the score as 0 in the weighted sum (consistent with current behavior).
- **FR-D4.4:** Store the computed overall percentage in `clause_score_caches.cached_percentage`.
- **FR-D4.5:** If a cap was applied, store descriptive text in `clause_score_caches.business_rule_violation` (e.g., "Score capped by Sound attribute at 65%").
- **FR-D4.6:** The final score = `allocated_points * (overall_score / 100)`.

### FR-D5: Backend-Only Canonical Calculation

- **FR-D5.1:** The canonical overall score is always computed on the backend. The frontend shows a live preview but the server response is authoritative.
- **FR-D5.2:** The save endpoint returns: `overall_score`, `cap_applied` (boolean), `cap_value`, `cap_attribute` (name), `weighted_sum`, `business_rule_violation` (string or null).

---

## 6. Data Model Changes

### DM-1: New Columns on `tool_subcheckpoints`

| Column | Type | Default | Null | Description |
|---|---|---|---|---|
| `weight` | `decimal(5,4)` | `null` | `true` | Weight of this attribute in overall score (0.0–1.0). Null = equal weight fallback. |
| `is_cap` | `boolean` | `false` | `false` | If true, overall score cannot exceed this attribute's value. |

**Migration:**
```ruby
add_column :tool_subcheckpoints, :weight, :decimal, precision: 5, scale: 4, null: true
add_column :tool_subcheckpoints, :is_cap, :boolean, default: false, null: false
```

### DM-2: No Other Structural Changes Required

The existing data model is sufficient for all assessment page changes:

- `ToolCheckpoint` records already group scoring attributes and will drive text area labels.
- `ToolSubcheckpoint` records already represent individual scoring items; they gain `weight` and `is_cap`.
- `ToolClauseSubcheckpointAssignment` already stores per-company, per-subcheckpoint work (`summary` for text, `percentage_score` for scores).
- `EvidenceAttachment` (polymorphic on assignment) already handles file uploads.
- `ChecklistItem` on clauses already stores checkpoint descriptions for guidance text.
- `clause.leaf?` already identifies terminal clauses.

### DM-3: Model Validations

- **DM-3.1:** `ToolSubcheckpoint` shall validate `weight` is between 0.0 and 1.0 (inclusive) when present.
- **DM-3.2:** `ToolSubcheckpoint` shall validate `is_cap` is a boolean.
- **DM-3.3:** No cross-record validation that weights sum to 1.0 (only UI warning).

---

## 7. API / Endpoint Changes

### EP-1: Terminal Clause Assessment Page

**`GET /standards/:standard_id/clauses/:clause_id/assessment`**

- Returns HTML (Turbo-compatible) rendering the full assessment page.
- Controller: new action on an existing controller (e.g., `ClausesController#assessment`) or a new `AssessmentsController`.
- Loads: clause with translations, checklist_items, tool via tool_clause, tool_checkpoints with subcheckpoints, existing assignments for the current company, evidence attachments, assignees.
- Authorization: user must belong to the company and have at least `company_viewer` role.

### EP-2: Save Scores

**`PUT /standards/:standard_id/clauses/:clause_id/assessment/scores`**

- Request body (JSON or form params):
  ```json
  {
    "scores": [
      { "subcheckpoint_id": "uuid", "value": 60 },
      { "subcheckpoint_id": "uuid", "value": 80 }
    ]
  }
  ```
- Response (JSON):
  ```json
  {
    "overall_score": 50,
    "cap_applied": true,
    "cap_value": 60,
    "cap_attribute": "Sound",
    "weighted_sum": 65,
    "business_rule_violation": "Score capped by Sound attribute"
  }
  ```
- On success: updates `percentage_score` on each `ToolClauseSubcheckpointAssignment`, recalculates overall via `ClauseScoreCalculator`, propagates via `ClauseScorePropagator`, returns computed result.
- Authorization: user must be assigned to the clause or have `company_quality_manager`+ role.

### EP-3: Save Checkpoint Text & Evidence

- Use existing `PUT /assignments/:id` endpoint to save `summary` text on individual assignments.
- Use existing evidence upload endpoints for file attachments.
- No new endpoints needed for text/evidence/assignee persistence.

### EP-4: Tool Admin CRUD

- Extend existing `ToolsController` create/update actions to accept and persist `weight` and `is_cap` on `ToolSubcheckpoint` nested attributes.
- No new endpoints needed — existing nested attributes handling via `accepts_nested_attributes_for` on `ToolCheckpoint` > `ToolSubcheckpoint`.

---

## 8. Non-Functional Requirements

### NFR-1: Performance

- **NFR-1.1:** The assessment page shall load in under 2 seconds for a clause with up to 10 checkpoints and 6 scoring attributes (typical EFQM configuration).
- **NFR-1.2:** Score propagation after save shall complete within 500ms for a standard with up to 50 terminal clauses.
- **NFR-1.3:** The real-time overall score preview on the frontend (Stimulus controller) shall update within 50ms of slider/input change (no perceptible delay).
- **NFR-1.4:** Use eager loading (`includes`) for all associations on the assessment page to avoid N+1 queries. Target: fewer than 10 SQL queries per page load.

### NFR-2: Accessibility

- **NFR-2.1:** All interactive elements (sliders, inputs, buttons, dropdowns) shall be keyboard-navigable.
- **NFR-2.2:** Tooltip content (scoring attribute descriptions) shall be accessible via keyboard focus (not hover-only). Use `aria-describedby` or a focusable tooltip pattern.
- **NFR-2.3:** Range sliders shall have `aria-label`, `aria-valuemin`, `aria-valuemax`, `aria-valuenow` attributes.
- **NFR-2.4:** Character counter on text areas shall use `aria-live="polite"` to announce changes to screen readers.
- **NFR-2.5:** All touch targets shall be at least 44x44px (already enforced by `min-h-[44px]` in mockups).
- **NFR-2.6:** Color contrast ratios shall meet WCAG 2.1 AA standards (4.5:1 for normal text, 3:1 for large text).

### NFR-3: Internationalization (i18n)

- **NFR-3.1:** All user-facing text on the assessment page shall be translatable via Rails I18n (en, ar locales).
- **NFR-3.2:** The page shall support RTL layout when the Arabic locale is active. Sliders, text areas, and layout shall mirror correctly.
- **NFR-3.3:** Tool names, checkpoint names, and subcheckpoint names/descriptions shall use the `*_in(locale)` translation methods from existing `*Translation` models.

### NFR-4: Responsiveness

- **NFR-4.1:** Desktop (lg+): text areas display in a horizontal grid (up to 3 columns). Scoring rows display attribute name and slider on the same row.
- **NFR-4.2:** Tablet (md): text areas may wrap to 2 columns. Scoring rows display attribute name and slider on the same row.
- **NFR-4.3:** Mobile (sm and below): text areas stack vertically. Scoring rows stack vertically (label above, slider below). All buttons are full-width or properly sized with min-h-[44px].
- **NFR-4.4:** Touch targets on sliders shall be large enough for finger interaction (minimum 44px track height).

### NFR-5: Security

- **NFR-5.1:** All score submissions shall validate that the current user has permission to score the given clause (company membership + role check).
- **NFR-5.2:** Score values shall be validated server-side: percentage values within 0–100 (or min/max), number values within min_score–max_score, multiple choice values must match defined options.
- **NFR-5.3:** The `company_id` on assignments shall always be set from the server-side `current_user.current_company`, never from client input.
- **NFR-5.4:** CSRF protection via Rails authenticity tokens on all form submissions.

### NFR-6: Audit Trail

- **NFR-6.1:** All score changes shall be logged via `AuditLogService` (who changed what, when, old value vs new value).
- **NFR-6.2:** Text field changes shall be tracked in the activity log visible on the assessment page.

---

## 9. Edge Cases & Error Scenarios

### EC-1: Scoring Edge Cases

| # | Scenario | Expected Behavior |
|---|---|---|
| EC-1.1 | No scores entered yet | Overall = 0%. All sliders at 0. No error displayed. |
| EC-1.2 | Only some attributes scored | Unscored attributes treated as 0 in weighted sum. |
| EC-1.3 | A cap attribute has score = 0 | Overall = 0 regardless of other attribute scores. This is correct EFQM behavior (e.g., Sound = 0 means everything is 0). |
| EC-1.4 | Multiple caps with different values | Overall = MIN(weighted_sum, MIN(all_cap_values)). E.g., Sound=60, Implemented=50 -> cap at 50. |
| EC-1.5 | Weights do not sum to 1.0 | Calculation proceeds with configured weights as-is. Admin sees warning. |
| EC-1.6 | All weights are null | Equal weighting fallback: 1/N per attribute. |
| EC-1.7 | Some weights are null, some set | Null weights treated as 0 in calculation. (Admin should be warned to fill all weights.) |
| EC-1.8 | No caps configured | Overall = weighted_sum only. No capping applied. |
| EC-1.9 | Weighted sum exceeds 100 (weights > 1.0 total) | Overall is the raw weighted_sum (may exceed 100). Admin warning should prevent this. |

### EC-2: Assessment Page Edge Cases

| # | Scenario | Expected Behavior |
|---|---|---|
| EC-2.1 | Tool has no subcheckpoints | No scoring section rendered. Checkpoint boxes still show text areas. |
| EC-2.2 | Clause has no checklist items | No checkpoint boxes rendered. Only the scoring section and comments section appear. |
| EC-2.3 | Tool has no checkpoints (no categories) | No text areas rendered in checkpoint boxes. Only guidance text, evidence, and assignee shown per checkpoint. |
| EC-2.4 | Non-terminal clause accessed | Redirect to clause hierarchy view or show error: "Assessment is only available for terminal clauses." |
| EC-2.5 | Clause has no linked tool | Show informational message: "No evaluation tool is linked to this clause." No scoring section. |
| EC-2.6 | User has view-only role (`company_viewer`) | Assessment page loads in read-only mode: sliders disabled, text areas disabled, no save/submit buttons. |
| EC-2.7 | Concurrent editing by multiple users | Last-write-wins for individual assignment fields. Turbo Stream broadcasts could update stale data (future enhancement). |
| EC-2.8 | Text field exceeds 100 characters (API bypass) | Server-side validation truncates or rejects values exceeding 100 characters with a 422 error. |
| EC-2.9 | Arabic content with RTL | Sliders render right-to-left. Text areas use RTL direction. Breadcrumbs mirror. Layout mirrors per existing RTL support. |

### EC-3: Tool Admin Edge Cases

| # | Scenario | Expected Behavior |
|---|---|---|
| EC-3.1 | Admin sets weight > 1.0 | Frontend validates and shows error (client-side). Server rejects with 422 if it arrives. |
| EC-3.2 | Admin deletes a ToolCheckpoint that has existing assignment data | Dependent `ToolSubcheckpoint` records are destroyed (cascade). Existing `ToolClauseSubcheckpointAssignment` records for those subcheckpoints are destroyed. Scores for affected clauses are invalidated and recalculated. |
| EC-3.3 | Admin adds a new ToolCheckpoint to an existing tool | Existing assessment pages gain a new text area column. New `ToolClauseSubcheckpointAssignment` records are created on-demand when the assessment page is loaded. |
| EC-3.4 | Tool with Multiple Choice scoring type | Assessment scoring section shows radio buttons/dropdown. Selected option maps to a defined numeric score value for calculation. |

---

## 10. Dependencies & Assumptions

### Dependencies

| # | Dependency | Type | Notes |
|---|---|---|---|
| D-1 | Existing `ToolCheckpoint` / `ToolSubcheckpoint` model hierarchy | Code | Reused as-is; extended with `weight` and `is_cap`. |
| D-2 | Existing `ToolClauseSubcheckpointAssignment` model | Code | Reused for both text (summary) and score (percentage_score) storage. |
| D-3 | Existing `ClauseScorePropagator` service | Code | Called after score save to propagate up the clause hierarchy. Must be updated to work with new weighted formula. |
| D-4 | Existing `ClauseScoreCalculator` service | Code | Must be rewritten to use weighted-sum + cap formula instead of simple average. |
| D-5 | Existing `BusinessRuleValidator` service | Code | May need updates if JSONB business_rules on tools interact with new cap logic. |
| D-6 | Existing `EvidenceAttachment` model + Active Storage | Code | Reused for file uploads per checkpoint. |
| D-7 | Existing `ChecklistItem` model | Code | Provides checkpoint guidance text. Must already be populated for clauses. |
| D-8 | Stimulus.js framework | Frontend | Required for real-time overall score calculation on slider change. |
| D-9 | Tailwind CSS v4.1 | Frontend | All styling per mockups uses Tailwind utility classes. |
| D-10 | Turbo (Hotwire) | Frontend | Page navigation and partial updates via Turbo Frames/Streams. |

### Assumptions

| # | Assumption | Impact if Wrong |
|---|---|---|
| A-1 | The existing `ToolClauseSubcheckpointAssignment` model can serve dual purpose: `summary` field for text areas and `percentage_score` for scoring section values. | If the spec requires separate records for text vs scores, a new model or restructured assignments would be needed. |
| A-2 | ChecklistItems are already populated for EFQM standard clauses. | If not, a seeding/import step is needed before the assessment page will display checkpoints. |
| A-3 | One tool is linked per clause via `ToolClause`. | If multiple tools per clause are needed, the assessment page and scoring logic need to support tool selection. |
| A-4 | The scoring section operates at the terminal clause level only (not per-checkpoint scoring). | Per-checkpoint scoring is deferred to v2 per the spec's "Scoring Level" field. |
| A-5 | Auto-save is deferred. V1 uses explicit Save Draft / Submit for Review buttons. | If auto-save is required, add a Stimulus controller with debounced PATCH requests. |
| A-6 | The `weight` fallback to equal weighting (1/N) applies when ALL weights are null. Partial null weights are treated as 0. | If partial nulls should also trigger equal weighting, the calculator logic changes. |
| A-7 | Custom formula field (`tools.custom_formula`) is deferred to v2. | V1 only supports the `weighted_sum + MIN(caps)` formula. |
| A-8 | The existing auditor review workflow (approve/reject via `AssignmentEvaluation`) requires no changes. | If the auditor workflow needs to be adapted to clause-level review (vs. subcheckpoint-level), additional work is needed. |

---

## 11. Acceptance Criteria

### AC-A: Terminal Clause Assessment Page

| # | Criterion | Verification |
|---|---|---|
| AC-A1 | Clicking a terminal clause in the hierarchy navigates to the assessment page at `/standards/:id/clauses/:id/assessment`. | Manual: click terminal clause link, verify URL and page content. |
| AC-A2 | The clause header displays code, title, status badge, allocated points, current score %, and tool name. | Manual: verify all fields match database values for the clause. |
| AC-A3 | Breadcrumb shows "Standard > Parent Clause > Terminal Clause" and each segment is clickable (except terminal). | Manual: verify breadcrumb rendering and navigation. |
| AC-A4 | Each checkpoint box displays inline guidance text from its ChecklistItem. | Manual: verify text matches ChecklistItem description for the current locale. |
| AC-A5 | For an EFQM tool with 3 categories, each checkpoint box shows 3 labeled text areas ("Approach", "Deployment", "Assessment & Refinement"). | Manual: create EFQM tool with 3 categories, open assessment page, verify 3 text areas per checkpoint. |
| AC-A6 | For an ISO tool with 1 category ("Fulfillment"), each checkpoint box shows 1 text area. | Manual: create ISO tool with 1 category, open assessment page, verify 1 text area. |
| AC-A7 | Text areas enforce 100-character limit. Character counter shows `X/100` and updates live. | Manual: type into text area, verify counter. Try pasting 150 chars, verify truncation at 100. |
| AC-A8 | Evidence upload works: upload a file, verify it appears in the list. Delete a file, verify removal. | Manual: upload PDF, verify in list. Click X, verify removed. |
| AC-A9 | Add Link works: enter a URL, verify it appears in the evidence list. | Manual: add link, verify display. |
| AC-A10 | Assignee picker shows company users. Selecting a user persists the assignment. | Manual: select user, save, reload page, verify user still assigned. |
| AC-A11 | "Save Draft" persists text, scores, and assignees without changing status. | Manual: fill fields, save draft, reload, verify persistence and status unchanged. |
| AC-A12 | "Submit for Review" persists all data and changes status to `under_review`. | Manual: fill fields, submit, verify status change in database and UI. |
| AC-A13 | Previous/Next buttons navigate to sibling terminal clauses. | Manual: click Next, verify next sibling clause loads. Click Previous, verify previous. |
| AC-A14 | Page renders correctly in Arabic locale with RTL layout. | Manual: switch to Arabic, verify mirrored layout, RTL text direction. |

### AC-B: Tool Admin

| # | Criterion | Verification |
|---|---|---|
| AC-B1 | Tool creation form includes Assessment Categories section with add/edit/reorder/delete. | Manual: create tool, add 3 categories, reorder via drag, delete one, save. |
| AC-B2 | Each category has a Scoring Attributes sub-section with Name, Description, Weight, Cap toggle, Delete. | Manual: add attributes to a category, fill all fields, save. |
| AC-B3 | Weight field accepts values 0.0–1.0 with step 0.05. | Manual: enter 0.2, verify accepted. Enter 1.5, verify validation error. |
| AC-B4 | Cap toggle persists correctly. | Manual: toggle cap on "Sound", save tool, reload, verify toggle state. |
| AC-B5 | Weight & Cap Summary shows correct distribution bars and total. | Manual: set weights, verify bars and sum in summary panel. |
| AC-B6 | Weight sum warning appears when weights don't total 1.0 but save is not blocked. | Manual: set weights summing to 0.8, verify warning, verify save succeeds. |
| AC-B7 | Formula preview updates when caps/weights change. | Manual: toggle a cap, verify formula text changes. |
| AC-B8 | Preview panel shows correct number of text area placeholders matching category count. | Manual: add/remove categories, verify preview updates. |

### AC-C: Scoring Section

| # | Criterion | Verification |
|---|---|---|
| AC-C1 | Scoring section renders groups matching ToolCheckpoint names with correct attributes. | Manual: open assessment for EFQM clause, verify groups (Approach, Deployment, Assessment & Refinement) with correct attributes. |
| AC-C2 | Percentage sliders work: drag slider, value updates in box. | Manual: drag slider to 65, verify box shows "65%". |
| AC-C3 | Question mark tooltip shows attribute description on hover/focus. | Manual: hover/focus `?` icon on "Sound", verify tooltip text matches ToolSubcheckpoint description. |
| AC-C4 | CAP badge appears on capped attributes. | Manual: mark "Sound" as cap in tool, open assessment, verify "CAP" badge on Sound row. |
| AC-C5 | Overall score bar updates in real-time when sliders change. | Manual: move Sound slider from 0 to 65, observe Overall bar updating without page reload. |
| AC-C6 | Formula breakdown text updates in real-time. | Manual: change slider values, verify formula text reflects new values and calculation. |
| AC-C7 | Number-type attributes show numeric input instead of slider. | Manual: create tool with Number-type attribute, verify numeric input on assessment page. |
| AC-C8 | Multiple Choice attributes show radio buttons or dropdown. | Manual: create tool with Multiple Choice attribute, verify radio/dropdown on assessment page. |

### AC-D: Score Calculation

| # | Criterion | Verification |
|---|---|---|
| AC-D1 | Weighted sum calculation is correct: `SUM(score_i * weight_i)`. | Automated test: set Sound=65 (w=0.2), Aligned=70 (w=0.2), Implemented=55 (w=0.2), Flexible=60 (w=0.2), Evaluated=50 (w=0.1), Learn=45 (w=0.1). Verify weighted_sum = 59.5. |
| AC-D2 | Cap is applied: if Sound (cap) = 65 and weighted_sum = 70, overall = 65. | Automated test: configure Sound as cap at 65, other scores high enough to produce weighted_sum > 65. Verify overall = 65. |
| AC-D3 | Multiple caps: MIN of cap values used. Sound (cap) = 60, Implemented (cap) = 50. Overall <= 50. | Automated test: set both as caps, verify overall capped at 50. |
| AC-D4 | Cap at 0: Sound (cap) = 0. Overall = 0 regardless of other scores. | Automated test: Sound=0, others=100. Verify overall=0. |
| AC-D5 | No weights configured: equal weighting fallback (1/N). | Automated test: 6 attributes, all weights null, all scores=100. Verify overall=100. Scores=[100,50,...]: verify average. |
| AC-D6 | No caps configured: overall = weighted_sum (no capping). | Automated test: set weights, no caps. Verify overall equals weighted_sum exactly. |
| AC-D7 | Score propagation: saving terminal clause scores updates parent clause cache. | Automated test: save scores on terminal clause, verify `ClauseScoreCache` updated for terminal and parent clauses. |
| AC-D8 | Cap violation recorded in cache: `clause_score_caches.business_rule_violation` populated when cap applied. | Automated test: trigger cap, verify `business_rule_violation` field has descriptive text. |
| AC-D9 | Final score formula: `allocated_points * (overall_score / 100)`. | Automated test: clause with 100 allocated points, overall=62%. Verify final score=62.0. |
| AC-D10 | Scores are company-scoped: different companies see independent scores for the same clause. | Automated test: save scores for Company A and Company B on same clause. Verify independent values. |

### AC-E: Integration & Regression

| # | Criterion | Verification |
|---|---|---|
| AC-E1 | Existing dashboard compliance metrics (`calculate_average_compliance_all_standards`) reflect new weighted scoring. | Manual: score clauses, check dashboard overview, verify compliance % matches expected calculation. |
| AC-E2 | Existing tool scores view (`_tool_scores.html.erb`) displays correct scores from updated calculation. | Manual: open tools page, verify clause scores match weighted formula results. |
| AC-E3 | Auditor review flow (approve/reject) continues to work on the new assessment page. | Manual: submit for review, log in as auditor, approve/reject, verify status changes. |
| AC-E4 | Score cache invalidation works when tool configuration changes (add/remove attributes, change weights). | Manual: change weight in tool admin, verify affected clause caches are invalidated and recalculated on next view. |

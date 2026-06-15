# Task 1: EFQM Scoring — Technical & Functional Specification

**Version:** 1.0
**Date:** 2026-04-15
**Requirements:** `docs/tasks/task-1-requirements.md`
**Branch:** `task-1-implement-efqm-scoring`

---

## Technical Spec

### 1. Architecture Decisions

#### 1.1 New Controller vs. Existing

**Decision:** Create a new `AssessmentsController` rather than adding actions to the existing `StandardsController` or `AssignmentsController`.

**Rationale:**
- The `AssignmentsController` operates at the **per-subcheckpoint** level (one assignment container). The assessment page operates at the **per-terminal-clause** level, aggregating across all subcheckpoints. These are fundamentally different abstractions.
- The `StandardsController` handles standard/clause CRUD. Assessment is a distinct workflow.
- A dedicated controller keeps concerns clean and avoids bloating existing files (the `ToolsController` is already 1400+ lines).

**File:** `app/controllers/assessments_controller.rb`

#### 1.2 Data Reuse vs. New Models

**Decision:** Reuse the existing data model. No new tables.

**Rationale:**
- `ToolClauseSubcheckpointAssignment` already stores per-company, per-subcheckpoint data with `summary` (text) and `percentage_score` (score) fields, plus evidence attachments and user assignments.
- `ToolCheckpoint` → text area labels. `ToolSubcheckpoint` → scoring attributes. This mapping is clean.
- Adding `weight` and `is_cap` columns to `tool_subcheckpoints` is the only schema change needed.
- New tables would duplicate storage and force data synchronization.

#### 1.3 Scoring Formula Ownership

**Decision:** `ClauseScoreCalculator` owns the canonical weighted+cap formula. The Stimulus controller mirrors it client-side for live preview only.

**Rationale:**
- Single source of truth on the backend prevents score divergence.
- The frontend preview is cosmetic — the server response after save is authoritative.
- If the formula changes, only `ClauseScoreCalculator` needs updating; the Stimulus controller is a convenience.

#### 1.4 Save Strategy

**Decision:** Explicit save via form buttons (Save Draft / Submit for Review). Not auto-save.

**Rationale:**
- Consistent with the existing assignment workflow (status transitions are deliberate).
- Auto-save adds complexity (debouncing, conflict resolution, partial states) for no clear user benefit in v1.
- The entire assessment page submits as a single form — text fields, scores, and assignees together.

#### 1.5 Assignment Record Creation Strategy

**Decision:** Lazy creation — `ToolClauseSubcheckpointAssignment` records are found-or-initialized when the assessment page loads, not eagerly created when tools are linked.

**Rationale:**
- Consistent with the existing `assign_user_to_subcheckpoint` pattern in `ToolsController` (lines 618-697) which creates assignment containers on demand.
- Avoids creating thousands of empty records for companies that haven't started assessment.
- The assessment controller `#show` action creates missing containers in memory (unsaved), and persists them only on form submission.

---

### 2. Data Model Changes

#### 2.1 Migration: Add `weight` and `is_cap` to `tool_subcheckpoints`

**File:** `db/migrate/YYYYMMDDHHMMSS_add_weight_and_is_cap_to_tool_subcheckpoints.rb`

```ruby
class AddWeightAndIsCapToToolSubcheckpoints < ActiveRecord::Migration[8.0]
  def change
    add_column :tool_subcheckpoints, :weight, :decimal, precision: 5, scale: 4, null: true
    add_column :tool_subcheckpoints, :is_cap, :boolean, default: false, null: false
  end
end
```

**Post-migration schema for `tool_subcheckpoints`:**

```
id              uuid PK
tool_checkpoints_id  uuid FK NOT NULL
name            string
description     text
scoring_type    string         -- "Number" | "Percentage" | "Multiple Choice"
min_score       decimal
max_score       decimal
display_order   integer
multiple_choice_options  jsonb  -- [{ "text": "...", "weight": N }, ...]
weight          decimal(5,4)   -- NEW: 0.0000–1.0000, NULL = equal weight fallback
is_cap          boolean        -- NEW: default false
created_at      datetime
updated_at      datetime
```

#### 2.2 Model Changes: `ToolSubcheckpoint`

**File:** `app/models/tool_subcheckpoint.rb`

Add validations:

```ruby
validates :weight, numericality: {
  greater_than_or_equal_to: 0.0,
  less_than_or_equal_to: 1.0
}, allow_nil: true

validates :is_cap, inclusion: { in: [true, false] }
```

#### 2.3 Model Changes: `Tool`

**File:** `app/models/tool.rb`

Add helper methods:

```ruby
# All subcheckpoints across all checkpoints for this tool, ordered
def all_subcheckpoints
  checkpoints.includes(:subcheckpoints)
             .order(:display_order)
             .flat_map { |cp| cp.subcheckpoints.order(:display_order) }
end

# Effective weights: configured or equal fallback
def effective_weights
  subs = all_subcheckpoints
  return {} if subs.empty?

  all_null = subs.all? { |s| s.weight.nil? }
  equal_weight = 1.0 / subs.size

  subs.each_with_object({}) do |sub, h|
    h[sub.id] = all_null ? equal_weight : (sub.weight || 0.0)
  end
end

# Subcheckpoint IDs marked as caps
def cap_subcheckpoint_ids
  all_subcheckpoints.select(&:is_cap).map(&:id)
end
```

#### 2.4 Strong Params Update: `ToolsController`

**File:** `app/controllers/tools_controller.rb`, method `tool_params` (line 1341)

Add `:weight` and `:is_cap` to the `subcheckpoints_attributes` whitelist:

```ruby
subcheckpoints_attributes: [
  :id,
  :name,
  :description,
  :scoring_type,
  :min_score,
  :max_score,
  :weight,                                    # NEW
  :is_cap,                                    # NEW
  { multiple_choice_options: [ :text, :weight ] },
  :_destroy,
  multiple_choice_options_attributes: [
    :index, :text, :weight, :_destroy
  ]
]
```

---

### 3. API Contracts

#### 3.1 Assessment Page (HTML)

```
GET /clauses/:clause_id/assessment
```

**Route definition (add to `config/routes.rb` inside the top-level scope, near line 239):**

```ruby
# Terminal clause assessment page
get "clauses/:clause_id/assessment", to: "assessments#show", as: :clause_assessment
patch "clauses/:clause_id/assessment", to: "assessments#update", as: :update_clause_assessment
```

**Controller:** `AssessmentsController#show`

**Params:**
- `clause_id` (path) — UUID of a terminal (leaf) clause

**Authorization:** User must belong to a company with an active `CompanyStandard` for this clause's standard. All roles can view; `company_viewer` sees read-only.

**Data loaded (single query batch with `includes`):**

```ruby
@clause = Clause.includes(
  :clause_translations,
  :checklist_items => :checklist_item_translations,
  tool_clause: {
    tool: {
      checkpoints: {
        subcheckpoints: :tool_subcheckpoint_translations
      }
    }
  }
).find(params[:clause_id])

@tool_clause = @clause.tool_clause
@tool = @tool_clause&.tool
@checkpoints = @tool&.checkpoints&.order(:display_order) || []

# Pre-load or initialize assignment containers for this company
@assignments = load_or_initialize_assignments(@tool_clause, current_company)
```

**Response:** Renders `assessments/show.html.erb` (full page within `dashboard` layout).

**Error cases:**
- Clause not found → 404
- Not a leaf clause → redirect to `standard_path` with flash
- No tool linked → render page with info message, no scoring section

#### 3.2 Assessment Save (Form Submit)

```
PATCH /clauses/:clause_id/assessment
```

**Controller:** `AssessmentsController#update`

**Params (form data):**

```ruby
{
  assessment: {
    # Text fields: keyed by assignment container (one per checklist_item × tool_checkpoint)
    assignments: {
      "<assignment_id_or_temp_key>" => {
        summary: "text content",
        assignee_user_id: "uuid"
      },
      # ...
    },
    # Scores: keyed by subcheckpoint ID
    scores: {
      "<subcheckpoint_uuid>" => "65",   # percentage or number value
      "<subcheckpoint_uuid>" => "70",
      # ...
    },
    # Status transition
    commit: "save_draft" | "submit_for_review"
  }
}
```

**Response (Turbo):**
- On success: redirect to same assessment page with flash. The Turbo response re-renders the page with updated scores and the server-computed overall.
- On validation error: re-render form with errors.

**Backend logic (pseudocode):**

```ruby
def update
  ActiveRecord::Base.transaction do
    # 1. Persist text summaries
    params[:assessment][:assignments].each do |key, attrs|
      container = find_or_create_container(key)
      container.update!(summary: attrs[:summary].truncate(100))
      update_assignee(container, attrs[:assignee_user_id])
    end

    # 2. Persist scores
    params[:assessment][:scores].each do |subcheckpoint_id, value|
      container = find_container_for_subcheckpoint(subcheckpoint_id)
      container.update!(percentage_score: value.to_f)
    end

    # 3. Status transition
    if params[:assessment][:commit] == "submit_for_review"
      transition_to_under_review(@containers)
    else
      transition_to_in_drafts_if_not_started(@containers)
    end

    # 4. Recalculate overall score
    result = ClauseScoreCalculator.new(@tool_clause).calculate_score(current_company)

    # 5. Propagate to parent caches
    ClauseScorePropagator.propagate_from_terminal_clause(@clause, current_company)

    # 6. Audit log
    AuditLogService.log_assessment_update(@clause, current_user, changes)
  end

  redirect_to clause_assessment_path(@clause), notice: "Assessment saved."
end
```

#### 3.3 Score Calculation API (JSON, for Turbo Stream updates)

```
POST /clauses/:clause_id/assessment/calculate_score
```

**Route:**
```ruby
post "clauses/:clause_id/assessment/calculate_score",
     to: "assessments#calculate_score", as: :calculate_clause_score
```

**Params (JSON):**
```json
{
  "scores": {
    "<subcheckpoint_uuid>": 65,
    "<subcheckpoint_uuid>": 70
  }
}
```

**Response (JSON):**
```json
{
  "overall_score": 59.5,
  "weighted_sum": 59.5,
  "cap_applied": false,
  "cap_value": 65,
  "cap_attribute": "Sound",
  "formula_text": "(65×0.2)+(70×0.2)+(55×0.2)+(60×0.2)+(50×0.1)+(45×0.1) = 59.5",
  "business_rule_violation": null
}
```

**Note:** This endpoint is optional — the Stimulus controller can compute the preview locally. But it's useful for server-side validation if needed.

---

### 4. Service / Class Design

#### 4.1 `ClauseScoreCalculator` Rewrite

**File:** `app/services/clause_score_calculator.rb`

The `calculate_score(company)` method (lines 8-83) is replaced. The new implementation:

```ruby
def calculate_score(company = nil)
  allocated_points = @clause.calculated_points || 0
  tool = @tool_clause.tool
  subcheckpoints = tool.all_subcheckpoints
  total_subcheckpoints = subcheckpoints.count

  return zero_result(allocated_points, total_subcheckpoints) if subcheckpoints.empty?

  # Load assignment containers for this clause + company
  containers_scope = ToolClauseSubcheckpointAssignment
    .where(tool_clause_id: @tool_clause.id)
  containers_scope = containers_scope.where(company_id: company.id) if company.present?
  containers = containers_scope.index_by(&:tool_subcheckpoint_id)

  # Get effective weights (handles null → equal fallback)
  weights = tool.effective_weights
  cap_ids = tool.cap_subcheckpoint_ids

  # Build per-attribute scores
  weighted_sum = 0.0
  cap_values = []
  evaluated_count = 0
  details_parts = []

  subcheckpoints.each do |sub|
    container = containers[sub.id]
    score_value = extract_score(container, sub)

    if container&.percentage_score.present?
      evaluated_count += 1
    end

    w = weights[sub.id] || 0.0
    contribution = score_value * w
    weighted_sum += contribution

    if cap_ids.include?(sub.id)
      cap_values << score_value
    end

    details_parts << { name: sub.name, score: score_value, weight: w, contribution: contribution.round(2) }
  end

  # Apply cap
  cap_applied = false
  cap_attribute = nil
  cap_value = nil

  if cap_values.any?
    min_cap = cap_values.min
    if weighted_sum > min_cap
      cap_applied = true
      cap_value = min_cap
      cap_idx = cap_values.index(min_cap)
      cap_sub = subcheckpoints.select { |s| cap_ids.include?(s.id) }[cap_idx]
      cap_attribute = cap_sub&.name
    end
  end

  overall_percentage = cap_applied ? [weighted_sum, cap_value].min : weighted_sum
  final_score = allocated_points * (overall_percentage / 100.0)

  violation_msg = if cap_applied
    "Score capped by #{cap_attribute} attribute at #{cap_value.round(1)}%"
  end

  {
    score: final_score.round(2),
    percentage: overall_percentage.round(2),
    weighted_sum: weighted_sum.round(2),
    allocated_points: allocated_points,
    evaluated_count: evaluated_count,
    total_count: total_subcheckpoints,
    details: details_parts,
    cap_applied: cap_applied,
    cap_value: cap_value&.round(2),
    cap_attribute: cap_attribute,
    business_rule_violation: violation_msg
  }
end

private

def extract_score(container, subcheckpoint)
  return 0.0 unless container

  case subcheckpoint.scoring_type
  when "Percentage"
    container.percentage_score&.to_f || 0.0
  when "Number"
    # Normalize to 0-100 scale
    min = subcheckpoint.min_score || 0
    max = subcheckpoint.max_score || 100
    raw = container.score&.to_f || 0.0
    range = max - min
    range > 0 ? ((raw - min) / range * 100.0) : 0.0
  when "Multiple Choice"
    container.percentage_score&.to_f || 0.0
  else
    0.0
  end
end

def zero_result(allocated_points, total)
  {
    score: 0, percentage: 0, weighted_sum: 0,
    allocated_points: allocated_points,
    evaluated_count: 0, total_count: total,
    details: "No scoring attributes configured",
    cap_applied: false, cap_value: nil, cap_attribute: nil,
    business_rule_violation: nil
  }
end
```

**Critical change:** The old formula `average_percentage = sum(scores) / count` is replaced with `weighted_sum = sum(score_i * weight_i)` followed by `overall = min(weighted_sum, min(caps))`.

**Impact on `ClauseScorePropagator`:** No changes needed. The propagator calls `calculator.calculate_score(company)` and reads `result[:score]`, `result[:percentage]`, `result[:evaluated_count]`, and `result[:business_rule_violation]` — all of which are still present in the new return hash.

**Impact on `BusinessRuleValidator`:** The existing `average_cannot_exceed_attribute` rule type queries approved assignments directly and compares `@score_result[:percentage]` (the overall percentage). This still works — `:percentage` now returns the weighted+capped result instead of the simple average, which is the correct semantics.

#### 4.2 `AssessmentsController`

**File:** `app/controllers/assessments_controller.rb`

```ruby
class AssessmentsController < ApplicationController
  layout "dashboard"

  before_action :authenticate_user!
  before_action :set_clause
  before_action :set_tool_context
  before_action :set_assessment_data, only: [:show]
  before_action :prevent_viewer_modification, only: [:update]

  def show
    # @clause, @tool, @checkpoints, @assignments, etc. set by before_actions
    @readonly = viewer?
    @sibling_clauses = sibling_terminal_clauses
    @overall_score = compute_current_score
  end

  def update
    ActiveRecord::Base.transaction do
      persist_text_fields
      persist_scores
      apply_status_transition
    end

    ClauseScorePropagator.propagate_from_terminal_clause(@clause, current_company)
    redirect_to clause_assessment_path(@clause), notice: t(".saved")
  rescue ActiveRecord::RecordInvalid => e
    flash.now[:alert] = e.message
    set_assessment_data
    render :show, status: :unprocessable_entity
  end

  private

  def set_clause
    @clause = Clause.includes(:clause_translations).find(params[:clause_id])
    unless @clause.leaf?
      redirect_to standard_path(@clause.standard_version.standard),
                  alert: t(".not_terminal")
      return
    end
  end

  def set_tool_context
    @tool_clause = @clause.tool_clause
    @tool = @tool_clause&.tool
    @checkpoints = @tool&.checkpoints&.includes(
      subcheckpoints: :tool_subcheckpoint_translations
    )&.order(:display_order) || []
    @subcheckpoints = @checkpoints.flat_map { |cp| cp.subcheckpoints.sort_by(&:display_order) }
  end

  def set_assessment_data
    @checklist_items = @clause.checklist_items.includes(:checklist_item_translations).ordered
    @assignments_by_key = load_or_initialize_assignments
    @evidence_by_assignment = load_evidence
    @company_users = current_company.users
  end

  # Returns Hash: { [checklist_item_id, subcheckpoint_id] => assignment }
  def load_or_initialize_assignments
    return {} unless @tool_clause

    existing = ToolClauseSubcheckpointAssignment
      .where(tool_clause_id: @tool_clause.id, company_id: current_company.id)
      .includes(:users, :evidence_attachments)
      .index_by(&:tool_subcheckpoint_id)

    result = {}
    @checklist_items.each do |ci|
      @subcheckpoints.each do |sub|
        container = existing[sub.id] || ToolClauseSubcheckpointAssignment.new(
          tool_clause: @tool_clause,
          tool_subcheckpoint: sub,
          company: current_company
        )
        result[[ci.id, sub.id]] = container
      end
    end
    result
  end

  # Helper methods...
  def current_company
    # Delegate to dashboard base logic
    @current_company ||= current_user.current_company
  end

  def viewer?
    current_user.company_role(current_company) == "company_viewer"
  end

  def prevent_viewer_modification
    if viewer?
      redirect_to clause_assessment_path(@clause), alert: t(".read_only")
    end
  end

  def sibling_terminal_clauses
    parent = @clause.parent
    return [] unless parent
    parent.children.select(&:leaf?).sort_by(&:sort_order)
  end

  def compute_current_score
    return nil unless @tool_clause
    ClauseScoreCalculator.new(@tool_clause).calculate_score(current_company)
  end
end
```

#### 4.3 Stimulus Controllers

##### 4.3.1 `scoring_calculator_controller.js`

**File:** `app/javascript/controllers/scoring_calculator_controller.js`

**Purpose:** Real-time overall score preview when sliders/inputs change. Mirrors the backend `ClauseScoreCalculator` formula client-side.

```javascript
// app/javascript/controllers/scoring_calculator_controller.js
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = [
    "attributeInput",   // Each slider/number/radio input
    "overallBar",       // Progress bar fill element
    "overallValue",     // Text display of overall %
    "formulaText"       // Formula breakdown text
  ]

  static values = {
    weights: Object,    // { subcheckpoint_uuid: 0.2, ... }
    caps: Array         // [subcheckpoint_uuid, ...]
  }

  connect() {
    this.recalculate()
  }

  recalculate() {
    const scores = {}
    this.attributeInputTargets.forEach(input => {
      const id = input.dataset.subcheckpointId
      scores[id] = parseFloat(input.value) || 0
    })

    // Weighted sum
    let weightedSum = 0
    const formulaParts = []
    for (const [id, weight] of Object.entries(this.weightsValue)) {
      const score = scores[id] || 0
      weightedSum += score * weight
      formulaParts.push(`(${score}×${weight})`)
    }

    // Cap
    let capApplied = false
    let capValue = Infinity
    let capName = ""
    this.capsValue.forEach(id => {
      const score = scores[id] || 0
      if (score < capValue) {
        capValue = score
        capName = this.element.querySelector(
          `[data-subcheckpoint-id="${id}"]`
        )?.dataset?.attributeName || ""
      }
    })
    if (this.capsValue.length === 0) capValue = Infinity

    const overall = Math.min(weightedSum, capValue)
    capApplied = (capValue < weightedSum && this.capsValue.length > 0)

    // Update DOM
    this.overallBarTarget.style.width = `${Math.min(overall, 100)}%`
    this.overallValueTarget.textContent = `${overall.toFixed(1)}%`

    // Formula text
    let text = `weighted_sum = ${formulaParts.join("+")} = ${weightedSum.toFixed(1)}`
    if (this.capsValue.length > 0) {
      text += ` | Cap (${capName}) = ${capValue.toFixed(0)}`
      text += ` | Overall = MIN(${weightedSum.toFixed(1)}, ${capValue.toFixed(0)}) = ${overall.toFixed(1)}%`
    }
    this.formulaTextTarget.textContent = text
  }

  // Called by data-action="input->scoring-calculator#recalculate" on each slider/input
}
```

##### 4.3.2 `char_counter_controller.js`

**File:** `app/javascript/controllers/char_counter_controller.js`

**Purpose:** Live character count display for 100-char text fields.

```javascript
import { Controller } from "@hotwired/stimulus"

export default class extends Controller {
  static targets = ["input", "counter"]
  static values = { max: { type: Number, default: 100 } }

  connect() { this.update() }

  update() {
    const len = this.inputTarget.value.length
    this.counterTarget.textContent = `${len}/${this.maxValue}`
  }
}
```

##### 4.3.3 `tool_weight_summary_controller.js`

**File:** `app/javascript/controllers/tool_weight_summary_controller.js`

**Purpose:** Live weight sum validation and formula preview in the tool admin form.

Listens for changes on weight inputs and cap toggles within the tool form. Updates the Weight & Cap Summary panel in real-time.

---

### 5. Integration Points

#### 5.1 Entry Point: Clause Hierarchy View → Assessment Page

**Current state:** Clicking a terminal clause in the hierarchy (rendered by `app/views/standards/_clause_hierarchy_edit.html.erb` and `_clause_tree.html.erb`) currently either opens inline editing or navigates to an assignment page.

**Change:** For terminal clauses with a linked tool, the action button should link to `clause_assessment_path(clause)` instead of the individual assignment page.

**File to modify:** `app/views/standards/_clause_tree.html.erb` (or the equivalent view that renders clause action buttons). Replace:
```erb
<%= link_to assignment_path(assignment) %>
```
with:
```erb
<%= link_to clause_assessment_path(clause) if clause.leaf? && clause.tool_clause.present? %>
```

#### 5.2 Score Cache Invalidation on Tool Config Change

**Existing behavior (correct, no change needed):** `ToolsController#update` (line 514-589) already calls `invalidate_company_score_cache_for_tool_changes` when tool configuration changes. This calls `ClauseScorePropagator.invalidate_cache_for_tool_clause_changes(standard, root_clauses)`. This invalidation will correctly trigger recalculation on next view with the new formula.

#### 5.3 Dashboard Compliance Metrics

**Existing behavior (no change needed):** `DashboardController#overview` calls `calculate_average_compliance_all_standards`, which ultimately calls `ClauseScoreCalculator.calculate_standard_compliance`. Since `ClauseScoreCalculator` now uses the weighted formula, dashboard metrics automatically reflect the new scoring.

#### 5.4 Tool Scores Partial

**File:** `app/views/tools/_tool_scores.html.erb`

This view displays clause scores. It reads from `ClauseScoreCache` and calls `ClauseScoreCalculator.calculate_for_clause`. Since the calculator returns the same hash shape (`:score`, `:percentage`, `:evaluated_count`, `:total_count`, `:business_rule_violation`), this view requires no changes.

**One addition:** If `business_rule_violation` contains cap-related text (e.g., "Score capped by Sound attribute at 65%"), it will display in the existing violation indicator. This is desirable.

#### 5.5 Auditor Review Flow

**No change.** The `AssignmentsController#evaluate` action (lines 142-266) creates `AssignmentEvaluation` records and calls `ClauseScorePropagator`. The assessment page's Comments & Activity section reuses this existing component. The auditor continues to see individual assignment evaluations within the clause-level page.

---

### 6. File Inventory (New & Modified)

| Action | File | Description |
|--------|------|-------------|
| **NEW** | `db/migrate/XXX_add_weight_and_is_cap_to_tool_subcheckpoints.rb` | Migration: 2 columns |
| **NEW** | `app/controllers/assessments_controller.rb` | Assessment page controller |
| **NEW** | `app/views/assessments/show.html.erb` | Assessment page main view |
| **NEW** | `app/views/assessments/_clause_header.html.erb` | Clause header partial |
| **NEW** | `app/views/assessments/_checkpoint_box.html.erb` | Repeating checkpoint box partial |
| **NEW** | `app/views/assessments/_scoring_section.html.erb` | Scoring section partial |
| **NEW** | `app/views/assessments/_scoring_row.html.erb` | Individual scoring attribute row |
| **NEW** | `app/views/assessments/_overall_score.html.erb` | Overall score bar + formula |
| **NEW** | `app/javascript/controllers/scoring_calculator_controller.js` | Live score preview |
| **NEW** | `app/javascript/controllers/char_counter_controller.js` | Text area character counter |
| **NEW** | `app/javascript/controllers/tool_weight_summary_controller.js` | Admin weight/cap summary |
| **MODIFY** | `app/models/tool_subcheckpoint.rb` | Add validations for weight, is_cap |
| **MODIFY** | `app/models/tool.rb` | Add `effective_weights`, `cap_subcheckpoint_ids`, `all_subcheckpoints` |
| **MODIFY** | `app/services/clause_score_calculator.rb` | Rewrite `calculate_score` with weighted+cap formula |
| **MODIFY** | `app/controllers/tools_controller.rb` | Add `:weight`, `:is_cap` to strong params |
| **MODIFY** | `app/views/tools/_form.html.erb` | Add weight input, cap toggle, summary panel, preview |
| **MODIFY** | `config/routes.rb` | Add assessment routes |
| **MODIFY** | `config/locales/en.yml` | Add i18n keys for assessment page |
| **MODIFY** | `config/locales/ar.yml` | Add Arabic translations |
| **MODIFY** | `app/views/standards/_clause_tree.html.erb` | Link terminal clauses to assessment page |

---

## Functional Spec

### 1. User Flows

#### Flow 1: Assessor Opens and Completes a Terminal Clause Assessment

```
1. User navigates to Standard → Clause Hierarchy
2. User clicks action button on terminal clause "1.1 Define Purpose and Vision"
3. System navigates to /clauses/:id/assessment
4. Assessment page loads with:
   - Clause header (code, title, status, points, score)
   - Checkpoint boxes (one per ChecklistItem)
   - Scoring section (grouped by ToolCheckpoint)
   - Comments & Activity section
5. User fills in text areas for each checkpoint
   - Character counter updates live (e.g., "87/100")
6. User uploads evidence files for checkpoints
7. User assigns owners to checkpoints
8. User adjusts scoring sliders
   - Overall score bar updates in real-time
   - Formula text updates in real-time
9. User clicks "Save Draft"
   - All data persists
   - Status transitions to "in_drafts" (if was "not_started")
   - Score recalculated server-side
   - Page reloads with updated overall score
10. User clicks "Submit for Review"
    - Status transitions to "under_review"
    - Auditor is notified
```

#### Flow 2: Admin Configures an EFQM Tool

```
1. Admin navigates to Tools → Create New Tool
2. Admin fills in general info:
   - Name: "EFQM Excellence Model"
   - Linked Standard: "EFQM 2020"
   - Scoring Type: "Percentage"
3. Admin adds Assessment Categories:
   - "Approach" (with description)
   - "Deployment" (with description)
   - "Assessment & Refinement" (with description)
4. Under each category, admin adds Scoring Attributes:
   - Approach → Sound (weight: 0.2, cap: ON), Aligned (weight: 0.2)
   - Deployment → Implemented (weight: 0.2), Flexible (weight: 0.2)
   - Assessment → Evaluated & Understood (weight: 0.1), Learn & Improve (weight: 0.1)
5. Weight & Cap Summary updates live:
   - Total: 100% (Valid) ✓
   - Cap enabled: Sound
   - Formula preview: overall = MIN(weighted_sum, Sound)
6. Preview panel shows checkpoint mockup with 3 text areas
7. Admin clicks "Save & Publish Tool"
8. Tool is created and available for linking to standards
```

#### Flow 3: Navigating Between Sibling Clauses

```
1. User is on assessment page for clause "1.1"
2. User clicks "Next" button
3. System navigates to clause "1.2" assessment page
4. All data for 1.2 loads (independent from 1.1)
5. User clicks "Previous" button
6. System navigates back to clause "1.1"
7. Previous data is preserved (was saved to DB)
```

#### Flow 4: Auditor Reviews a Clause Assessment

```
1. Auditor receives notification that clause "1.1" is submitted for review
2. Auditor opens the assessment page
3. Auditor sees all checkpoint text, evidence, and scores (read-only)
4. Auditor scrolls to Comments & Activity section
5. Auditor clicks "Evaluate" / "Review"
6. Existing evaluation modal opens (no change from current flow)
7. Auditor approves or requests changes
8. Status updates; score propagates if approved
```

---

### 2. UI Behavior and States

#### 2.1 Assessment Page States

| State | Condition | Behavior |
|-------|-----------|----------|
| **Empty** | No assignments exist, all sliders at 0 | All text areas empty, all sliders at 0, Overall = 0%. "Save Draft" button active. |
| **In Progress** | Some text/scores filled | Text areas show content, sliders show values, Overall reflects partial scoring. Both Save Draft and Submit available. |
| **Under Review** | Status = `under_review` | Text areas and sliders are **disabled** (no editing while under review). Only Comments section is active. Auditor can evaluate. |
| **Approved** | Status = `approved` | Read-only. All inputs disabled. Score is final. Green status badge. |
| **Needs Changes** | Status = `needs_changes` | Text areas and sliders are **re-enabled**. Auditor feedback shown prominently. User can edit and re-submit. |
| **Read-Only (Viewer)** | User role = `company_viewer` | All inputs disabled. No Save/Submit buttons. "View Only" indicator shown. |
| **No Tool Linked** | `clause.tool_clause` is nil | Info message: "No evaluation tool is linked to this clause." No checkpoint text areas, no scoring section. Only comments visible. |
| **No Checklist Items** | Clause has 0 ChecklistItems | No checkpoint boxes rendered. Scoring section still visible (scores can still be set). |

#### 2.2 Slider Interaction

- **Range:** 0–100 (or custom min/max from ToolSubcheckpoint)
- **Step:** 1
- **Visual:** Purple accent (`#5C3984`) fill track
- **Value display:** Box to the right showing `XX%`, updates on `input` event (not just `change`)
- **Keyboard:** Arrow keys increment/decrement by 1. Page Up/Down by 10.
- **Touch:** Full-width slider track, thumb at least 44px touch target
- **Disabled state:** Gray track, no thumb interaction, muted value display

#### 2.3 Character Counter

- Displays below each text area: `X/100`
- Updates on every `input` event
- Color: `text-gray-400` normally, `text-red-500` when at limit (100/100)
- `maxlength="100"` on the `<textarea>` prevents typing beyond limit
- Pasting text that exceeds limit: browser truncates at 100

#### 2.4 Overall Score Bar

- **Width:** Fills proportionally to the overall percentage (0-100%)
- **Color:** `bg-[#5C3984]` (purple fill)
- **Badge:** White text on purple background showing `XX%`
- **Animation:** `transition-all duration-500` on width change for smooth updates
- **Capped indicator:** When a cap is active, the formula text shows which cap attribute limited the score

#### 2.5 Tooltip Behavior

- **Trigger:** Hover on `?` icon OR keyboard focus on the icon (using `tabindex="0"`)
- **Content:** `ToolSubcheckpoint.description_in(locale)`
- **Position:** Above the icon, centered
- **Dismissal:** On mouse leave or focus blur
- **Implementation:** CSS-only tooltip using `group-hover` and `group-focus-within` (no JS needed), or Stimulus tooltip controller if existing one is available

#### 2.6 CAP Badge

- Displayed inline with attribute name when `is_cap == true`
- Style: `bg-amber-50 text-amber-600 px-1.5 py-0.5 rounded text-xs font-medium`
- Text: "CAP"

---

### 3. Business Logic Rules

#### 3.1 Score Calculation Rules

| Rule | Description |
|------|-------------|
| **BL-1** | `weighted_sum = Σ(score_i × weight_i)` for all scoring attributes |
| **BL-2** | If ALL weights are null: each `weight_i = 1.0 / N` (equal weighting) |
| **BL-3** | If SOME weights are null: null weights treated as 0.0 |
| **BL-4** | `cap_value = MIN(score_j)` for all attributes where `is_cap = true` |
| **BL-5** | `overall = MIN(weighted_sum, cap_value)` |
| **BL-6** | If no caps configured: `overall = weighted_sum` |
| **BL-7** | `final_score = allocated_points × (overall / 100)` |
| **BL-8** | Unscored attributes contribute 0 to the weighted sum |
| **BL-9** | Overall score is stored in `clause_score_caches.cached_percentage` |
| **BL-10** | Cap violation text stored in `clause_score_caches.business_rule_violation` |

#### 3.2 Status Transition Rules

| From | To | Trigger | Who |
|------|----|---------|-----|
| `not_started` | `in_drafts` | Any content saved (text, score, evidence) | Contributor |
| `in_drafts` | `under_review` | "Submit for Review" button | Contributor |
| `under_review` | `auditor_approved` | Auditor approves | Auditor |
| `under_review` | `needs_changes` | Auditor rejects | Auditor |
| `auditor_approved` | `approved` | QM approves | Quality Manager |
| `needs_changes` | `in_drafts` | User edits and re-saves | Contributor |
| `needs_changes` | `under_review` | User re-submits | Contributor |

**Note:** These transitions operate at the **assignment container** level. The **clause-level status** shown in the header is derived: if ANY container is `under_review`, clause shows "Under Review". If ALL containers are `approved`, clause shows "Complete". Otherwise "In Progress" (if any have content) or "Not Started".

#### 3.3 Assignment Container Lifecycle

For the assessment page, containers are scoped to `(tool_clause, company)`. Within that scope, there is one container **per `ToolSubcheckpoint`** — the subcheckpoint determines which scoring attribute or text field group the container belongs to.

- On the assessment page, the same container's `.summary` stores text content and `.percentage_score` stores the scoring value.
- The `summary` field stores text for the relevant assessment category (the `ToolCheckpoint` that is the parent of this container's `ToolSubcheckpoint`).
- Evidence attachments are polymorphic on the container.
- User assignments (owner/assignee) are via `ToolClauseSubcheckpointAssignmentsUser`.

#### 3.4 Authorization Rules

| Action | Roles Permitted |
|--------|----------------|
| View assessment page | All roles (super_admin, company_admin, company_quality_manager, company_viewer, delegated_admin) |
| Edit text / scores | All except `company_viewer` |
| Submit for review | Contributor (assigned user) or company_quality_manager+ |
| Evaluate (approve/reject) | Auditor, company_quality_manager, company_admin |
| Configure tool (weights/caps) | super_admin, delegated_admin with `manage_tools` |

---

### 4. Validation Rules

#### 4.1 Server-Side Validations

| Field | Rule | Error Message |
|-------|------|---------------|
| `tool_subcheckpoints.weight` | `0.0 ≤ weight ≤ 1.0` when present | "Weight must be between 0 and 1" |
| `tool_subcheckpoints.is_cap` | Boolean (true/false) | (framework-enforced) |
| Text area summary | `length ≤ 100` | "Summary must be 100 characters or fewer" |
| Percentage score | `0 ≤ value ≤ 100` (or min/max) | "Score must be between {min} and {max}" |
| Number score | `min_score ≤ value ≤ max_score` | "Score must be between {min} and {max}" |
| Multiple choice value | Must match a defined option | "Invalid choice selected" |
| Assignment company_id | Must equal `current_user.current_company.id` | (silent enforcement, not user-facing) |

#### 4.2 Client-Side Validations

| Field | Rule | Behavior |
|-------|------|----------|
| Text area | `maxlength="100"` | Browser truncates input |
| Slider | `min="0" max="100"` (or custom) | Browser constrains range |
| Number input | `min` / `max` attributes | Browser constrains range |
| Weight (admin) | `min="0" max="1" step="0.05"` | Browser constrains range |
| Weight sum (admin) | Sum of all weights == 1.0 | Warning banner (yellow), not blocking |

---

## Mockups

### Screen 1: Terminal Clause Assessment Page

```
┌─────────────────────────────────────────────────────────────┐
│ EFQM 2020 > 1. Direction > 1.1 Define Purpose and Vision   │ ← Breadcrumb
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1.1 Define Purpose and Vision          [In Progress]       │ ← H1 + badge
│                                                             │
│  An outstanding organisation defines its purpose and        │ ← Summary
│  develops a vision that inspires...                         │
│                                                             │
│  Allocated Points: 100  |  Current Score: 62%  |  Tool: EFQM│ ← Metadata
│                                                             │
│                              [← Previous]  [Next →]         │ ← Navigation
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  CHECKPOINTS                                                │
│                                                             │
│ ┌───────────────────────────────────────────────────────┐   │
│ │ (1) Purpose Statement & Values           [Complete]   │   │ ← Checkpoint header
│ ├───────────────────────────────────────────────────────┤   │
│ │ ┌─────────────────────────────────────────────────┐   │   │
│ │ │ The organization has a clearly defined purpose  │   │   │ ← Guidance text
│ │ │ statement that reflects its mission and values. │   │   │   (blue box)
│ │ └─────────────────────────────────────────────────┘   │   │
│ │                                                       │   │
│ │ ┌─────────────┐ ┌─────────────┐ ┌─────────────────┐  │   │ ← Text areas
│ │ │ APPROACH    │ │ DEPLOYMENT  │ │ ASSESSMENT &    │  │   │   (3 columns)
│ │ │             │ │             │ │ REFINEMENT      │  │   │
│ │ │ [textarea]  │ │ [textarea]  │ │ [textarea]      │  │   │
│ │ │      87/100 │ │      92/100 │ │      88/100     │  │   │ ← Char counters
│ │ └─────────────┘ └─────────────┘ └─────────────────┘  │   │
│ │                                                       │   │
│ │ Evidence:                        Owner / Assignee:    │   │
│ │ ┌─────────────────────────┐     ┌───────────────┐    │   │
│ │ │[Upload File] [Add Link] │     │ ●SA S. Ahmed  │    │   │
│ │ │ 📄 Purpose_2024.pdf  ✕ │     │ Quality Mgr   │    │   │
│ │ │ 🔗 Town Hall Q3      ✕ │     └───────────────┘    │   │
│ │ └─────────────────────────┘                           │   │
│ └───────────────────────────────────────────────────────┘   │
│                                                             │
│ ┌───────────────────────────────────────────────────────┐   │
│ │ (2) Vision Development & Communication  [Under Review]│   │ ← Checkpoint 2
│ ├───────────────────────────────────────────────────────┤   │
│ │  ... (same structure as above) ...                    │   │
│ └───────────────────────────────────────────────────────┘   │
│                                                             │
│ ┌───────────────────────────────────────────────────────┐   │
│ │ (3) Strategic Alignment                 [Not Started] │   │ ← Checkpoint 3
│ │  ... (same structure, empty fields) ...               │   │
│ └───────────────────────────────────────────────────────┘   │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  SCORING                                                    │
│  Rate each attribute using the sliders. The overall score   │
│  is calculated automatically using configured weights/caps. │
│                                                             │
│  ┃ APPROACH                                                 │ ← Group header
│  │                                                          │
│  │  Sound  (?) [CAP]  ═══════════●═══════  [65%]           │ ← Slider row
│  │  Aligned (?)       ═══════════════●═══  [70%]           │
│  │                                                          │
│  ┃ DEPLOYMENT                                               │
│  │                                                          │
│  │  Implemented (?)   ═══════●═══════════  [55%]           │
│  │  Flexible    (?)   ════════●══════════  [60%]           │
│  │                                                          │
│  ┃ ASSESSMENT & REFINEMENT                                  │
│  │                                                          │
│  │  Evaluated & Understood (?)  ═════●═══  [50%]           │
│  │  Learn & Improve        (?)  ════●════  [45%]           │
│  │                                                          │
│  ──────────────────────────────────────────────────         │
│  ┌──────────────────────────────────────────────────────┐   │
│  │  OVERALL  ██████████████████████████████░░░░  [62%]  │   │ ← Overall bar
│  └──────────────────────────────────────────────────────┘   │
│  Formula: weighted_sum = (65×0.2)+(70×0.2)+(55×0.2)+       │ ← Formula text
│  (60×0.2)+(50×0.1)+(45×0.1) = 59.5 |                      │
│  Cap (Sound) = 65 | Overall = MIN(59.5, 65) = 59.5%        │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  COMMENTS & ACTIVITY                                        │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ [You] [Add a comment...                    ] [Post]  │   │ ← Comment input
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  ✓ Sarah Ahmed updated Approach text for Checkpoint 1       │ ← Activity log
│    2 hours ago                                              │
│  ↑ Sarah Ahmed uploaded Purpose_Statement_2024.pdf          │
│    3 hours ago                                              │
│  💬 Mohammed Ali: "Please provide more detail..."           │ ← Comment
│    Yesterday at 4:30 PM                                     │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  [← Back to Clause List]    [Save Draft] [Submit for Review →]│
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

### Screen 2: Tool Admin (Create/Edit)

```
┌─────────────────────────────────────────────────────────────┐
│  Create New Tool                        [Cancel] [Save Tool]│
│  Configure assessment categories, scoring attributes,       │
│  weights, and caps for your evaluation tool.                │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  GENERAL INFORMATION                                        │
│  ┌──────────────────────┐  ┌──────────────────────┐        │
│  │ Tool Name            │  │ Linked Standard      │        │
│  │ [EFQM Excellence   ] │  │ [EFQM 2020       ▼] │        │
│  └──────────────────────┘  └──────────────────────┘        │
│  ┌─────────────────────────────────────────────────┐        │
│  │ Description                                     │        │
│  │ [The EFQM Excellence Model is a comprehensive ] │        │
│  └─────────────────────────────────────────────────┘        │
│  ┌──────────────────────┐  ┌──────────────────────┐        │
│  │ Scoring Type         │  │ Scoring Level        │        │
│  │ [Percentage (Slider)▼│  │ [Terminal Clause Lv▼]│        │
│  └──────────────────────┘  └──────────────────────┘        │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│ ℹ How it works: Assessment Categories define the text      │ ← Info banner
│   areas per checkpoint. Scoring Attributes define the       │
│   sliders/inputs in the scoring section.                    │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  ASSESSMENT CATEGORIES                     [+ Add Category] │
│  Each category creates a labeled text area per checkpoint   │
│                                                             │
│ ┌───────────────────────────────────────────────────────┐   │
│ │ ⠿ (1) [Approach                              ] [🗑]  │   │ ← Category row
│ │   [How the organization plans and develops...      ]  │   │   (drag handle,
│ │                                                       │   │    name, desc,
│ │   SCORING ATTRIBUTES                 [+ Add Attribute]│   │    delete)
│ │   ┌──────────┬────────────────────┬───────┬─────┬──┐  │   │
│ │   │ Name     │ Description        │Weight │ Cap │  │  │   │ ← Attr header
│ │   ├──────────┼────────────────────┼───────┼─────┼──┤  │   │
│ │   │[Sound   ]│[Clearly defined  ]│[ 0.2 ]│[●ON]│ ✕│  │   │ ← Sound (cap)
│ │   ├──────────┼────────────────────┼───────┼─────┼──┤  │   │
│ │   │[Aligned ]│[Supports strategy]│[ 0.2 ]│[○  ]│ ✕│  │   │ ← Aligned
│ │   └──────────┴────────────────────┴───────┴─────┴──┘  │   │
│ └───────────────────────────────────────────────────────┘   │
│                                                             │
│ ┌───────────────────────────────────────────────────────┐   │
│ │ ⠿ (2) [Deployment                            ] [🗑]  │   │ ← Category 2
│ │   [How the organization implements...              ]  │   │
│ │   SCORING ATTRIBUTES                 [+ Add Attribute]│   │
│ │   │[Implmntd]│[Approaches put.. ]│[ 0.2 ]│[○  ]│ ✕│  │   │
│ │   │[Flexible]│[Adapts to needs  ]│[ 0.2 ]│[○  ]│ ✕│  │   │
│ └───────────────────────────────────────────────────────┘   │
│                                                             │
│ ┌───────────────────────────────────────────────────────┐   │
│ │ ⠿ (3) [Assessment & Refinement               ] [🗑]  │   │ ← Category 3
│ │   [How the organization measures and learns...     ]  │   │
│ │   SCORING ATTRIBUTES                 [+ Add Attribute]│   │
│ │   │[Eval&Und]│[Measured for eff.]│[ 0.1 ]│[○  ]│ ✕│  │   │
│ │   │[Learn&Im]│[Outputs used to..]│[ 0.1 ]│[○  ]│ ✕│  │   │
│ └───────────────────────────────────────────────────────┘   │
│                                                             │
│  [+ Add Assessment Category]                                │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  WEIGHT & CAP SUMMARY                                       │
│                                                             │
│  Weight Distribution:          Score Caps:                   │
│  Sound       ████░░░░ 20%     ┌──────────────────────────┐ │
│  Aligned     ████░░░░ 20%     │ ⚠ When cap attributes    │ │
│  Implemented ████░░░░ 20%     │ are enabled, overall     │ │
│  Flexible    ████░░░░ 20%     │ score cannot exceed the  │ │
│  Eval & Und  ██░░░░░░ 10%     │ MIN of capped values.    │ │
│  Learn & Imp ██░░░░░░ 10%     └──────────────────────────┘ │
│  ─────────────────────         🔒 Sound — Cap enabled       │
│  Total: 100% (Valid) ✓        🔓 Others — No cap           │
│                                                             │
│  Formula Preview:                                           │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ weighted_sum = (Sound×0.2) + (Aligned×0.2) +        │   │
│  │   (Implemented×0.2) + (Flexible×0.2) +              │   │
│  │   (Eval×0.1) + (Learn×0.1)                          │   │
│  │ overall = MIN(weighted_sum, Sound)                   │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  PREVIEW: ASSESSMENT PAGE LAYOUT                            │
│                                                             │
│  ┌─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┐   │
│  │ [Checkpoint 1] The organization has a clear...     │   │
│  │ ┌──────────┐ ┌──────────┐ ┌──────────────────┐    │   │
│  │ │ Approach │ │Deployment│ │Assessment & Refin│    │   │
│  │ │(100 char)│ │(100 char)│ │(100 char)        │    │   │
│  │ └──────────┘ └──────────┘ └──────────────────┘    │   │
│  │ [Evidence upload area]  [Assignee picker]          │   │
│  └─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ─ ┘   │
│                                                             │
├─────────────────────────────────────────────────────────────┤
│  [Cancel]                      [Save as Draft] [Save & Publish]│
└─────────────────────────────────────────────────────────────┘
```

### Screen 3: Weight Sum Warning State (Tool Admin)

```
  Weight Distribution:
  Sound       ████░░░░ 20%
  Aligned     ████░░░░ 20%
  Implemented ████░░░░ 20%
  Flexible    ████░░░░ 20%
  ─────────────────────
  Total: 80% ⚠ Weights do not sum to 100%.
              Scoring may produce unexpected results.

  [Save is NOT blocked — warning only]
```

### Screen 4: Assessment Page — Empty State

```
┌─────────────────────────────────────────────────────────────┐
│ EFQM 2020 > 1. Direction > 1.1 Define Purpose and Vision   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  1.1 Define Purpose and Vision          [Not Started]       │
│  Allocated Points: 100  |  Current Score: 0%                │
│                                                             │
│ ┌───────────────────────────────────────────────────────┐   │
│ │ (1) Purpose Statement & Values           [Not Started]│   │
│ │ ┌─────────────────────────────────────────────────┐   │   │
│ │ │ The organization has a clearly defined purpose  │   │   │
│ │ └─────────────────────────────────────────────────┘   │   │
│ │ ┌─────────────┐ ┌─────────────┐ ┌─────────────────┐  │   │
│ │ │ APPROACH    │ │ DEPLOYMENT  │ │ ASSESSMENT &    │  │   │
│ │ │ [          ]│ │ [          ]│ │ [              ]│  │   │
│ │ │       0/100 │ │       0/100 │ │          0/100 │  │   │
│ │ └─────────────┘ └─────────────┘ └─────────────────┘  │   │
│ │ Evidence: [Upload File] [Add Link]  No evidence yet   │   │
│ │ Owner: [Select assignee... ▼]                         │   │
│ └───────────────────────────────────────────────────────┘   │
│                                                             │
│  SCORING                                                    │
│  ┃ APPROACH                                                 │
│  │  Sound  (?) [CAP]  ●═══════════════════  [ 0%]          │
│  │  Aligned (?)       ●═══════════════════  [ 0%]          │
│  ┃ DEPLOYMENT                                               │
│  │  Implemented (?)   ●═══════════════════  [ 0%]          │
│  │  Flexible    (?)   ●═══════════════════  [ 0%]          │
│  ┃ ASSESSMENT & REFINEMENT                                  │
│  │  Eval & Understood (?)  ●══════════════  [ 0%]          │
│  │  Learn & Improve   (?)  ●══════════════  [ 0%]          │
│  ──────────────────────────────────────────────────         │
│  OVERALL  ░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░░  [ 0%]        │
│                                                             │
│  [← Back to Clause List]    [Save Draft] [Submit for Review →]│
└─────────────────────────────────────────────────────────────┘
```

### Screen 5: Assessment Page — No Tool Linked

```
┌─────────────────────────────────────────────────────────────┐
│ ISO 9001 > 4. Context > 4.1 Understanding the Organization │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│  4.1 Understanding the Organization                         │
│                                                             │
│  ┌──────────────────────────────────────────────────────┐   │
│  │ ℹ No evaluation tool is linked to this clause.       │   │
│  │   Contact your administrator to link an assessment   │   │
│  │   tool before starting the evaluation.               │   │
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  COMMENTS & ACTIVITY                                        │
│  [comments section unchanged]                               │
│                                                             │
│  [← Back to Clause List]                                    │
└─────────────────────────────────────────────────────────────┘
```

### Screen 6: Assessment Page — Read-Only (Viewer)

```
┌─────────────────────────────────────────────────────────────┐
│ EFQM 2020 > 1. Direction > 1.1 Define Purpose and Vision   │
├─────────────────────────────────────────────────────────────┤
│  ┌──────────────────────────────────────────────────────┐   │
│  │ 👁 You are viewing this assessment in read-only mode │   │ ← Viewer banner
│  └──────────────────────────────────────────────────────┘   │
│                                                             │
│  1.1 Define Purpose and Vision          [Complete]          │
│                                                             │
│  ... (all text areas DISABLED, gray background) ...         │
│  ... (all sliders DISABLED, muted styling) ...              │
│  ... (no Upload/Add Link buttons) ...                       │
│  ... (assignee shown but not editable) ...                  │
│                                                             │
│  SCORING (read-only)                                        │
│  Sound [CAP] ═══════════════●═══════  65%  (disabled)       │
│  ...                                                        │
│  OVERALL ████████████████████████████░░░░  62%              │
│                                                             │
│  [← Back to Clause List]                                    │
│  (NO Save Draft / Submit buttons)                           │
└─────────────────────────────────────────────────────────────┘
```

### Screen 7: ISO Tool — Single Text Area Variant

```
┌───────────────────────────────────────────────────────┐
│ (1) Clause 4.1.a - General Requirements  [Not Started]│
├───────────────────────────────────────────────────────┤
│ ┌─────────────────────────────────────────────────┐   │
│ │ The organization shall determine external and   │   │ ← Guidance
│ │ internal issues relevant to its purpose.        │   │
│ └─────────────────────────────────────────────────┘   │
│                                                       │
│ ┌─────────────────────────────────────────────────┐   │ ← SINGLE text area
│ │ FULFILLMENT                                     │   │   (ISO tool has
│ │ [                                              ]│   │    1 category)
│ │                                          0/100  │   │
│ └─────────────────────────────────────────────────┘   │
│                                                       │
│ Evidence: [Upload File] [Add Link]                    │
│ Owner: [Select assignee... ▼]                         │
└───────────────────────────────────────────────────────┘
```

### State Diagram: Assessment Status Flow

```
                    ┌─────────────┐
                    │ not_started │
                    └──────┬──────┘
                           │ (any content saved)
                           ▼
                    ┌─────────────┐
               ┌───▶│  in_drafts  │◀──────────────┐
               │    └──────┬──────┘               │
               │           │ (Submit for Review)   │
               │           ▼                       │
               │    ┌──────────────┐               │
               │    │ under_review │               │
               │    └───┬─────┬───┘               │
               │        │     │                    │
               │ (reject)│     │(auditor approve)  │
               │        ▼     ▼                    │
               │  ┌────────┐ ┌──────────────────┐  │
               │  │ needs  │ │auditor_approved  │  │
               └──│changes │ └────────┬─────────┘  │
                  └────┬───┘          │             │
                       │              │(QM approve) │
                       │              ▼             │
                       │       ┌───────────┐       │
                       └──────▶│  approved  │       │
                               └───────────┘       │
                                                    │
              (User edits after needs_changes) ─────┘
```

### State Diagram: Score Calculation Flow

```
┌─────────────────────────┐
│ User moves slider / enters score │
└─────────────┬───────────┘
              │
              ▼
┌─────────────────────────┐
│ Stimulus: recalculate() │  ← CLIENT-SIDE (preview only)
│                         │
│ 1. Read all slider vals │
│ 2. weighted_sum = Σ(s×w)│
│ 3. cap = MIN(cap_vals)  │
│ 4. overall = MIN(ws, c) │
│ 5. Update bar + formula │
└─────────────────────────┘
              │
              │ User clicks "Save Draft"
              ▼
┌─────────────────────────┐
│ Form POST to server     │
└─────────────┬───────────┘
              │
              ▼
┌─────────────────────────┐
│ AssessmentsController   │  ← SERVER-SIDE (canonical)
│ #update                 │
│                         │
│ 1. Persist scores to DB │
│ 2. ClauseScoreCalculator│
│    .calculate_score()   │
│    → weighted + cap     │
│ 3. Update cache         │
│ 4. Propagator: update   │
│    parent caches        │
│ 5. AuditLog: record     │
└─────────────┬───────────┘
              │
              ▼
┌─────────────────────────┐
│ Redirect back to page   │
│ Page renders with        │
│ server-computed score    │
└─────────────────────────┘
```

### Data Flow: How Tool Config Maps to Assessment Page

```
TOOL ADMIN (configuration)              ASSESSMENT PAGE (rendering)
─────────────────────────              ──────────────────────────

Tool                                    
├── ToolCheckpoint "Approach"  ───────▶ Text area label: "APPROACH"
│   ├── ToolSubcheckpoint "Sound"       ├── per checkpoint box
│   │   weight: 0.2, is_cap: true  ──▶ Scoring row: slider + CAP badge
│   └── ToolSubcheckpoint "Aligned"     │
│       weight: 0.2, is_cap: false ──▶ Scoring row: slider
│                                       │
├── ToolCheckpoint "Deployment" ──────▶ Text area label: "DEPLOYMENT"
│   ├── ToolSubcheckpoint "Impl"        ├── per checkpoint box
│   │   weight: 0.2              ────▶ Scoring row: slider
│   └── ToolSubcheckpoint "Flex"        │
│       weight: 0.2              ────▶ Scoring row: slider
│                                       │
└── ToolCheckpoint "Assess&Ref" ──────▶ Text area label: "ASSESS. & REFIN."
    ├── ToolSubcheckpoint "Eval"        ├── per checkpoint box
    │   weight: 0.1              ────▶ Scoring row: slider
    └── ToolSubcheckpoint "Learn"       │
        weight: 0.1              ────▶ Scoring row: slider

        3 ToolCheckpoints = 3 text areas per checkpoint box
        6 ToolSubcheckpoints = 6 scoring rows grouped by parent
```

### Data Flow: Assignment Container Mapping

```
Terminal Clause "1.1" has 3 ChecklistItems (checkpoints)
Tool has 3 ToolCheckpoints with 6 ToolSubcheckpoints total

For Company X, the containers look like:

ToolClauseSubcheckpointAssignment records:
┌──────────────┬───────────────────┬───────────┬────────┬──────────────────┐
│ tool_clause   │ tool_subcheckpoint│ company   │ summary│ percentage_score │
├──────────────┼───────────────────┼───────────┼────────┼──────────────────┤
│ TC(1.1,EFQM) │ Sound             │ Company X │ null   │ 65.00            │
│ TC(1.1,EFQM) │ Aligned           │ Company X │ null   │ 70.00            │
│ TC(1.1,EFQM) │ Implemented       │ Company X │ null   │ 55.00            │
│ TC(1.1,EFQM) │ Flexible          │ Company X │ null   │ 60.00            │
│ TC(1.1,EFQM) │ Evaluated & Und   │ Company X │ null   │ 50.00            │
│ TC(1.1,EFQM) │ Learn & Improve   │ Company X │ null   │ 45.00            │
└──────────────┴───────────────────┴───────────┴────────┴──────────────────┘

Note: The `summary` field on these containers stores the text from the
assessment text areas. Since there's one container per subcheckpoint (not
per checklist_item × subcheckpoint), text area content for each checkpoint
is stored separately per checkpoint. This means the assessment page creates
containers for EACH (checklist_item, subcheckpoint) combination by using
the ToolClauseSubcheckpointAssignment's summary field.

Scoring values (percentage_score) are shared across checkpoints — they
represent the CLAUSE-LEVEL score for that attribute, not per-checkpoint.
```

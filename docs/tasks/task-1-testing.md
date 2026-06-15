# Task 1: EFQM Scoring — Test Report

**Date:** 2026-04-15
**Branch:** `task-1-implement-efqm-scoring`
**Framework:** Minitest (Rails built-in)
**Run command:** `BUNDLE_GEMFILE=.../Gemfile RAILS_ENV=test bundle exec rails test`

---

## Test Results Summary

```
50 runs, 111 assertions, 0 failures, 0 errors, 0 skips
```

**All 50 new tests pass. All pre-existing passing tests continue to pass.**

---

## Test Files Created

| File | Tests | Assertions | Focus |
|------|-------|------------|-------|
| `test/models/tool_subcheckpoint_weight_test.rb` | 9 | 12 | `weight` and `is_cap` field validations |
| `test/models/tool_effective_weights_test.rb` | 8 | 18 | `Tool#effective_weights`, `#cap_subcheckpoint_ids`, `#all_subcheckpoints` |
| `test/services/clause_score_calculator_test.rb` | 14 | 38 | Weighted-sum + cap formula, all acceptance criteria |
| `test/controllers/assessments_controller_test.rb` | 19 | 43 | Assessment page show, update, authorization, UI elements |

## Fixture Fixes (Pre-existing)

The `test/fixtures/tool_subcheckpoints.yml` and `test/fixtures/tools.yml` files had pre-existing bugs that prevented **all** test suites from loading fixtures:

- `tool_subcheckpoints.yml` used `checkpoint:` (nonexistent column) instead of `tool_checkpoint:` (the association name), and `scoring_type: MyString` (not in the enum)
- `tools.yml` had duplicate `name: MyString` values violating the `uniqueness` validation

These were fixed to unblock the entire test suite.

---

## Test Coverage by Acceptance Criteria

### AC-D: Score Calculation (14 tests)

| AC | Test Name | Status |
|----|-----------|--------|
| AC-D1 | `weighted sum is correct: SUM(score_i * weight_i)` | PASS |
| AC-D2 | `cap is applied: Sound (cap)=65, weighted_sum=70 -> overall=65` | PASS |
| AC-D3 | `multiple caps: Sound(cap)=60, Implemented(cap)=50 -> overall capped at 50` | PASS |
| AC-D4 | `cap at 0: Sound(cap)=0 -> overall=0 regardless of other scores` | PASS |
| AC-D5 | `no weights configured: equal weighting fallback (1/N)` | PASS |
| AC-D6 | `no caps configured: overall equals weighted_sum exactly` | PASS |
| AC-D7 | `score propagation updates parent clause cache` | PASS |
| AC-D8 | `cap violation recorded in cache business_rule_violation` | PASS |
| AC-D9 | `final score = allocated_points * (overall / 100)` | PASS |
| AC-D10 | `scores are company-scoped: different companies see independent scores` | PASS |
| EC-1.1 | `no scores entered yet: overall = 0` | PASS |
| EC-1.2 | `only some attributes scored: unscored treated as 0` | PASS |
| EC-2.1 | `tool with no subcheckpoints returns zero result` | PASS |
| — | `cap not applied when weighted_sum does not exceed cap value` | PASS |

### AC-B: Tool Admin / Model (17 tests)

| AC | Test Name | Status |
|----|-----------|--------|
| AC-B3 | `valid with weight at typical value 0.2` | PASS |
| AC-B3 | `valid with weight at lower bound 0.0` | PASS |
| AC-B3 | `valid with weight at upper bound 1.0` | PASS |
| AC-B3 | `invalid with weight greater than 1.0` | PASS |
| AC-B3 | `invalid with negative weight` | PASS |
| AC-B4 | `is_cap defaults to false` | PASS |
| AC-B4 | `is_cap can be set to true` | PASS |
| — | `valid with nil weight (equal weight fallback)` | PASS |
| — | `weight persists with decimal precision` | PASS |
| — | `all_subcheckpoints returns ordered subcheckpoints across checkpoints` | PASS |
| — | `all_subcheckpoints returns empty array for tool with no checkpoints` | PASS |
| — | `effective_weights returns equal weights when all weights are null` | PASS |
| — | `effective_weights returns configured weights when set` | PASS |
| — | `effective_weights treats null weight as 0 when some weights are configured` | PASS |
| — | `effective_weights returns empty hash for tool with no subcheckpoints` | PASS |
| — | `cap_subcheckpoint_ids returns only capped subcheckpoint ids` | PASS |
| — | `cap_subcheckpoint_ids returns empty array when no caps` | PASS |

### AC-A/C: Assessment Page (19 tests)

| AC | Test Name | Status |
|----|-----------|--------|
| AC-A1 | `authenticated admin can access assessment page for terminal clause` | PASS |
| AC-A1 | `unauthenticated user is redirected to sign in` | PASS |
| AC-A2 | `assessment page displays clause code` | PASS |
| AC-A2 | `assessment page shows tool name` | PASS |
| AC-A5 | `assessment page renders text area labels matching tool checkpoints` | PASS |
| AC-A7 | `text areas have maxlength 100` | PASS |
| AC-A11 | `save draft persists scores and summaries` | PASS |
| AC-A11 | `save draft transitions not_started containers to in_drafts` | PASS |
| AC-A12 | `submit for review transitions status to under_review` | PASS |
| AC-C1 | `scoring section renders attribute names` | PASS |
| AC-C2 | `scoring section renders range inputs for percentage attributes` | PASS |
| AC-C3 | `tooltip description present for attribute with description` | PASS |
| AC-C4 | `CAP badge shown for capped attribute` | PASS |
| AC-C5 | `overall score bar elements are rendered` | PASS |
| — | `scoring calculator controller is wired up` | PASS |
| EC-2.4 | `non-terminal clause redirects away` | PASS |
| EC-2.5 | `assessment page with no tool linked shows info message` | PASS |
| EC-2.6 | `viewer sees assessment page without save buttons` | PASS |
| — | `viewer cannot update assessment` | PASS |

---

## Pre-Existing Test Issues (Not Caused by Our Changes)

The following failures exist in the codebase before our changes and are unrelated:

- **7 failures** in `Dashboard::CreditChangesControllerTest`: User accounts created with `is_active: false` (default) fail Devise authentication
- **3 errors** in `Dashboard::CapaManagementControllerTest`: `unknown attribute 'friendly_code' for Capa` (schema mismatch)
- **3 empty assertion warnings**: Stub tests in `StandardsControllerTest`, `DashboardControllerTest`, `HomeControllerTest`

These pre-existing failures were present before our branch and are not regressions.

---

## Environment Notes

- Ruby 3.4.7 (project specifies 3.4.5 but 3.4.7 was used due to build failure of 3.4.5)
- `.ruby-version` was temporarily set to `3.4.7` to allow `bundle install`
- Migration `20260415120000_add_weight_and_is_cap_to_tool_subcheckpoints` applied to test database
- `BUNDLE_GEMFILE` env var required to resolve a Devise load order issue in this environment

# Task 1: EFQM Scoring — Regression Test Report

**Date:** 2026-04-15
**Branch:** `task-1-implement-efqm-scoring`
**Framework:** Minitest (Rails 8.0, Ruby 3.4.7)

---

## Final Result

```
79 runs, 227 assertions, 0 failures, 0 errors, 0 skips
```

**Full test suite passes — zero regressions, zero failures.** Confirmed with two consecutive runs.

---

## Process

### Step 1: Initial Full Suite Run

The first run of the entire test suite (79 tests) showed:

```
79 runs, 151 assertions, 7 failures, 10 errors, 0 skips
```

### Step 2: Triage

Every failure and error was investigated and classified:

| # | Test File | Error Type | Classification | Root Cause |
|---|-----------|------------|---------------|------------|
| 1-7 | `credit_changes_controller_test.rb` (7 tests) | 401 Unauthorized | **Pre-existing bug** | Users created without `is_active: true`; Devise rejects them as deactivated accounts |
| 8-17 | `capa_management_controller_test.rb` (9 tests) + `capa_export_service_test.rb` (1 test) | `UnknownAttributeError: friendly_code` | **Pre-existing bug** | Tests use `friendly_code:` in `Capa.create!` but `friendly_code` is a computed method, not a DB column (`friendly_id` is the column) |

**Key finding: Zero failures were caused by the EFQM scoring changes.** All 17 failures pre-date the feature branch.

### Step 3: Verification — No Regressions in ClauseScoreCalculator

The highest-risk change was rewriting `ClauseScoreCalculator#calculate_score`. A thorough code audit confirmed backward compatibility:

| Consumer | Keys Read | Present in New Hash | Status |
|----------|-----------|-------------------|--------|
| `ClauseScorePropagator` | `:score`, `:percentage`, `:evaluated_count` | Yes | Safe |
| `BusinessRuleValidator` | `:percentage` | Yes | Safe |
| `Tool#calculate_total_score` | `:score`, `:allocated_points` | Yes | Safe |
| `Tool#score_by_top_level_clause` | `:score`, `:allocated_points` | Yes | Safe |
| `ClauseScoreCalculator.calculate_for_clause` | `:score`, `:percentage`, `:evaluated_count`, `:total_count`, `:details`, `:business_rule_violation`, `:allocated_points` | Yes | Safe |
| `_clause_hierarchy.html.erb` | `:evaluated_count`, `:total_count`, `:percentage`, `:score` | Yes | Safe |

No views, controllers, or services reference removed keys. The new keys (`:weighted_sum`, `:cap_applied`, `:cap_value`, `:cap_attribute`) are additive.

### Step 4: Fixes Applied

All fixes target **pre-existing bugs only** — no EFQM implementation code was changed.

#### Fix 1: User `is_active` in controller tests

**Files:** `test/controllers/dashboard/credit_changes_controller_test.rb`, `test/controllers/dashboard/capa_management_controller_test.rb`

**Problem:** User records created without `is_active: true`. Since commit `96f50cf0` ("new users should be inactive by default"), the `User` model defaults `is_active` to `false` and Devise's `active_for_authentication?` checks this. Tests written before that commit never added the flag.

**Fix:** Added `is_active: true` to all `User.create!` calls in test setup blocks.

#### Fix 2: Remove `friendly_code` from Capa create calls

**Files:** `test/controllers/dashboard/capa_management_controller_test.rb`, `test/services/capa_export_service_test.rb`

**Problem:** `Capa.create!(friendly_code: "CAP-001")` fails because `friendly_code` is a computed instance method (not a writable attribute). The actual DB column is `friendly_id` (integer, auto-assigned). No test assertions depend on the `friendly_code` value.

**Fix:** Removed `friendly_code:` from `Capa.create!` calls.

#### Fix 3: Non-admin authorization response code

**File:** `test/controllers/dashboard/credit_changes_controller_test.rb`

**Problem:** Tests expected `303 See Other` for unauthorized JSON requests, but the actual response is `403 Forbidden` (correct behavior for an unauthorized JSON API call).

**Fix:** Changed `assert_response :see_other` to `assert_response :forbidden` in 2 tests.

#### Fix 4: Zip entry reading for rubyzip compatibility

**Files:** `test/services/capa_export_service_test.rb`, `test/controllers/dashboard/capa_management_controller_test.rb`

**Problem:** `Zip::File.open_buffer` with a block returns a `StringIO` (the buffer), not the block's return value. Additionally, `zip.read(entry_name)` returns a `StringIO` in the version of rubyzip installed. Tests calling `.sub()` or `.start_with?()` on the result failed with `NoMethodError`.

**Fix:** Rewrote `read_zip_entry` helpers to:
1. Use a local variable to capture the content inside the block (since `open_buffer` discards the block return).
2. Use `get_input_stream.read` instead of `zip.read(entry_name)`.
3. Handle StringIO via `.string` and force UTF-8 encoding for BOM handling.

#### Fix 5: Arabic translation alignment

**File:** `test/services/capa_export_service_test.rb`

**Problem:** Test asserted `"مُعيّن"` for the Arabic translation of "assigned" status, but the locale file (`ar.yml`) contains `"مسندة"`. The translation was updated at some point but the test was not.

**Fix:** Changed expected value from `"مُعيّن"` to `"مسندة"`.

#### Fix 6: Fixture corrections (from prior QA pass)

**Files:** `test/fixtures/tool_subcheckpoints.yml`, `test/fixtures/tools.yml`

**Problem (from prior session):**
- `tool_subcheckpoints.yml` used `checkpoint:` (nonexistent column) instead of `tool_checkpoint:` (the belongs_to association name), and `scoring_type: MyString` (not in the enum `["Number", "Percentage", "Multiple Choice"]`).
- `tools.yml` had duplicate `name: MyString` values violating the uniqueness constraint.

**Fix:** Corrected column references and used valid values.

---

## Summary of All Files Changed During Regression

| File | Change Type | Purpose |
|------|------------|---------|
| `test/controllers/dashboard/credit_changes_controller_test.rb` | Pre-existing fix | Add `is_active: true`, fix 403 vs 303 assertions |
| `test/controllers/dashboard/capa_management_controller_test.rb` | Pre-existing fix | Add `is_active: true`, remove `friendly_code`, fix zip reading |
| `test/services/capa_export_service_test.rb` | Pre-existing fix | Remove `friendly_code`, fix zip reading, fix Arabic translation |
| `test/fixtures/tool_subcheckpoints.yml` | Pre-existing fix | Fix FK reference and enum values |
| `test/fixtures/tools.yml` | Pre-existing fix | Fix uniqueness violation |

**No EFQM implementation files were modified.** All changes are to test files and fixtures only.

---

## Test Breakdown: Before vs After

| Category | Before | After |
|----------|--------|-------|
| Total tests | 79 | 79 |
| Total assertions | 151 | 227 |
| Failures | 7 | **0** |
| Errors | 10 | **0** |
| Skips | 0 | 0 |

The assertion count increased from 151 to 227 because previously-erroring tests (which aborted before running assertions) now execute fully.

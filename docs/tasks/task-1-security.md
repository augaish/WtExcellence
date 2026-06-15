# Task 1: EFQM Scoring — Security Review Report

**Date:** 2026-04-15
**Reviewer:** Senior Security Engineer
**Branch:** `task-1-implement-efqm-scoring`
**Scope:** All files created or modified in the EFQM scoring feature

---

## Executive Summary

Two vulnerabilities were found and **fixed immediately**:

| # | Vulnerability | Severity | OWASP Category | Status |
|---|--------------|----------|---------------|--------|
| SEC-1 | IDOR: Arbitrary subcheckpoint ID injection in score/summary persistence | **High** | A01:2021 Broken Access Control | **FIXED** |
| SEC-2 | Missing company-scoped authorization on clause access | **Medium** | A01:2021 Broken Access Control | **FIXED** |
| SEC-3 | Missing server-side score range validation | **Low** | A03:2021 Injection | **FIXED** |

No XSS, CSRF, SQL injection, hardcoded secrets, or insecure dependency issues were found.

---

## Findings

### SEC-1: IDOR — Arbitrary Subcheckpoint ID in Score Persistence (HIGH)

**File:** `app/controllers/assessments_controller.rb`, methods `persist_scores` and `persist_summaries`

**Vulnerability:** The `subcheckpoint_id` in form params (`assessment[scores][<UUID>]` and `assessment[summaries][<UUID>]`) was passed directly to `find_or_create_container` without validating that the UUID belongs to a subcheckpoint within the tool linked to the current clause. An attacker could:

1. Craft a PATCH request with an arbitrary `subcheckpoint_id` (from a different tool)
2. `find_or_create_container` would create a `ToolClauseSubcheckpointAssignment` record linking `@tool_clause` to a foreign subcheckpoint
3. This pollutes the assignment table with cross-tool data, potentially corrupting score calculations for other clauses

**Before (vulnerable):**
```ruby
def persist_scores
  params[:assessment][:scores].each do |subcheckpoint_id, value|
    container = find_or_create_container(subcheckpoint_id)  # No validation
    container.update!(percentage_score: value.to_f)
  end
end
```

**Fix applied:** Added `valid_subcheckpoint_id?` method that checks the submitted ID against the pre-loaded set of subcheckpoint IDs belonging to the current tool. Invalid IDs are silently skipped.

```ruby
def valid_subcheckpoint_id?(subcheckpoint_id)
  @allowed_subcheckpoint_ids ||= @subcheckpoints.map { |s| s.id.to_s }.to_set
  @allowed_subcheckpoint_ids.include?(subcheckpoint_id.to_s)
end
```

Both `persist_scores` and `persist_summaries` now call `next unless valid_subcheckpoint_id?(subcheckpoint_id)` before any database write.

---

### SEC-2: Missing Company Authorization on Clause Access (MEDIUM)

**File:** `app/controllers/assessments_controller.rb`, method `set_clause`

**Vulnerability:** `Clause.find(params[:clause_id])` loaded any clause by ID globally, without verifying that the current user's company has an active `CompanyStandard` subscription for the clause's standard. This allowed:

1. Any authenticated user to access the assessment page for any clause in the system
2. Exposure of clause titles, checkpoint guidance text, and scoring configuration from other companies' standards

The write path (`update`) was safe because `company_id` on containers is set from `current_company`, but the read path leaked information.

**Before (vulnerable):**
```ruby
def set_clause
  @clause = Clause.find(params[:clause_id])  # No company scope
  @standard = @clause.standard_version&.standard
  # ...
end
```

**Fix applied:** Added company-standard authorization check, consistent with the existing pattern in `AssignmentsController#set_assignment` (lines 489-496):

```ruby
unless current_user&.super_admin? || current_user&.delegated_admin?
  unless current_company && @standard &&
         CompanyStandard.exists?(company_id: current_company.id, standard_id: @standard.id)
    redirect_back(fallback_location: root_path, alert: t("assessments.no_access"))
  end
end
```

Super admins and delegated admins are exempt (they have cross-company access by design).

---

### SEC-3: Missing Server-Side Score Range Validation (LOW)

**File:** `app/controllers/assessments_controller.rb`, method `persist_scores`

**Vulnerability:** Score values from user input were converted with `value.to_f` without range clamping. An attacker could submit `assessment[scores][<id>]=99999` or `assessment[scores][<id>]=-500`, bypassing the HTML `min="0" max="100"` attributes. While this doesn't cause direct harm (the `ClauseScoreCalculator` would just compute a wrong score), it corrupts data integrity.

**Before:**
```ruby
container.update!(percentage_score: value.to_f)
```

**Fix applied:**
```ruby
score = value.to_f.clamp(0, 100)
container.update!(percentage_score: score)
```

---

## Security Audit by Category

### 1. OWASP A01:2021 — Broken Access Control

| Check | Result | Details |
|-------|--------|---------|
| Authentication required | PASS | `AssessmentsController` inherits `Dashboard::BaseController` which inherits `ApplicationController`. `ApplicationController` has `before_action :authenticate_user!` (via Devise). |
| Viewer role enforcement | PASS | `update` action calls `prevent_viewer_action` as its first line. Viewers are blocked from all writes. |
| Company scoping on reads | **FIXED** | Added `CompanyStandard.exists?` check (SEC-2). |
| Company scoping on writes | PASS | All write operations use `company_id: current_company.id` — derived server-side, never from user input. |
| IDOR on subcheckpoint IDs | **FIXED** | Added `valid_subcheckpoint_id?` allowlist (SEC-1). |
| Status transition bypass | PASS | `apply_status_transition` uses `update_all` with `WHERE status IN (...)` — only valid transitions from known states. |
| Horizontal privilege escalation | PASS | A user from Company A cannot write scores for Company B because `current_company.id` is always used server-side. |

### 2. OWASP A02:2021 — Cryptographic Failures

| Check | Result | Details |
|-------|--------|---------|
| Sensitive data in transit | N/A | No new secrets, tokens, or PII introduced. Score data is business data, not PII. |
| Hardcoded secrets | PASS | No secrets, API keys, or credentials in any changed file. |
| Sensitive data in logs | PASS | No score data or user input is explicitly logged. `ActiveRecord::RecordInvalid` messages in flash are model validation errors, not raw user input. |

### 3. OWASP A03:2021 — Injection

| Check | Result | Details |
|-------|--------|---------|
| SQL injection | PASS | All database queries use ActiveRecord parameterized queries (`.where(key: value)`, `.find()`, `.find_or_create_by!()`). No raw SQL strings with user input interpolation. |
| XSS (stored) | PASS | The `summary` field (user text input) is rendered via `<%= current_summary %>` in ERB. Rails' default ERB escaping (`<%= %>`) auto-HTML-encodes output. The `<textarea>` value context also prevents injection. |
| XSS (reflected) | PASS | Error messages use `t()` (i18n lookups, not user input). Flash messages come from translations, not raw params. |
| XSS in data attributes | PASS | `weights_json` and `caps_json` are `to_json` on server-generated UUIDs and floats — no user-controllable content. ERB `<%= %>` escapes `"` to `&quot;` in attribute context. |
| XSS in tooltip | PASS | `sub.description_in` renders admin-configured content (not user input from the assessment form). It's output via `<%= %>` with auto-escaping. |
| Command injection | N/A | No shell commands, `system()`, or `exec()` calls. |

### 4. OWASP A04:2021 — Insecure Design

| Check | Result | Details |
|-------|--------|---------|
| CSRF protection | PASS | `form_with` generates a CSRF token automatically. `ApplicationController` inherits `protect_from_forgery` from Rails defaults. The PATCH route requires a valid authenticity token. |
| Mass assignment | PASS | The controller does not use `params.permit` for bulk assignment. It explicitly reads `params[:assessment][:scores]` and `params[:assessment][:summaries]` and sets fields individually. `ToolsController` uses strong params with an explicit whitelist for `:weight` and `:is_cap`. |
| Business logic bypass | PASS | Score calculation is backend-only (`ClauseScoreCalculator`). The Stimulus controller is a cosmetic preview — the server recomputes on save. An attacker manipulating client-side JS cannot affect stored scores. |

### 5. OWASP A05:2021 — Security Misconfiguration

| Check | Result | Details |
|-------|--------|---------|
| Debug mode in production | N/A | No debug flags or verbose error output added. |
| Default credentials | N/A | No new credentials introduced. |
| Overly permissive routes | PASS | Only `GET` and `PATCH` routes added — no `DELETE` or `POST` on the assessment endpoint. |

### 6. OWASP A06:2021 — Vulnerable and Outdated Components

| Check | Result | Details |
|-------|--------|---------|
| New dependencies | PASS | No new gems or npm packages added. The feature uses only existing dependencies (Stimulus, Rails, Tailwind). |
| Known vulnerabilities | N/A | No dependency version changes. |

### 7. OWASP A07:2021 — Identification and Authentication Failures

| Check | Result | Details |
|-------|--------|---------|
| Authentication bypass | PASS | Devise `authenticate_user!` is enforced globally. Confirmed unauthenticated requests redirect to sign-in (covered by test). |
| Session management | N/A | No changes to session handling. |

### 8. OWASP A08:2021 — Software and Data Integrity Failures

| Check | Result | Details |
|-------|--------|---------|
| Score tampering | PASS | Scores are clamped server-side (0-100). The canonical calculation is server-only. Client-side preview cannot affect persisted data. |
| Cache poisoning | PASS | `ClauseScorePropagator` is called after every save to update parent caches. The cache is invalidated on tool config changes via `invalidate_company_score_cache_for_tool_changes`. |

### 9. OWASP A09:2021 — Security Logging and Monitoring Failures

| Check | Result | Details |
|-------|--------|---------|
| Audit logging | NOTE | The spec calls for `AuditLogService` logging on score changes. The current implementation does not call `AuditLogService` in the `update` action. This is a **missing feature** (not a vulnerability) and should be added in a follow-up. The existing `set_current_user_for_activity_logging` in `Dashboard::BaseController` does set `Thread.current[:current_user]`, so model callbacks that use it will still fire. |

### 10. OWASP A10:2021 — Server-Side Request Forgery (SSRF)

| Check | Result | Details |
|-------|--------|---------|
| SSRF vectors | N/A | No outbound HTTP requests, URL fetching, or file inclusion based on user input. |

---

## Input Validation Summary

| Input | Source | Validation | Risk |
|-------|--------|-----------|------|
| `params[:clause_id]` | URL path | `Clause.find()` raises 404 if invalid UUID. Company check added. | Mitigated |
| `params[:assessment][:scores][id]` | Form hash key | Validated against tool's subcheckpoint IDs (allowlist). | Mitigated |
| `params[:assessment][:scores][id]` value | Form value | Clamped to 0-100 via `.to_f.clamp(0, 100)`. | Mitigated |
| `params[:assessment][:summaries][id]` | Form hash key | Validated against tool's subcheckpoint IDs (allowlist). | Mitigated |
| `params[:assessment][:summaries][id]` value | Form value | Truncated to 100 chars via `.to_s.truncate(100)`. HTML-escaped on output. | Safe |
| `params[:assessment][:commit]` | Form button | Compared against literal strings (`"submit_for_review"`, else fallback). | Safe |
| `tool[checkpoints_attributes][][subcheckpoints_attributes][][weight]` | Tool admin form | Model validates `0.0 <= weight <= 1.0`. Strong params whitelist. | Safe |
| `tool[checkpoints_attributes][][subcheckpoints_attributes][][is_cap]` | Tool admin form | Model validates boolean inclusion. Hidden field + checkbox pattern ensures `"0"` or `"1"`. | Safe |

---

## Files Reviewed

| File | Type | Security-Relevant Findings |
|------|------|--------------------------|
| `app/controllers/assessments_controller.rb` | Controller | SEC-1 (IDOR), SEC-2 (authz), SEC-3 (range) — all fixed |
| `app/views/assessments/show.html.erb` | View | No XSS — all output uses `<%= %>` auto-escaping |
| `app/views/assessments/_checkpoint_box.html.erb` | View | No XSS — `current_summary` auto-escaped in textarea |
| `app/views/assessments/_scoring_section.html.erb` | View | No XSS — JSON in data attributes safely escaped |
| `app/views/assessments/_status_badge.html.erb` | View | No injection — status from hardcoded strings |
| `app/javascript/controllers/scoring_calculator_controller.js` | JS | No DOM XSS — uses `textContent` (safe), not `innerHTML` |
| `app/javascript/controllers/char_counter_controller.js` | JS | No DOM XSS — uses `textContent` (safe) |
| `app/services/clause_score_calculator.rb` | Service | No injection — all DB queries parameterized |
| `app/models/tool_subcheckpoint.rb` | Model | Proper numeric validation on `weight` |
| `app/models/tool.rb` | Model | No security concerns |
| `app/controllers/tools_controller.rb` | Controller | Strong params correctly whitelist `:weight`, `:is_cap` |
| `app/views/tools/_form.html.erb` | View | No XSS — form inputs use Rails helpers |
| `config/routes.rb` | Routes | Only GET/PATCH — appropriate HTTP verbs |
| `config/locales/en.yml` | Config | No secrets or sensitive data |
| `db/migrate/20260415120000_...` | Migration | Safe schema change — non-null boolean with default |

---

## Recommendations (Non-blocking)

1. **Add audit logging to `AssessmentsController#update`** — Call `AuditLogService` to log score changes with old/new values for compliance audit trail.
2. **Rate limiting on the assessment update endpoint** — Not currently needed (form submission only), but if the endpoint is later exposed as an API, add throttling to prevent score-manipulation brute-force.

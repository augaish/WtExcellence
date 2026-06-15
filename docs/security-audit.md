# Security Audit — Way to Excellence

**Date:** 2026-02-23
**Scope:** Full application codebase (Rails 8.0.3 / PostgreSQL / Sidekiq 8 / Aliyun OSS)
**Type:** Defensive code review (no live penetration testing)

---

## Executive Summary

The application has a solid Rails foundation with Devise authentication, company-scoped role-based access control, and well-structured controller authorization. However, several critical and high-severity issues were identified — most notably an **arbitrary code execution vector** in a background job, a **hardcoded database password** committed to version control, an **SSRF-capable proxy endpoint**, and **publicly accessible cloud storage** for uploaded compliance documents. These must be addressed before any further production deployment.

**Findings by Severity:**

| Severity | Count |
|----------|-------|
| Critical | 2 |
| High | 8 |
| Medium | 8 |
| Low | 4 |
| Info | 3 |
| **Total** | **25** |

**Top 3 items requiring immediate attention:**

1. **Arbitrary code execution** — `eval(code)` in `KamalCronSmall` job accepts and runs arbitrary Ruby
2. **Hardcoded database password** in `config/database.yml`, committed to Git history
3. **Cloud storage set to `public: true`** — all uploaded compliance documents accessible without authentication

---

## Findings

### 1. Authentication & Authorization

#### F-01: Arbitrary Code Execution via Background Job

- **Severity:** Critical
- **Location:** `app/jobs/kamal_cron_small.rb:8-12`
- **Description:** The `KamalCronSmall` Sidekiq job calls `eval(code)` on its argument. Any process or user that can enqueue a Sidekiq job (via Redis access, admin panel, or SSRF) can execute arbitrary Ruby code with full application privileges.
- **Impact:** Complete system compromise — database exfiltration, file system access, lateral movement to other services, credential theft.
- **Vulnerable code:**
  ```ruby
  # app/jobs/kamal_cron_small.rb
  def perform(code)
    Rails.logger.info "Running KamalCronSmall #{code}"
    eval(code)  # <-- CRITICAL
  end
  ```
- **Recommendation:** Remove `eval` entirely. Replace with a dispatch pattern that maps string identifiers to pre-defined methods:
  ```ruby
  class KamalCronSmall
    include Sidekiq::Worker
    sidekiq_options queue: "cron_small"

    ALLOWED_TASKS = {
      "cleanup_temp_files" => :cleanup_temp_files,
      "sync_standards"     => :sync_standards,
      # add tasks here as needed
    }.freeze

    def perform(task_name)
      handler = ALLOWED_TASKS[task_name]
      raise ArgumentError, "Unknown task: #{task_name}" unless handler
      send(handler)
    end

    private

    def cleanup_temp_files
      # ...
    end

    def sync_standards
      # ...
    end
  end
  ```

---

#### F-02: No Account Lockout (Brute-Force Login)

- **Severity:** High
- **Location:** `config/initializers/devise.rb:193-211`, `app/models/user.rb:5`
- **Description:** Devise's `:lockable` module is not enabled. The entire lockable configuration block is commented out. There is no rate limiting on the login endpoint. An attacker can attempt unlimited password guesses.
- **Impact:** Credential stuffing and brute-force attacks against user accounts. Especially dangerous for admin accounts.
- **Recommendation:** Enable Devise lockable:
  ```ruby
  # app/models/user.rb
  devise :database_authenticatable, :rememberable, :validatable,
         :recoverable, :lockable

  # config/initializers/devise.rb
  config.lock_strategy = :failed_attempts
  config.unlock_strategy = :both
  config.maximum_attempts = 10
  config.unlock_in = 30.minutes
  config.last_attempt_warning = true
  ```
  Generate and run the migration to add the required columns (`failed_attempts`, `unlock_token`, `locked_at`) to the `users` table.

---

#### F-03: No Multi-Factor Authentication (MFA)

- **Severity:** Medium
- **Location:** `app/models/user.rb:5`, `config/initializers/devise.rb`
- **Description:** No second authentication factor is available. All access — including super_admin and delegated_admin — relies solely on email/password.
- **Impact:** A single compromised password gives full account access. For admin accounts, this means full platform access.
- **Recommendation:** Add TOTP-based MFA via `devise-two-factor` gem. At minimum, require MFA for super_admin and delegated_admin roles.

---

#### F-04: Weak Minimum Password Length

- **Severity:** Medium
- **Location:** `config/initializers/devise.rb:181`
- **Description:** `config.password_length = 6..128` allows 6-character passwords. The invitation acceptance flow independently enforces 8 characters (`user_invitations_controller.rb:48`), creating an inconsistency — users who reset their password can set a weaker password than new invitees.
- **Impact:** Weak passwords are more susceptible to brute-force attacks.
- **Recommendation:** Set `config.password_length = 12..128` in devise.rb. Remove the separate validation in the invitation controller to maintain a single source of truth.

---

#### F-05: Session Cookie Not Explicitly Secured

- **Severity:** Medium
- **Location:** `config/initializers/devise.rb:177`, `config/environments/production.rb:34`
- **Description:** `config.rememberable_options = {}` is commented out. Combined with `force_ssl` being disabled (F-13), the remember-me cookie may be transmitted over plain HTTP. No explicit `secure: true`, `httponly: true`, or `SameSite` configuration found for session cookies.
- **Impact:** Session hijacking via network sniffing if any HTTP traffic is allowed.
- **Recommendation:**
  ```ruby
  # config/initializers/devise.rb
  config.rememberable_options = { secure: true, httponly: true, same_site: :lax }
  ```

---

#### F-06: No Session Timeout

- **Severity:** Low
- **Location:** `config/initializers/devise.rb:191`
- **Description:** Devise `:timeoutable` is not enabled. `config.timeout_in` is commented out. Sessions remain active indefinitely.
- **Impact:** Abandoned sessions on shared devices remain authenticated. Higher risk in compliance/audit software where data sensitivity is high.
- **Recommendation:** Enable `:timeoutable` with a 30-minute timeout, or a value appropriate for the user base.

---

### 2. Input Validation & Injection

#### F-07: Server-Side Request Forgery (SSRF) via Ollama Proxy

- **Severity:** High
- **Location:** `app/controllers/ollama_proxy_controller.rb:16-18`
- **Description:** The proxy endpoint takes `params[:path]` and appends it directly to the Ollama base URL to construct an HTTP request target. While token-authenticated, the path is not validated or restricted. An attacker with a valid proxy token could request internal network resources, cloud metadata endpoints (e.g., `169.254.169.254`), or other internal services.
- **Impact:** Internal network reconnaissance, cloud credential theft (via metadata service), access to internal APIs.
- **Vulnerable code:**
  ```ruby
  path = "/#{params[:path]}"
  path += "?#{request.query_string}" if request.query_string.present?
  uri = URI("#{base}#{path}")
  http = Net::HTTP.new(uri.host, uri.port)  # host comes from ENV, but path controls the full URL
  ```
- **Recommendation:** Restrict `params[:path]` to a known whitelist of Ollama API paths:
  ```ruby
  ALLOWED_PATHS = %w[api/generate api/chat api/tags api/show].freeze

  def forward
    unless valid_proxy_token?
      head :unauthorized
      return
    end

    unless ALLOWED_PATHS.include?(params[:path])
      head :not_found
      return
    end
    # ... rest of the method
  end
  ```

---

#### F-08: Shell Command Execution with Backticks

- **Severity:** High
- **Location:** `app/services/standard_ingestion_service.rb:66,132,157-160`
- **Description:** Three separate shell execution points:
  1. `system("pdftoppm -png -r 300 #{pdf_path} #{output_prefix}")` (line 66) — paths are escaped via `Shellwords.escape`
  2. `` `tesseract --list-langs 2>&1` `` (line 132) — hardcoded command, safe
  3. `` `#{cmd}` `` (line 160) where `cmd` includes `lang_string` (line 145) built from `tesseract --list-langs` output — not validated against a whitelist

  While file paths are escaped with `Shellwords.escape`, the `lang_string` is assembled by joining values from `tesseract --list-langs` output. If Tesseract were compromised or the output manipulated, injection is possible.
- **Impact:** Remote code execution via command injection.
- **Vulnerable code:**
  ```ruby
  lang_string = languages.join("+")  # line 145
  cmd = "tesseract #{escaped_image_path} #{escaped_output} -l #{lang_string} --psm 6 --oem 3 2>&1"
  result = `#{cmd}`  # line 160
  ```
- **Recommendation:** Use `Open3.capture2e` instead of backticks, and validate languages against a hardcoded whitelist:
  ```ruby
  ALLOWED_LANGS = %w[eng ara ara_script].freeze

  languages = languages.select { |l| ALLOWED_LANGS.include?(l) }
  lang_string = languages.join("+")

  stdout_stderr, status = Open3.capture2e(
    "tesseract", image_path, output_file,
    "-l", lang_string, "--psm", "6", "--oem", "3"
  )
  ```

---

#### F-09: Pervasive innerHTML Usage in JavaScript Controllers

- **Severity:** High
- **Location:** 20+ Stimulus controllers including:
  - `app/javascript/controllers/toast_controller.js:84`
  - `app/javascript/controllers/modal_controller.js:555,566,717`
  - `app/javascript/controllers/capa_link_clauses_search_controller.js:91,145,167,259`
  - `app/javascript/controllers/drag_drop_upload_controller.js:228,256`
  - `app/javascript/controllers/standards_controller.js:39`
- **Description:** Server-rendered HTML is injected into the DOM using `innerHTML` throughout the frontend. While the HTML originates from the server (and is therefore trusted in the current flow), this pattern is dangerous because:
  1. Any stored XSS in the database (e.g., CAPA titles, document names, notification text) renders and executes immediately
  2. No Content Security Policy exists to block inline script execution (see F-14)
- **Impact:** If any user-controlled string reaches the database unsanitized (even via an admin panel or API), it executes as JavaScript for every user who views it.
- **Recommendation:**
  - Short term: Enable CSP (F-14) to block inline script execution
  - Medium term: Replace `innerHTML` with safe DOM manipulation methods (`textContent`, `insertAdjacentHTML` with sanitized input), or use Turbo Streams for server-driven DOM updates
  - One controller already demonstrates good practice: `capa_link_clauses_search_controller.js:336-340` implements `escapeHtml()` — this pattern should be applied globally

---

#### F-10: CDN Scripts Without Subresource Integrity (SRI)

- **Severity:** Medium
- **Location:** `app/views/layouts/dashboard.html.erb:25,32`
- **Description:** Chart.js and Select2 are loaded from `cdn.jsdelivr.net` without `integrity` attributes:
  ```html
  <link href="https://cdn.jsdelivr.net/npm/select2@4.0.13/dist/css/select2.min.css" rel="stylesheet" />
  <script src="https://cdn.jsdelivr.net/npm/chart.js@3.9.1/dist/chart.min.js"></script>
  ```
- **Impact:** If the CDN is compromised, malicious JavaScript executes in every user's browser with full application context (cookies, CSRF tokens, DOM access).
- **Recommendation:** Add `integrity` and `crossorigin` attributes:
  ```html
  <script src="https://cdn.jsdelivr.net/npm/chart.js@3.9.1/dist/chart.min.js"
          integrity="sha384-<hash>"
          crossorigin="anonymous"></script>
  ```
  Alternatively, vendor these libraries locally via importmap to eliminate CDN dependency entirely.

---

#### F-11: html_safe on User-Influenced Content

- **Severity:** Low
- **Location:** `app/views/assignments/show.html.erb:1044`
- **Description:** A translated string with interpolated clause code is marked `html_safe`:
  ```erb
  <%= t('assignments.show.allocated_points_for', code: @clause.code, pts: @clause.calculated_points.round(2)).html_safe %>
  ```
  The `@clause.code` value comes from the database. If an admin sets a clause code containing HTML/JS, it renders unsanitized.
- **Impact:** Stored XSS if clause codes are user-editable.
- **Recommendation:** Remove `.html_safe` and use `sanitize` or the `%{code}` interpolation with proper escaping. If HTML formatting is needed in the translation, use `_html` suffix convention (`allocated_points_for_html`) which auto-escapes interpolated values.

---

### 3. Data Protection & Secrets

#### F-12: Hardcoded Database Password in Version Control

- **Severity:** Critical
- **Location:** `config/database.yml:28,64`
- **Description:** Development and test database credentials are hardcoded in plaintext:
  ```yaml
  development:
    username: postgres
    password: Patrick242004
  test:
    username: postgres
    password: Patrick242004
  ```
  This file is committed to Git. The password is now in the repository history permanently.
- **Impact:** Anyone with repository access (current and former team members, CI systems, backup services) has the database password. If this password is reused elsewhere, those systems are also compromised.
- **Recommendation:**
  1. Immediately rotate this password on all systems where it may be reused
  2. Move development credentials to environment variables or `.env` (already have `dotenv-rails`):
     ```yaml
     development:
       <<: *default
       database: way_to_excellence_development
       username: <%= ENV.fetch("DEV_DB_USER", "postgres") %>
       password: <%= ENV.fetch("DEV_DB_PASSWORD", "") %>
     ```
  3. Consider using `git filter-repo` or BFG Repo-Cleaner to remove the password from Git history
  4. Add `config/database.yml` to `.gitignore` and use `config/database.yml.example` as a template

---

#### F-13: Cloud Storage Set to Public Access

- **Severity:** High
- **Location:** `config/storage.yml:16`
- **Description:** The Aliyun OSS storage bucket is configured with `public: true`:
  ```yaml
  aliyun:
    service: Aliyun
    access_key_id: <%= ENV["ALIYUN_ACCESS_KEY_ID"] %>
    access_key_secret: <%= ENV["ALIYUN_ACCESS_KEY_SECRET"] %>
    bucket: <%= ENV["ALIYUN_BUCKET"] %>
    endpoint: <%= ENV["ALIYUN_ENDPOINT"] %>
    region: <%= ENV["ALIYUN_REGION"] %>
    public: true
  ```
  This means every uploaded file (compliance documents, evidence attachments, internal quality reports) is accessible to anyone with the direct URL.
- **Impact:** Confidential compliance and quality management documents are exposed. Direct URLs to blobs can be enumerated or leaked via logs/referrer headers.
- **Recommendation:** Set `public: false` and use signed, time-limited URLs for file access:
  ```yaml
  aliyun:
    service: Aliyun
    # ... credentials ...
    public: false
  ```
  Update file download logic to use `rails_blob_url` with `disposition: :attachment` and signed URLs. Ensure the application's `visible_to_user?` check gates all file access.

---

#### F-14: Server IPs Committed to Repository

- **Severity:** Medium
- **Location:** `config/deploy.yml`, `config/deploy.stage.yml`
- **Description:** Production (`8.213.80.159`) and staging (`8.213.42.254`) server IP addresses are committed in deployment configuration. Ollama server IP (`8.213.84.103`) appears in comments.
- **Impact:** Simplifies reconnaissance for attackers. Combined with other vulnerabilities, provides direct targets.
- **Recommendation:** Move server addresses to environment variables or a secrets manager. Use `.env` files excluded from Git for deployment config.

---

#### F-15: Audit Logs Contain Unmasked Sensitive Data

- **Severity:** Low
- **Location:** `app/services/audit_log_service.rb:21-28`
- **Description:** The `payload_json` column stores document names, CAPA titles, user actions, and file names in plain text. No data masking or encryption applied.
- **Impact:** If audit logs are accessed by unauthorized users (via SQL injection, backup leak, or over-broad admin access), sensitive business data is exposed.
- **Recommendation:** Implement field-level encryption for `payload_json` using `ActiveRecord::Encryption` (built into Rails 7+), or apply a masking policy to sensitive fields before logging.

---

### 4. Infrastructure & Configuration

#### F-16: Content Security Policy Entirely Disabled

- **Severity:** High
- **Location:** `config/initializers/content_security_policy.rb` (all 25 lines commented out)
- **Description:** No CSP headers are sent with any response. This removes the primary browser-side defense against XSS attacks.
- **Impact:** Any XSS vulnerability (stored or reflected) can execute arbitrary JavaScript, steal session cookies, redirect users, or exfiltrate data without browser restriction.
- **Recommendation:** Enable CSP with a strict policy:
  ```ruby
  Rails.application.configure do
    config.content_security_policy do |policy|
      policy.default_src :self
      policy.font_src    :self, "https://fonts.gstatic.com"
      policy.img_src     :self, :data, :https
      policy.object_src  :none
      policy.script_src  :self, "https://cdn.jsdelivr.net"
      policy.style_src   :self, :unsafe_inline, "https://fonts.googleapis.com", "https://cdn.jsdelivr.net"
      policy.connect_src :self
      policy.frame_src   :none
    end

    config.content_security_policy_nonce_generator = ->(request) { request.session.id.to_s }
    config.content_security_policy_nonce_directives = %w[script-src]
  end
  ```
  Deploy in `report-only` mode first, then enforce after confirming no breakage.

---

#### F-17: force_ssl Disabled in Production

- **Severity:** High
- **Location:** `config/environments/production.rb:34`
- **Description:** `config.force_ssl = true` is commented out. While `config.assume_ssl = true` (line 31) tells Rails to treat incoming requests as HTTPS (for URL generation), it does **not**:
  - Redirect HTTP requests to HTTPS
  - Set the `Strict-Transport-Security` (HSTS) header
  - Mark cookies as `Secure`
- **Impact:** If any HTTP traffic reaches the application (misconfigured load balancer, direct IP access, development oversight), sessions and credentials are transmitted in plaintext.
- **Recommendation:** Uncomment `config.force_ssl = true` and configure the health check exclusion:
  ```ruby
  config.force_ssl = true
  config.ssl_options = { redirect: { exclude: ->(request) { request.path == "/up" } } }
  ```

---

#### F-18: Host Header Protection Disabled

- **Severity:** High
- **Location:** `config/environments/production.rb:97-103`
- **Description:** `config.hosts` is commented out. The application responds to requests with any `Host` header, enabling DNS rebinding attacks and cache poisoning.
- **Impact:** An attacker can trick the application into generating URLs with a malicious host (password reset emails, redirects), or use DNS rebinding to access the app from a malicious domain.
- **Recommendation:**
  ```ruby
  config.hosts = [
    "app.wtexcellence.com",
    "test.wtexcellence.com",
    "www.wtexcellence.com",
    "wtexcellence.com"
  ]
  config.host_authorization = { exclude: ->(request) { request.path == "/up" } }
  ```

---

#### F-19: No Rate Limiting

- **Severity:** Medium
- **Location:** Application-wide (no `rack-attack` or equivalent middleware found)
- **Description:** No rate limiting exists on any endpoint: login, password reset, file upload, API, invitation acceptance, or the Ollama proxy. The Gemfile does not include `rack-attack` or any throttling middleware.
- **Impact:** Enables brute-force attacks (login, invitation tokens), denial-of-service via file upload flood, and API abuse.
- **Recommendation:** Add `rack-attack` and configure throttles:
  ```ruby
  # Gemfile
  gem "rack-attack"

  # config/initializers/rack_attack.rb
  Rack::Attack.throttle("logins/ip", limit: 10, period: 60.seconds) do |req|
    req.ip if req.path == "/users/sign_in" && req.post?
  end

  Rack::Attack.throttle("uploads/user", limit: 20, period: 60.seconds) do |req|
    req.env["warden"].user&.id if req.path == "/uploads" && req.post?
  end

  Rack::Attack.throttle("password_resets/ip", limit: 5, period: 60.seconds) do |req|
    req.ip if req.path == "/users/password" && req.post?
  end
  ```

---

#### F-20: SMTP Authentication Without TLS Enforcement

- **Severity:** Medium
- **Location:** `config/environments/production.rb:65-72`
- **Description:** SMTP configured with `authentication: :plain` but no explicit TLS setting:
  ```ruby
  ActionMailer::Base.smtp_settings = {
    port: ENV["SMTP_PORT"],
    address: ENV["SMTP_SERVER"],
    user_name: ENV["SMTP_LOGIN"],
    password: ENV["SMTP_PASSWORD"],
    domain: ENV["SMTP_DOMAIN"],
    authentication: :plain
  }
  ```
  Rails defaults `enable_starttls_auto` to `true`, so STARTTLS is likely attempted. However, this is opportunistic — if the server doesn't advertise STARTTLS, credentials are sent in plaintext.
- **Impact:** SMTP credentials transmitted in cleartext if STARTTLS negotiation fails.
- **Recommendation:** Explicitly enforce TLS:
  ```ruby
  ActionMailer::Base.smtp_settings = {
    # ... existing settings ...
    authentication: :plain,
    enable_starttls_auto: true,
    openssl_verify_mode: OpenSSL::SSL::VERIFY_PEER
  }
  ```

---

#### F-21: Sentry Tracing at 100% Sample Rate

- **Severity:** Low
- **Location:** `config/initializers/sentry.rb:6`
- **Description:** `config.traces_sample_rate = 1.0` — every single request is traced and sent to Sentry.
- **Impact:** Performance overhead on every request. Potential data exposure in Sentry's cloud dashboard (request bodies, headers, user data). Increased costs.
- **Recommendation:** Reduce to 10-20% in production:
  ```ruby
  config.traces_sample_rate = ENV.fetch("SENTRY_TRACES_SAMPLE_RATE", 0.1).to_f
  ```

---

#### F-22: No File Upload Size Limits

- **Severity:** Medium
- **Location:** `app/controllers/uploads_controller.rb:13-170`, `app/models/upload.rb`
- **Description:** While `Upload` validates `size_bytes` is present and greater than 0 (line 9), there is no **maximum** file size validation at the model or controller level. No Nginx/reverse proxy upload size limit was found in the codebase.
- **Impact:** Denial-of-service via large file uploads exhausting disk space, memory, or bandwidth.
- **Recommendation:** Add model-level validation and consider a web server limit:
  ```ruby
  # app/models/upload.rb
  validates :size_bytes, presence: true,
            numericality: { greater_than: 0, less_than_or_equal_to: 50.megabytes }
  ```

---

### 5. Business Logic & Application

#### F-23: Race Condition in CAPA Status Synchronization

- **Severity:** High
- **Location:** `app/models/capa.rb:57-67`
- **Description:** `sync_status_with_assignments` reads `capa_assignments.exists?` and then calls `update_column(:status, ...)` without any database lock. Two concurrent requests (e.g., one creating an assignment, one deleting) can interleave and leave the status inconsistent.
- **Impact:** CAPA records show incorrect status (e.g., "open" when assignments exist, or "assigned" when none do). In a compliance/audit platform, incorrect status creates regulatory risk.
- **Vulnerable code:**
  ```ruby
  def sync_status_with_assignments
    return unless persisted?
    has_assignments = capa_assignments.exists?     # read
    if has_assignments && open?
      update_column(:status, :assigned)            # write — no lock between read and write
    elsif !has_assignments && assigned?
      update_column(:status, :open)
    end
  end
  ```
- **Recommendation:** Use pessimistic locking:
  ```ruby
  def sync_status_with_assignments
    return unless persisted?

    with_lock do
      has_assignments = capa_assignments.exists?
      if has_assignments && open?
        update_column(:status, :assigned)
      elsif !has_assignments && assigned?
        update_column(:status, :open)
      end
    end
  end
  ```

---

#### F-24: Race Condition in Ingestion Job State Machine

- **Severity:** High
- **Location:** `app/models/ingestion_job.rb:36-57`, `app/jobs/process_ingestion_job.rb`
- **Description:** State transitions (`queued` → `processing` → `completed`/`failed`) use unconditional `update!` calls. No guard clause checks the current state before transitioning. If a job is picked up twice (Sidekiq retry, duplicate enqueue), both workers will process it.
- **Impact:** Duplicate processing of ingestion jobs — wasted AI API credits, potential data corruption if partial results overwrite complete ones.
- **Vulnerable code:**
  ```ruby
  def start_processing!
    update!(status: "processing", started_at: Time.current)  # no check: "only if status == queued"
  end
  ```
- **Recommendation:** Use conditional updates:
  ```ruby
  def start_processing!
    rows = self.class.where(id: id, status: "queued")
               .update_all(status: "processing", started_at: Time.current)
    raise "Job #{id} already processing or completed" if rows == 0
    reload
  end
  ```

---

#### F-25: Optional company_id on Tenant-Critical Models

- **Severity:** Medium
- **Location:** `app/models/upload.rb:17`, `app/models/capa.rb` (line 2, via `belongs_to :company, optional: true`)
- **Description:** `Upload`, `Capa`, and `Folder` all have `belongs_to :company, optional: true`. This means records can exist without a company association. The `Upload` model even has a TODO comment (line 13-14): `# TODO: Make company_id required after backfilling existing records`.
- **Impact:** Records without `company_id` bypass tenant-scoped queries (e.g., `where(company_id: company.id)` won't match `NULL`). This could result in orphaned data visible to the wrong company, or invisible to all companies.
- **Recommendation:** Complete the backfill of `company_id` for existing records, then make the association required:
  ```ruby
  belongs_to :company  # remove optional: true
  validates :company_id, presence: true
  ```

---

#### F-26: Thread.current[:current_user] for Audit Context

- **Severity:** Low
- **Location:** `app/controllers/dashboard/base_controller.rb:114-127`
- **Description:** User context for model-level audit logging is stored in `Thread.current[:current_user]`. While cleaned up in an `after_action` callback (line 125-127), this pattern is fragile in threaded servers — if the `after_action` is skipped (exception in middleware, timeout), the thread-local leaks to the next request on the same thread.
- **Impact:** Audit logs could attribute actions to the wrong user. Low probability but high impact for compliance accuracy.
- **Recommendation:** Use `ActiveSupport::CurrentAttributes` instead, which is automatically reset between requests:
  ```ruby
  # app/models/current.rb
  class Current < ActiveSupport::CurrentAttributes
    attribute :user
  end

  # app/controllers/dashboard/base_controller.rb
  before_action -> { Current.user = current_user }
  ```

---

#### F-27: Temporary Files Written to Predictable Paths Without Encryption

- **Severity:** Low
- **Location:** `app/jobs/process_ingestion_job.rb:92-96`, `app/services/standard_ingestion_service.rb:96-97`
- **Description:** Extracted PDF text and LLM responses are written to predictable paths under `tmp/`:
  ```ruby
  output_path = Rails.root.join("tmp", "ollama_responses", "t4_optimized",
    "standard_t4_#{standard.code.downcase}_#{timestamp}.json")
  ```
  These files contain potentially confidential document content and are not encrypted.
- **Impact:** Information disclosure if the server's `/tmp` directory is readable by other processes or users.
- **Recommendation:** Use `Dir.mktmpdir` with cleanup blocks, and ensure tmp files are deleted after use. For debugging, store outputs in the database or encrypted storage rather than the filesystem.

---

### 6. Dependencies & Supply Chain

#### F-28: Dependency Versions — Current Assessment

- **Severity:** Info
- **Location:** `Gemfile`, `Gemfile.lock`
- **Description:** Key dependency versions as of this audit:
  - Rails 8.0.3 — current
  - Devise 4.9.4 — current
  - Sidekiq 8.0.8 — current
  - Puma 7.1.0 — current
  - pg 1.6.2 — current
  - Sentry 6.3.1 — current
  - pdf-reader 2.15.0 — current

  No known CVEs were identified for the current versions during this review. Brakeman (7.1.1) is included in dev/test for static analysis.
- **Recommendation:** Set up automated dependency scanning (e.g., `bundle audit` in CI, Dependabot, or Snyk) to catch future vulnerabilities. Run `bundle audit` regularly.

---

## Areas Reviewed — No Issues Found

### Strong Parameter Usage
- **What was checked:** All controller actions across `UploadsController`, `EvidenceAttachmentsController`, `CapaManagementController`, `GeneralSettingsController`, `UserInvitationsController`, and API controllers.
- **Why it's acceptable:** Every controller uses `params.require().permit()` for mass assignment protection. No instances of `params.permit!` or unfiltered parameter access were found.

### CSRF Protection
- **What was checked:** `ApplicationController` inherits from `ActionController::Base` (includes `protect_from_forgery`). All views include `<%= csrf_meta_tags %>`. The Ollama proxy endpoint correctly uses `skip_before_action :verify_authenticity_token` implicitly (via API-style rendering) combined with its own token authentication.
- **Why it's acceptable:** Rails' default CSRF protection is active for all browser-facing endpoints. API endpoints use separate token authentication.

### SQL Injection
- **What was checked:** All ActiveRecord queries across controllers, models, and scopes. Searched for raw SQL, `Arel.sql`, string interpolation in queries.
- **Why it's acceptable:** All queries use parameterized ActiveRecord methods. The few uses of `Arel.sql()` contain only static strings (date grouping expressions). The raw SQL in `capa_visible_scope` (base_controller.rb:72) uses parameterized placeholders (`?`).

### Password Storage
- **What was checked:** Devise configuration, User model, BCrypt settings.
- **Why it's acceptable:** Passwords are hashed with BCrypt using 12 stretches (`devise.rb:40`). No plaintext password storage. Password reset tokens are properly generated and expired.

### Invitation Token Security
- **What was checked:** `User.generate_invitation_token` in `user.rb:202`, invitation acceptance flow in `user_invitations_controller.rb`.
- **Why it's acceptable:** Tokens generated with `SecureRandom.urlsafe_base64(32)` (256 bits of entropy). Tokens expire after 7 days. Tokens are cleared after acceptance. Token lookup uses constant-time comparison via Devise internals.

### Credit System Transaction Safety
- **What was checked:** `CreditService` (`app/services/credit_service.rb:40-56,67-80`).
- **Why it's acceptable:** Credit deductions use `Company.transaction` with pessimistic locking (`company.lock!`, `company_user.lock!`). Proper error handling prevents negative balances. This is well-implemented.

### Role-Based CAPA Visibility
- **What was checked:** `capa_visible_scope` in `dashboard/base_controller.rb:46-79`.
- **Why it's acceptable:** CAPA visibility is properly scoped by role — contributors see only assigned CAPAs, auditors see assigned + created, admins/QMs see all company CAPAs. Super admins see everything. Uses parameterized queries for user ID filtering.

### Upload Visibility Controls
- **What was checked:** `Upload.visible_to_user` scope (`upload.rb:34-62`), `visible_to_user?` instance method (`upload.rb:101-115`), `UploadsController`, `EvidenceAttachmentsController`.
- **Why it's acceptable:** Public/private distinction is enforced at query level. Private uploads are only visible to the uploader or company admins. Cross-company upload prevention is explicitly coded in the uploads controller (lines 37-54).

### Parameter Filtering in Logs
- **What was checked:** `config/initializers/filter_parameter_logging.rb`.
- **Why it's acceptable:** Filters cover `:passw`, `:email`, `:secret`, `:token`, `:_key`, `:crypt`, `:salt`, `:certificate`, `:otp`, `:ssn`, `:cvv`, `:cvc`. The substring matching catches `password`, `invitation_token`, `reset_password_token`, `api_key`, etc.

### Viewer Role Enforcement
- **What was checked:** `prevent_viewer_action` in `dashboard/base_controller.rb:87-104`, all mutation endpoints in CAPA management, uploads, settings.
- **Why it's acceptable:** Viewer role is consistently checked via `before_action :prevent_viewer_action` on all state-changing actions. Returns 403 for both HTML and JSON requests.

### Soft Delete Implementation
- **What was checked:** `User` model `deleted_at` column, `UserDeletionService`.
- **Why it's acceptable:** User deletion uses soft delete with transaction-based cleanup of associated records. Deleted users cannot authenticate (`active_for_authentication?` checks `is_active?`).

---

## Recommendations Summary

### Immediate (fix before next deployment)

| # | Finding | Action |
|---|---------|--------|
| F-01 | `eval()` in KamalCronSmall | Replace with dispatch table of named tasks |
| F-12 | Hardcoded DB password in Git | Rotate password, move to env vars, scrub Git history |
| F-13 | Public cloud storage | Set `public: false`, use signed URLs |
| F-17 | `force_ssl` disabled | Uncomment `config.force_ssl = true` |

### Short term (within 1-2 sprints)

| # | Finding | Action |
|---|---------|--------|
| F-02 | No account lockout | Enable Devise `:lockable`, add migration |
| F-07 | SSRF via Ollama proxy | Whitelist allowed API paths |
| F-08 | Shell execution with backticks | Switch to `Open3.capture2e`, validate language whitelist |
| F-16 | CSP disabled | Enable CSP in report-only mode, then enforce |
| F-18 | Host header unprotected | Configure `config.hosts` |
| F-19 | No rate limiting | Add `rack-attack` with login/upload/API throttles |
| F-23 | CAPA status race condition | Add pessimistic locking |
| F-24 | Ingestion job race condition | Use conditional state transitions |

### Medium term (within 1-2 months)

| # | Finding | Action |
|---|---------|--------|
| F-03 | No MFA | Add `devise-two-factor` for admin roles |
| F-04 | Weak password minimum | Increase to 12 characters |
| F-05 | Session cookie not secured | Configure `rememberable_options` |
| F-09 | innerHTML usage | Migrate to safe DOM methods / Turbo Streams |
| F-10 | CDN scripts without SRI | Add integrity hashes or vendor locally |
| F-14 | Server IPs in repo | Move to env vars |
| F-20 | SMTP without TLS enforcement | Add explicit TLS config |
| F-22 | No upload size limits | Add max size validation |
| F-25 | Optional company_id | Backfill and make required |

### Longer term / ongoing

| # | Finding | Action |
|---|---------|--------|
| F-06 | No session timeout | Enable Devise `:timeoutable` |
| F-11 | html_safe usage | Remove or use `_html` i18n convention |
| F-15 | Unmasked audit logs | Encrypt `payload_json` column |
| F-21 | Sentry 100% sample rate | Reduce to 10-20% |
| F-26 | Thread-local user context | Migrate to `ActiveSupport::CurrentAttributes` |
| F-27 | Temp files unencrypted | Use `Dir.mktmpdir` with cleanup, or store in DB |
| F-28 | Dependency monitoring | Set up `bundle audit` in CI, enable Dependabot |

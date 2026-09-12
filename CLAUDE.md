# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Way to Excellence — a Ruby on Rails 8 SaaS platform for Quality Management System (QMS) and CAPA (Corrective/Preventive Action) management. Features AI/LLM integration for document processing, questionnaire generation, and compliance analysis. Multi-tenant, bilingual (English/Arabic with RTL support).

## Development Commands

```bash
# Start all dev processes (web server, Tailwind watcher, Sidekiq)
bin/dev

# Individual processes
bin/rails server              # Puma on port 3000
bin/rails tailwindcss:watch   # Tailwind CSS compilation
bin/sidekiq                   # Background job processor

# Database
bin/rails db:migrate
bin/rails db:seed

# Linting
bundle exec rubocop
bundle exec rubocop -a        # Auto-fix

# Assets
bundle exec rails assets:precompile
bundle exec rails tailwindcss:build

# Console
bin/rails console
```

## Architecture

### Backend Stack
- **Rails 8.0.2** with PostgreSQL 17, Ruby 3.4.5
- **Hotwire** (Turbo + Stimulus) for frontend interactivity — no SPA framework
- **Importmap** for JS (no npm build step)
- **Tailwind CSS v4.1** via `tailwindcss-rails` gem
- **Devise** for authentication (email/password)
- **Sidekiq** + Redis for background jobs; `sidekiq-cron` for scheduled tasks
- **Solid Cache/Queue/Cable** — Rails' Solid suite for cache, queue fallback, and WebSockets

### Multi-Tenancy & Authorization
Users belong to a single company via `company_users` join table. Roles are hierarchical:
- `super_admin` (platform-wide)
- `company_admin`, `company_quality_manager`, `company_viewer` (company-level)
- `delegated_admin`

Current user is set in `Thread.current[:current_user]` for audit logging.

### Service Layer
Business logic lives in `app/services/` (25+ services). Key patterns:
- **LLM Services**: `CapaQuestionnaireService`, `CapaActionGenerationService`, `CapaClauseSuggestionService` — support both OpenRouter (Claude) and Ollama (local) providers, controlled by `CAPA_*_PROVIDER` env vars
- **PDF Pipeline**: `StandardIngestionService` / `MultiStagePdfPipeline` — OCR (Tesseract) → text extraction (Tika) → LLM parsing to extract standards/clauses
- **Audit**: `AuditLogService` for compliance trail
- **Credits**: `CreditService` tracks AI usage per company

### Key Domain Models
- `Capa` — core entity with friendly_id (e.g., CAPA-1-2025-03-28), status enum (open/assigned/in_progress/closed), priority enum, soft-deletes via `deleted_at`
- `Standard` / `Clause` — compliance standards ingested from PDFs
- `Company` / `CompanyUser` / `User` — multi-tenant user management
- `ChecklistItem` — QMS checklist data

### Routing Namespaces
- `/dashboard/*` — main app interface (13 controllers)
- `/library/*` — standards/clauses library
- `/standards/*` — standards management
- `/tools/*` — QMS tools
- `/api/*` — JSON API endpoints (4 controllers)

### I18n
Locales: `en` (default), `ar` (Arabic with RTL). Locale detected from URL param → session → Accept-Language header. Timezone: Asia/Riyadh.

### File Storage
Active Storage with Aliyun OSS in production, local disk in development.

## Deployment

Deployed via **Kamal** (Docker-based) to `app.wtexcel.com` (destination `wtexcel`, config `config/deploy.wtexcel.yml`, run by `scripts/server_deploy.sh`). `config/deploy.yml` is the old wtexcellence.com destination. Docker image includes Tesseract OCR (en+ar), Poppler, and Apache Tika for PDF processing.

## LLM Configuration

Primary provider: **OpenRouter** (default model: `anthropic/claude-sonnet-4.5`). Per-task provider selection via env vars:
- `CAPA_ACTION_PROVIDER`, `CAPA_CLAUSE_PROVIDER`, `CAPA_QUESTIONNAIRE_PROVIDER` — set to `ollama` or `openrouter`
- Each has corresponding `CAPA_*_OLLAMA_MODEL` for local inference

## Outbound Data Flows

External services that receive data from this app — review before adding new ones:
- **OpenRouter / Ollama**: full CAPA text, descriptions, standards/clauses, questionnaire answers, and extracted PDF text (`app/services/capa_*_service.rb`, `multi_stage_pdf_pipeline.rb`, `ollama_client.rb`)
- **Aliyun OSS**: all uploaded files/documents (`config/storage.yml`)
- **Sentry**: error traces and request context, 100% sample rate (`config/initializers/sentry.rb`)
- **MailerSend SMTP**: notification/invitation emails (`app/mailers/`)

## Code Conventions

- **Controllers**: thin; inherit `Dashboard::BaseController` or `ApplicationController`; use `respond_to` for html/json; status via symbols (`:forbidden`, `:unprocessable_entity`, `:not_found`)
- **Models**: explicit `class_name:`/`foreign_key:` on associations; Rails 7 hash-enum syntax (`enum :status, { open: "Open" }`); lambda scopes; soft-delete via `deleted_at`; audit context via `Thread.current[:current_user]`
- **Services**: class-method entry points with keyword args (e.g. `CreditService.deduct_credits(company, action_type, company_user: user)`); custom error classes (e.g. `CreditService::InsufficientCreditsError`); wrap external calls in begin/rescue and log rather than always raising
- **Views**: i18n via `t()` for all user-facing strings; Tailwind utility classes; partials named `_partial.html.erb`; mobile-first breakpoints (`sm:`, `lg:`)
- **Tests**: Minitest (not RSpec), mirroring `app/` structure under `test/`; fixtures plus `SecureRandom.hex(4)` for uniqueness in setup
- **Style**: follows `rubocop-rails-omakase`; snake_case methods/vars, PascalCase classes, CONSTANT_CASE constants

## Development Workflow

For new feature requests or non-trivial changes, work through these stages before declaring done:
1. **Requirement analysis** — restate the ask, identify affected models/controllers/views, flag ambiguities to the user if blocking
2. **Design** — propose which files change and how, applying the Code Conventions above
3. **Implementation** — write the code
4. **Audit** — re-check the diff for security issues (see `security-review` skill), convention adherence, and that the feature actually works (run relevant tests or verify manually) before reporting completion

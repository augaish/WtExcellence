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

Deployed via **Kamal** (Docker-based) to `app.wtexcellence.com`. Config in `config/deploy.yml`. Docker image includes Tesseract OCR (en+ar), Poppler, and Apache Tika for PDF processing.

## LLM Configuration

Primary provider: **OpenRouter** (default model: `anthropic/claude-sonnet-4.5`). Per-task provider selection via env vars:
- `CAPA_ACTION_PROVIDER`, `CAPA_CLAUSE_PROVIDER`, `CAPA_QUESTIONNAIRE_PROVIDER` — set to `ollama` or `openrouter`
- Each has corresponding `CAPA_*_OLLAMA_MODEL` for local inference

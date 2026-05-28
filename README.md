# FSP Lightreach PO Manager

Internal Freedom Solar tool that automates the creation of Lightreach Direct Pay purchase orders for residential solar installations. It pulls the weekly install schedule from [Skedulo](https://skedulo.com), reconciles each project's Sales Order in [NetSuite](https://www.netsuite.com) against the project's Bill of Materials in [Project Sunrise](https://projectsunrise.com), creates a Purchase Order against the CED Direct Pay vendor, and distributes the resulting PO PDF to regional purchasing teams and to the customer's [Lightreach (Palmetto Finance)](https://palmetto.finance) account.

**Production:** https://purchasing.gofreedompower.com
**Heroku:** `fsp-lightreach-po-manager` (CI/CD via GitHub Actions)

---

## What it does

Every week, the purchasing team needs a PO created for every Lightreach Direct Pay installation that's scheduled to install. Historically this was a manual process across four systems. This app does it in one click per region:

1. **Pulls** the upcoming Installation and Tesla Powerwall jobs from Skedulo for the current and following week.
2. **Filters** to projects whose `lender == "Lightreach Lease"` (Lightreach Direct Pay).
3. **Parses** the project's BOM PDF out of Project Sunrise to extract Pegasus racking quantities and a long list of inverter/battery/component SKUs.
4. **Reconciles** quantities on the project's NetSuite Sales Order — adding or updating line items, while skipping any line that has already been fulfilled.
5. **Creates** a Purchase Order in NetSuite against `CED - Direct Pay` (vendor 2660586) for direct-pay projects, or `CED` (vendor 1054) for kitted jobs, copying the SO's customer, location, and ship-to address.
6. **Writes back** the PO link and creation date to the Sunrise project so it's not duplicated next run.
7. **Distributes** the PO: generates a region summary PDF, attaches every individual PO PDF, and emails it to the regional ROM/CAM distribution list via the Gmail API; uploads the PO PDF to the customer's Lightreach account as a `billOfMaterials` document.
8. **Streams** live progress and per-step logs to the React UI over ActionCable so the operator can see exactly what happened on every project.

There is also a one-off material-return workflow that emails the regional distribution list with PO context whenever inventory needs to be returned.

---

## Tech stack

| Layer | Tech |
|---|---|
| Language | Ruby 3.3.9 |
| Framework | Rails 7.2 |
| Database | PostgreSQL 15 |
| Background jobs | Sidekiq + Redis |
| Web server | Puma |
| Real-time | ActionCable (WebSockets) |
| Frontend | React 19 + MUI 9 + Emotion |
| Bundler | esbuild 0.19 (via jsbundling-rails) |
| Auth | Devise + Google OAuth2 (domain-restricted to `@gofreedompower.com`) |
| NetSuite | SuiteTalk REST + SuiteQL (OAuth 1.0, custom Faraday client) |
| Lightreach | Palmetto Finance REST API |
| Project Sunrise | v2 REST API + Elasticsearch |
| Skedulo | GraphQL API |
| Email | Gmail API via Google service account |
| PDF | Prawn (generate summaries) + pdf-reader (parse BOMs) |
| Errors | Sentry (ruby + rails + sidekiq) |
| Testing | RSpec + FactoryBot + WebMock + VCR + SimpleCov |
| Linting / security | Rubocop (Rails Omakase) + Brakeman |
| Hosting | Heroku (CI/CD via GitHub Actions) |

---

## Repository layout

```
app/
  controllers/
    api/v1/
      po_generation_controller.rb     → start / cancel / status / resend-email
      projects_controller.rb          → schedule by region, project show
      material_return_controller.rb   → email a material-return request
    dashboard_controller.rb           → React SPA shell
    users/                            → Devise + OmniAuth callbacks
  models/
    user.rb                           → Google-OAuth user (gofreedompower.com only)
    po_generation_job.rb              → Job state + atomic lock per region/project
    po_generation_log.rb              → Timestamped progress lines
    sunrise_task.rb                   → Stub for "Crew Installation Complete" check
  services/
    po_generation_service.rb          → Orchestrates one project's PO end-to-end
    job_schedule_service.rb           → Skedulo → Sunrise → location lookup (SuiteQL)
    email_notification_service.rb     → Per-region PO email + Lightreach upload
    material_return_service.rb        → Material-return email
    google.rb                         → Gmail service-account auth + send
  workers/
    batch_po_generation_worker.rb     → Region + batch jobs
    po_generation_worker.rb           → Single-project jobs
    add_racking_quantities_to_so_worker.rb  → BOM → Sales Order line updates
  channels/
    po_generation_channel.rb          → Live job log stream
  mailers/
    lightreach/direct_pay_mailer.rb   → Regional PO email + material-return email
  javascript/
    components/
      Dashboard.jsx                   → MUI dark theme, region tabs
      LoginPage.jsx
      po_generation/
        RegionView.jsx                → Per-region project list + actions
        ProjectList.jsx
        POGenerationProgress.jsx      → Live ActionCable log viewer
        LogViewer.jsx
        ManualProjectInput.jsx        → Single-project / batch entry
        ReturnMaterialDialog.jsx
        ManualReturnMaterialInput.jsx
lib/
  external/
    netsuite_api.rb                   → OAuth 1.0 client + SalesOrder / PurchaseOrder / InventoryItem
    project_sunrise_api.rb            → v2 REST wrapper, bulk fetch, file download
    lightreach.rb                     → Palmetto Finance client (Document, Account, Pricing, ...)
    skedulo_api.rb / skedulo_query.rb → GraphQL job lookup
    distribution_list.rb              → Email recipient groups (ROM, CAM, AROM, ...)
    http_verb.rb                      → Net::HTTP wrapper with multipart support
config/routes.rb
db/schema.rb
spec/                                 → RSpec specs (mirrors app/)
Procfile                              → Heroku web + worker + release
.github/workflows/ci.yml              → Brakeman + Rubocop + RSpec + 70% coverage gate
```

---

## Domain model

### `User` ([app/models/user.rb](app/models/user.rb))
Google-OAuth user. Only `@gofreedompower.com` emails are admitted (`User.from_google` returns `nil` otherwise).

### `PoGenerationJob` ([app/models/po_generation_job.rb](app/models/po_generation_job.rb))
One row per PO generation run. `job_type` is `region`, `batch`, or `single`. `status` is `pending → running → completed | failed`.

Per-region and per-project locking is enforced in code, not DB constraints:

- `PoGenerationJob.running_for_region?(region)` blocks two operators kicking off the same region simultaneously.
- `PoGenerationJob.locked_project_ids` blocks the same project being processed twice in parallel runs.

A job marked `failed` with `error_message == "Job cancelled by user"` is treated as cancelled — workers `reload` and check this at every step so cancellation takes effect mid-pipeline.

### `PoGenerationLog` ([app/models/po_generation_log.rb](app/models/po_generation_log.rb))
Append-only log lines with `level ∈ {info, success, warning, error}`. Written by `PoGenerationService#log_progress` (and `AddRackingQuantitiesToSoWorker#log_progress`); the same payload is broadcast to ActionCable for live UI updates.

---

## PO generation pipeline

```
User clicks "Generate POs for Austin" in the React UI
        │
        ▼
POST /api/v1/po_generation/region            → creates PoGenerationJob (pending)
        │
        ▼
BatchPoGenerationWorker (queue: po_generation)
        │
        ├─► JobScheduleService.fetch_direct_pay_on_schedule(region:)
        │       ├─ SkeduloApi.find_jobs("Installation") + find_jobs("Tesla Powerwall")
        │       │     scoped to today → end-of-next-week
        │       ├─ ProjectSunriseApi.get_projects_bulk(fields: [lender, ...])
        │       │     keep only lender == "Lightreach Lease"
        │       └─ NetSuite SuiteQL JOIN on transactionline.location
        │             to resolve each project's region (Austin / Houston / ...)
        │
        ├─► For each project:
        │       ├─ Skip if Crew Installation Complete (or system_size == 0)
        │       ├─ If project already has lightreach_direct_pay_po_link:
        │       │     ├─ Fetch existing PO from NetSuite
        │       │     ├─ Skip if already received (partiallyReceived/pendingBilling/fullyBilled/closed)
        │       │     └─ Reuse it
        │       ├─ Else:
        │       │     ├─ AddRackingQuantitiesToSoWorker (inline) — parse BOM PDF,
        │       │     │     update Pegasus + Envoy + Combiner + APKE + ... SO lines
        │       │     ├─ Fetch SO; filter PO-eligible items (categories 2,3,5,18,21,33)
        │       │     ├─ Create PO in NetSuite (vendor 2660586 direct pay, or 1054 kitted)
        │       │     │     amount = 0 for direct pay (cost is on the lender, not us)
        │       │     └─ ProjectSunriseApi.update_project — write back PO link + creation_date
        │
        ├─► Persist po_results on the job
        ├─► Broadcast status_update over ActionCable
        └─► EmailNotificationService.send_batch_email
                ├─ For each PO: fetch PDF from NetSuite, upload to Lightreach account
                └─ Group POs by region → one email per region with:
                      • region summary PDF (Prawn-generated, aggregated parts list)
                      • every individual PO PDF as an attachment
                      • Safe Harbor PW3 detection (item 971) adds purchasing@ to CC
```

Every step calls `log_progress(...)`, which writes a `PoGenerationLog` row **and** broadcasts to `po_generation_<job_id>` on ActionCable. The React `POGenerationProgress` component subscribes via `PoGenerationChannel`, gets all historical logs on connect (`transmit_existing_logs`), then streams new ones live.

---

## External integrations

### NetSuite ([lib/external/netsuite_api.rb](lib/external/netsuite_api.rb))
OAuth 1.0 (TBA) client. The full surface used here:

- `Netsuite::SalesOrder.find(id)` / `.find_external("sales_order_<sunrise_id>")` / `.update(id, body, replace_item: true)`
- `Netsuite::PurchaseOrder.new(...).create` / `.find(id)` / `.fetch_pdf_binary(id)`
- `Netsuite::InventoryItem.fetch_details_by_ids(ids)` — batched, used to map SO `item.id` to `itemid`/`displayname`/`custitem1` (category)
- `Netsuite::Client#suiteql(query:)` — used by `JobScheduleService` to resolve project → SO → location in one round-trip

Auth retries 401s once with a 10-second backoff (fresh nonce/timestamp). PO links written back to Sunrise point at the right NetSuite account URL per `Rails.application.credentials.netsuite.<env>.account_id_url`.

### Project Sunrise ([lib/external/project_sunrise_api.rb](lib/external/project_sunrise_api.rb))
- `ProjectSunriseApi.get_projects_bulk(ids, fields:)` — selective field fetch
- `ProjectSunriseApi.update_project(id, updates)` — writes `lightreach_direct_pay_po_link` + `lightreach_direct_pay_po_creation_date`
- `ProjectSunriseApi.get_file(project_id, "BOM")` — downloads the BOM PDF for parsing

Primary customer phone/email is extracted from the `customers` array indexed by `primary_customer_id`.

### Lightreach / Palmetto Finance ([lib/external/lightreach.rb](lib/external/lightreach.rb))
- `Lightreach::Document.upload(account_id, document)` — multipart upload of the PO PDF as `type: "billOfMaterials"`
- `Lightreach::Account.find` / `.update`
- `Lightreach::InstallPackage.save` / `Lightreach::ActivationPackage.save` (available but unused by this app's main flow)

Production uses `palmetto.finance/api`; non-production uses `next.palmetto.finance/api`.

### Skedulo ([lib/external/skedulo_api.rb](lib/external/skedulo_api.rb))
- `SkeduloApi.find_jobs(type, start_time:, end_time:)` — GraphQL query for `Installation` and `Tesla Powerwall` jobs
- `SkeduloApi.list_jobs_for_project(project_id, type)` — used to determine `job_start` per project

Only jobs in `Dispatched / Ready / En Route / On Site / In Progress / Complete` are considered.

### Gmail ([app/services/google.rb](app/services/google.rb))
Service-account auth with domain-wide delegation. Sender is `project_sunrise@gofreedompower.com`. The service account credentials are built dynamically from Rails credentials into `google-service-account.json` at boot if not present.

---

## BOM → Sales Order rules

The trickiest bit of business logic lives in [add_racking_quantities_to_so_worker.rb](app/workers/add_racking_quantities_to_so_worker.rb):

- **Pegasus racking** is identified by regex on the BOM (`P[SI][RFOW]-...` followed by `Pegasus` in the description). Several BOM part numbers map to a single SO part — e.g. `PSR-B168` → `PSR-M168-US (DOMESTIC)`, and `PSR-B84` → same SKU but at **half quantity (ceil)**. Quantities are aggregated when multiple BOM rows hit the same SO line.
- **Enphase Envoy** (`ENV-IQ-AM1-240` in BOM, item `941` in NetSuite) — when present, also adds `ENP CT-200-SPLIT` (item `949`) at the same quantity.
- **Combiner-WIFI-5** (item `734`) is added if-and-only-if the BOM contains `X-IQ-AM1-240-5-HDK`. If the HDK is missing and the SO has a Combiner line, it's removed (uses `replace_item: true` on the SO PATCH).
- **Standard SKUs** (Tesla MCI Gen2, PF-DW75, PIF2-BDT, PF-SF70, Tesla 200A CT, SUNMODO TOPTILE-7-B, SPAN 1-00800-XX, PL7R-40MID200-FG, Tesla Meter, and the APKE0008x–APKE00115 series) are matched on substring with their NetSuite item IDs hard-coded in `BOM_ITEM_CONFIGS`.
- **Already-fulfilled lines** (`quantityFulfilled > 0`) are always skipped — never updated, never removed.

PO-eligible categories on the SO are `[2, 3, 5, 18, 21, 33]` (Modules, Racking, Monitoring, Energy Storage, Inverters, "Other"). All other lines on the SO are excluded from the PO.

---

## Routes

| Verb | Path | Purpose |
|---|---|---|
| GET | `/users/sign_in` | Google OAuth login |
| GET | `/users/auth/google_oauth2/callback` | OAuth callback |
| GET | `/dashboard` | React SPA (root) |
| GET | `/api/v1/projects/schedule/:region` | Direct-pay projects on schedule for a region |
| GET | `/api/v1/projects/:id` | Single project + PO status |
| POST | `/api/v1/po_generation/region` | Start a region run |
| POST | `/api/v1/po_generation/project` | Start a single-project run |
| POST | `/api/v1/po_generation/batch` | Start a multi-project run |
| GET | `/api/v1/po_generation/jobs/:id` | Job status + logs |
| POST | `/api/v1/po_generation/cancel/:id` | Cancel a pending/running job |
| POST | `/api/v1/po_generation/resend_email` | Resend regional email for a completed job |
| POST | `/api/v1/material_return/request` | Email a material-return request |
| WS | `/cable` | ActionCable (live job logs) |
| GET | `/up` | Health check |

All `/api/v1/*` endpoints require an authenticated user; responses use a consistent `{ success, data | error }` envelope ([api/v1/base_controller.rb](app/controllers/api/v1/base_controller.rb)).

---

## Development

### Prerequisites
- Ruby 3.3.9 (`rbenv` or `asdf`)
- Node 16.20.2 (per `.node-version`) — Yarn for installs
- PostgreSQL 15
- Redis
- `config/master.key` for Rails encrypted credentials (ask a teammate)

### Setup

```bash
bundle install
yarn install
bin/rails db:create db:migrate
yarn build                           # bundle JS once
bin/rails server                     # http://localhost:3000
bundle exec sidekiq -C config/sidekiq.yml
```

For continuous JS rebuilds during development, use `Procfile.dev`:

```bash
bin/dev   # or: foreman start -f Procfile.dev
```

### Testing

```bash
bundle exec rspec                    # full suite
bundle exec rspec spec/services      # one directory
```

SimpleCov enforces **70% overall** coverage (lib/external/ is excluded). HTML and JSON reports land in `coverage/`. CI fails the build if coverage drops below 70%.

### Lint + security

```bash
bin/rubocop                          # style (Rails Omakase config)
bin/rubocop -A                       # auto-fix
bin/brakeman --no-pager              # static security scan
```

CI runs all three on every PR — see [.github/workflows/ci.yml](.github/workflows/ci.yml).

---

## Credentials

Stored encrypted in `config/credentials.yml.enc`, accessed via `Rails.application.credentials`. The shape used by this app:

```yaml
netsuite:
  production:
    account_id: ...
    account_id_url: ...
    consumer_key: ...
    consumer_secret: ...
    token_id: ...
    token_secret: ...
  sandbox:
    ...
PROJECT_SUNRISE:
  ROOT_V2: ...
  ORG_ID: ...
  API_KEY: ...
  USER_ID: ...
lightreach:
  production:
    username: ...
    password: ...
  next:
    username: ...
    password: ...
skedulo:
  api_key: ...
google_project_id: ...
google_client_email: ...
google_private_key_id: ...
google_private_key: ...
google_client_id: ...
devise:
  google_oauth2:
    client_id: ...
    client_secret: ...
sentry_dsn: ...
```

Edit with: `EDITOR=vim bin/rails credentials:edit`

Other env vars (set in Heroku Config Vars): `RAILS_MASTER_KEY`, `DATABASE_URL`, `REDIS_URL`.

---

## Deployment

**Never push directly to `main`. Never `git push heroku`.** Deploys are gated by CI and triggered by merges to `main`.

```bash
git checkout -b feature/your-change
# edit, test, lint locally
git push origin feature/your-change
gh pr create --title "..." --body "..."
# CI runs Brakeman + Rubocop + RSpec (with 70% coverage gate)
# Merge after review → Heroku auto-deploy
heroku logs --tail --app fsp-lightreach-po-manager
```

The Procfile defines three process types:

```
web:     bundle exec puma -C config/puma.rb
worker:  bundle exec sidekiq -C config/sidekiq.yml
release: bundle exec rails db:migrate
```

Sidekiq runs the `default`, `po_generation`, and `mailers` queues with concurrency 10 in production (`config/sidekiq.yml`).

---

## Useful links

- Production: https://purchasing.gofreedompower.com
- Repo: https://github.com/freedom-solar/fsp-lightreach-po-manager
- Project Sunrise: https://projectsunrise.com
- NetSuite SuiteTalk REST docs: https://docs.oracle.com/en/cloud/saas/netsuite/ns-online-help/section_1545564088.html
- Lightreach (Palmetto Finance) API: https://palmetto.finance
- Skedulo GraphQL: https://api.skedulo.com/graphql/graphql
- Sister app — site capture verification: https://github.com/freedom-solar/sunrise-site-capture

# Code-read areas

Answer each question from the code with `file:line` evidence. A question the code cannot
answer goes to the follow-up list in buyer mode, worded for the seller, and to the open
questions in owner mode, worded for the team.

## Architecture

- System shape: monolith, modular monolith, services, or serverless. Count deployable units from the inventory's `infra` and `ecosystems.dirs`.
- Frontend-to-backend contract: REST, GraphQL, RPC, or server-rendered. Find the API schema or client generation if one exists.
- Data stores: databases, caches, queues, object storage. Cite the settings or config that wires each one.
- Multi-tenancy model, if the product is multi-tenant: separate databases, separate schemas, or row-level filtering. Cite where the tenant filter is applied, and name one query path that skips it if you find one.
- Background work: the job framework, schedulers, and what runs out of band.
- Third-party services the product depends on: payments, email, SMS, auth, analytics, AI APIs. Cite the client setup.
- Hotspots: the inventory's `largest_source_files` and `git.most_changed_files_last_12_months`. A file on both lists is a likely coupling point. Read the top ones and say what they own.

## Code quality and tests

- Size by language, from the inventory or scc.
- Ratio of test files to source files, and which layers have tests.
- Whether CI runs the tests, and on which events. Cite the workflow file and job.
- Coverage reports in the repo, and coverage gates in CI.
- Linters and type checkers configured, and whether CI enforces them.

## Infrastructure and operations

- How the product deploys: the path from merge to production. Cite the CI jobs and deploy config.
- Environments: dev, staging, and prod separation in config.
- Containers: base image pinning, non-root user, multi-stage build, secrets passed at build time.
- Infrastructure as code: coverage of what runs in production, remote state, hardcoded credentials or wide-open network rules.
- CI security: secrets exposed to pull requests from forks, `pull_request_target` with checkout of PR code, actions not pinned to a commit SHA.
- Observability: error tracking, structured logging, metrics, health checks.
- Backups and recovery: anything in the config that shows backups, retention, or restore procedures.

## Licensing and IP

Report everything in this area as an **observation**: no severity, not counted in the summary
table, never in the investment summary's top risks. IP ownership and license rights live in
contracts and assignments, not in the repo, so each observation pairs with a question for the
seller or counsel.

- The repo's own license file, and any license the code or API metadata declares.
- Dependency licenses from the license scan: copyleft (GPL, AGPL, SSPL) and packages with no license.
- Vendored or copied third-party code, and third-party content the product ships: directories like `vendor/` or `third_party/`, files with a foreign copyright header, copied standards or datasets. Cite each one.
- Contributor provenance: authors in `git.top_authors` whose names or domains suggest contractors or outside parties. Ask for an IP assignment for each one.

## Data and subprocessors

- A data map: which customer and personal data the product stores, where (database, object storage, logs, traces, analytics), and for how long. Cite the model, schema, or config for each store.
- Subprocessors: every external service that receives customer data, with what it receives. Include LLM providers, document parsers, error tracking, analytics, and tracing. Cite the call site.
- Data that leaves the product's own infrastructure to a place without access control or retention limits is High.
- Regulated data (health, payment, children's, biometric) and where it is handled. Name the regime it implies (HIPAA, PCI DSS, COPPA, GDPR special categories).

## AI and vendor economics

Only when the product calls an LLM or another paid per-use API.

- The calls made per unit of work (per analysis, per request, per document): which models, how many calls, and whether inputs are cached or batched. Cite the orchestration code.
- Cost signals in the repo: token limits, budget guards, cost logging, per-tenant quotas. Their absence on an unauthenticated or unmetered path is High.
- Vendor concentration: which features stop working if one provider is unavailable or changes terms, and whether a fallback provider exists in code.
- Model quality controls: evals, golden fixtures, regression tests on prompts, and whether CI runs them.

## Scalability

- What limits growth: single instance or process, in-process background work, shared global state, per-tenant locks, database connection limits, synchronous calls to slow vendors.
- What happens at 10× today's load for each limit, judged from the code and deploy config. Say which limit is hit first.
- Whether the deploy config can run more than one instance safely. Cite the setting or code that decides it.

## Seller claims

Only when `--claims` names a file. For each claim the file makes about the technology
(architecture, security, compliance, scale, test coverage, proprietary technology), give a
verdict with evidence: `supported`, `partly supported`, `contradicted`, or `unverifiable from
the repo`. A contradicted claim is a finding at the severity of the gap it hides.

## Team and process

- Bus factor: `git.top_author_share_last_12_months`. One author above 0.5 is a High finding in buyer mode and a Medium finding in owner mode.
- Activity: commits and authors in the last 12 months, and the date of the last commit.
- Review discipline: `CODEOWNERS`, PR templates, and whether recent commits on the default branch carry PR numbers (`git log --oneline -50`).
- Documentation: README setup steps, ADRs, runbooks, security policy, from the inventory's `docs`.

The repo cannot show branch protection, incident history, on-call coverage, or team
retention. List them as open questions (the follow-up list in buyer mode).

## Buyer mode: also request

Add each item that the repo does not already contain to the report's follow-up list:

- architecture and data-flow diagrams
- the production infrastructure inventory and cloud account structure
- the incident log for the last 12 months and any security incidents
- penetration test reports and remediation status
- compliance attestations (SOC 2, ISO 27001, HIPAA) and their scope
- IP assignment agreements for every contributor
- open-source license policy and any license audits
- the third-party service contracts the product depends on
- data processing agreements with each subprocessor
- monthly cloud and per-use vendor (LLM, parsing) spend for the last 6 months
- the growth plan the system must support (customers, documents, requests per month)

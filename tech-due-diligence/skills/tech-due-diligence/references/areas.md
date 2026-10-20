# Code-read areas

Answer each question from the code with `file:line` evidence. A question the code cannot
answer goes to the open-questions list, worded for the person who can answer it: the seller
in buyer mode, the team in owner mode.

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

- The repo's own license file. In buyer mode, a permissive open-source license on code the seller calls proprietary is a High finding.
- Vendored or copied third-party code: directories like `vendor/` or `third_party/`, files with a foreign copyright header. Cite each one with its license.
- Contributor provenance: authors in `git.top_authors` whose names or domains suggest contractors or outside parties. In buyer mode, ask for IP assignment for each one.

## Team and process

- Bus factor: `git.top_author_share_last_12_months`. One author above 0.5 is a High finding in buyer mode and a Medium finding in owner mode.
- Activity: commits and authors in the last 12 months, and the date of the last commit.
- Review discipline: `CODEOWNERS`, PR templates, and whether recent commits on the default branch carry PR numbers (`git log --oneline -50`).
- Documentation: README setup steps, ADRs, runbooks, security policy, from the inventory's `docs`.

The repo cannot show branch protection, incident history, on-call coverage, or team
retention. List them as open questions.

## Buyer mode: also request

Add each item that the repo does not already contain to the report's request list:

- architecture and data-flow diagrams
- the production infrastructure inventory and cloud account structure
- the incident log for the last 12 months and any security incidents
- penetration test reports and remediation status
- compliance attestations (SOC 2, ISO 27001, HIPAA) and their scope
- IP assignment agreements for every contributor
- open-source license policy and any license audits
- the third-party service contracts the product depends on

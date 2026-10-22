# Scanner commands by signal

`<repo>` is the audited repo root. `<work>` is the work directory from step 1. `<scripts>` is
the scripts directory from the skill's Resource paths. `<dir>` is a
directory from `ecosystems.<name>.dirs` in the inventory. Run a row only when its tool is
present in the inventory's `tools` map, using the path the map gives.

A tool that exits nonzero because it found issues has run successfully. Treat a nonzero exit
as a failure only when the output file is missing or does not parse.

## Every repo

| Area | Tool | Command |
|---|---|---|
| Secrets (full history) | gitleaks | `gitleaks git <repo> --no-banner --redact --exit-code 0 --report-format json --report-path <work>/gitleaks.json` |
| Secrets (config settings) | python3 | `python3 <scripts>/config_secrets.py scan <repo> > <work>/config-secrets.json` |
| Code security | semgrep | `semgrep scan --metrics off --quiet --json --output <work>/semgrep.json --config p/default <extra --config packs> <repo>` |
| Size | scc, else cloc | `scc --format json <repo>` / `cloc --vcs=git --json <repo>` |

Without git history (`git` is null in the inventory), run `gitleaks dir <repo>` with the same
flags and mark the secrets area `PARTIAL: no git history`.

Add a semgrep `--config` pack for each language in the inventory's `languages`:
Python → `p/python`, JavaScript → `p/javascript`, TypeScript → `p/typescript`,
Go → `p/golang` and `p/gosec`, Rust → `p/rust`, Ruby → `p/ruby`, Java → `p/java`,
Kotlin → `p/kotlin`, Scala → `p/scala`, C# → `p/csharp`, PHP → `p/php`, Swift → `p/swift`,
Elixir → `p/elixir`, C and C++ → `p/c`. A language not in this list gets `p/default` only;
say so under Method. Never pass a pack name that is not listed here: semgrep fails the whole
scan on an unknown pack.

Also add a pack for each detected framework or infra kind:
`django` → `p/django`, `flask` → `p/flask`, `react` → `p/react`, `nextjs` → `p/nextjs`,
`express` → `p/expressjs`, `terraform` → `p/terraform`, `dockerfile` → `p/dockerfile`,
`ci:github-actions` → `p/github-actions`. When the registry is unreachable, semgrep fails
on fetch. Mark code security `NOT RUN: semgrep registry unreachable`.

semgrep's `errors` array lists per-file parse and matching problems at `warn` level. They do
not stop the scan. Report their count and the affected file count under Method; mark code
security `PARTIAL` only when an error has `level` `error`.

gitleaks matches known token shapes, so it misses a hand-picked password in a TOML, YAML,
or env file. `config_secrets.py scan` matches on the setting's name instead and reports each
setting's `kind` and value length, never the value. Triage its results:

- `literal` or `credential-url` in a non-template file is a credential finding: High, or Critical when `tracked_in_git` is true or the file is a deploy config that the hosting platform shows to its users (for example `[env]` in `fly.toml`).
- `literal` in a template file (`template: true`) is Low unless the value is not a placeholder. Check that through the redacted view's length and context only.
- `reference` and `placeholder` are not findings. A deploy config that references a secret store is the correct pattern; say so in the strengths.

Then check the inventory's environment files and key material:

- Each file in `tracked_env_files` or `tracked_key_material` (in git) is High.
- A file in `untracked_env_files` or `untracked_key_material` is on disk outside version control. That is normal for a local environment file: report it only when `config_secrets.py scan` lists a `literal` credential in it, at the severity above, and as Low hygiene otherwise.
- Do not read any of these files except through `config_secrets.py view`. Cite the path, the setting name, and the line.
- Triage gitleaks hits with `python3 <scripts>/config_secrets.py context <repo> <work>/gitleaks.json`. It reads each hit from its commit, or from the working tree for `gitleaks dir`, and masks the value wherever it recurs.

## Dependency vulnerabilities and licenses

Prefer osv-scanner v2. One pass reads every lockfile, reports vulnerabilities, and, with
`--licenses`, adds a license summary from deps.dev. It executes nothing, and the license data
needs network access.

| Signal | Tool | Command |
|---|---|---|
| any lockfile | osv-scanner v2 | `osv-scanner scan source --licenses -r <repo> --format json --output <work>/osv.json` |
| any lockfile | osv-scanner v1 | `osv-scanner -r <repo> --format json --output <work>/osv.json` (no license summary) |
| any lockfile, no osv-scanner | trivy | `trivy fs --scanners vuln --skip-dirs node_modules,.venv,venv --format json --output <work>/trivy-vuln.json <repo>` |

Check `osv-scanner --version` to pick the v1 or v2 form. In v2 output, `license_summary`
counts packages per license, and each result package lists its `licenses`. Without
osv-scanner or trivy, fall back to the per-ecosystem rows. `<lockdir>` is the directory of a
lockfile listed in `ecosystems.<name>.lockfiles`. Pass the directory as a flag; do not `cd`.

| Ecosystem | Tool | Command |
|---|---|---|
| node | npm | `npm audit --prefix <lockdir> --json --package-lock-only` (for `package-lock.json`) |
| node | pnpm | `pnpm audit --dir <lockdir> --json` (for `pnpm-lock.yaml`) |
| python | pip-audit | `pip-audit -r <requirements file> --no-deps --disable-pip --format json`, only when every line is pinned with `==` |
| go | govulncheck | `govulncheck -C <lockdir> -json ./...` (for `go.sum`; downloads modules, needs the Go toolchain) |
| rust | cargo-audit | `cargo audit --json --file <Cargo.lock path>` |
| ruby | bundle-audit or bundler-audit | `bundle-audit check <lockdir> --format json --output <work>/bundle-audit.json` (for `Gemfile.lock`) |

- pnpm refuses to run when the project pins a different pnpm version in `packageManager`. Mark that lockfile `PARTIAL: pnpm version mismatch` unless osv-scanner covered it.
- bundle-audit prints advisory-database progress to stdout, so always pass `--output`.
- pip-audit exits nonzero for an unpinned line and audits nothing in that file.

One lockfile at a workspace root covers its member packages. Audit each lockfile once; a
package directory with no lockfile of its own is covered by the workspace lockfile above it.

A Python requirements file with unpinned lines cannot be audited without resolving it. Mark it
`NOT RUN: unpinned requirements`, and report the unpinned dependencies as a Medium finding.
A manifest with no lockfile in its directory or any workspace root above it is a Medium
finding (non-reproducible builds).

A finding in a dev-only or test-only dependency is at most Medium unless it ships in the
deployed artifact.

### Licenses

Use osv-scanner's `license_summary` and per-package `licenses`. trivy's license scanner reads
installed packages (`node_modules`, `site-packages`), not lockfiles, so it reports nothing for
a repo with no installed dependencies. Use it only when those directories exist. Without a
license source, mark dependency licenses `NOT RUN: no license scanner`. Still check the repo's
own license and vendored code from the inventory and the areas reference.

`UNKNOWN` from deps.dev means the license data is missing, not that the package has no
license. Report an `UNKNOWN` package only after checking its manifest metadata in the
lockfile or registry record; if it is still unknown, list it as an observation marked unverifiable.

License results are observations, not severity-ranked findings (see the licensing and IP
section of the areas reference). For each, note the obligation it may carry: AGPL, SSPL, or
network-use clauses for a service; GPL for a distributed product; LGPL, MPL, EPL for
modification and notice duties; a package with no license.

## Container images

For each entry in the inventory's `container_images`, resolve the reference first. Replace each
`${VAR}` or `${VAR:-default}` with its value from the repo's env template (`env.example`,
`.env.example`, `.env.sample`) or the compose default. Never read a real environment file to
resolve it. Skip a reference built by this repo (a compose service with a `build:` key). Scan
each distinct resolved reference once:

| Tool | Command |
|---|---|
| trivy | `trivy image --image-src remote --scanners vuln,license --format json --output <work>/trivy-image-<n>.json <ref>` |

`--image-src remote` pulls the image layers from the registry and runs nothing, so this is
allowed in buyer mode. A reference that stays unresolved, or a private registry that refuses
the pull, is `PARTIAL: <ref> not scanned (<reason>)`. A floating tag (`latest`, `alpine`, a
bare major version) means the scan describes today's image, not what installs run; say so.
Report image vulnerabilities under Dependencies and image licenses as licensing observations.

## Infrastructure

| Signal | Tool | Command |
|---|---|---|
| `dockerfile` | hadolint | `hadolint --format json <each Dockerfile>` |
| `terraform`, `kubernetes`, `helm`, `cloudformation`, `dockerfile`, `ci:github-actions` | checkov | `checkov -d <repo> --quiet --compact -o json --skip-path node_modules --skip-path .venv` |

Without these tools, read the files yourself and apply the infrastructure questions in
the areas reference.

## Stack packs

Run a pack only when the inventory lists its framework.

### Django

- Read every file in `django_settings_modules`. Find the module that production loads, from `DJANGO_SETTINGS_MODULE` in the manage, WSGI, or ASGI files and in the deploy config.
- Check in that module, following its imports: `DEBUG`, `ALLOWED_HOSTS`, `SECRET_KEY` source, `SESSION_COOKIE_SECURE`, `CSRF_COOKIE_SECURE`, `SECURE_SSL_REDIRECT` or a proxy that enforces HTTPS, `SECURE_HSTS_SECONDS`, `X_FRAME_OPTIONS` or `XFrameOptionsMiddleware`, `CSRF_TRUSTED_ORIGINS`, CORS settings, and `DEFAULT_PERMISSION_CLASSES` when DRF is present.
- A value read from the environment is not a finding by itself. Report the default that applies when the variable is unset.
- Owner mode only, and only when the project's environment is already installed: run `python manage.py check --deploy` with the production settings module and quote its output.
- When DRF is present, list viewsets and API views with no permission class and no default. Recommend a dedicated RBAC review for depth.

### React, Next.js, Vue, Angular

- Read semgrep's framework-pack results.
- Search for client-exposed environment variables (`NEXT_PUBLIC_`, `VITE_`, `REACT_APP_`) whose names suggest secrets.
- Search for auth tokens kept in `localStorage` or `sessionStorage`.
- Note the build tool, the state management library, and the test runner from `package.json`.

### Apple apps (iOS, macOS)

Read every file in `apple_config_files`, then search the Swift sources.

- **Dependencies.** Find the declared packages in `project.yml` (`packages:`), `Package.swift`, `project.pbxproj` (`XCRemoteSwiftPackageReference`), or `Podfile`. Without a tracked `Package.resolved` or `Podfile.lock`, the versions float. Report that as Medium and mark Swift dependency vulnerabilities `NOT RUN: no Swift lockfile`. osv-scanner reads `Package.resolved` and `Podfile.lock` when they exist.
- **Transport security.** In `Info.plist`, `NSAppTransportSecurity` with `NSAllowsArbitraryLoads` true is High. A per-domain exception is Low; name the domain.
- **Secrets in the bundle.** API keys or tokens in `Info.plist`, `.xcconfig`, or Swift string literals ship inside the app, and anyone can extract them. Report each as High, unless it is a key designed to be public (a publishable or client-side key); say which.
- **Credential storage.** Auth tokens, passwords, or keys written to `UserDefaults`, `@AppStorage`, or plain files are High. They belong in the Keychain. Check the Keychain accessibility class: `kSecAttrAccessibleAlways` is Medium.
- **Purchases.** For StoreKit, find where entitlement or credit decisions are made. A server that grants or spends value based on a client-sent identifier without verifying a signed transaction is High. Name the endpoint.
- **Entitlements and capabilities.** List the entitlements. Flag any that the code does not use (Medium), and associated domains or URL schemes whose handlers act on input without validation (Medium).
- **Privacy manifest.** Check that `PrivacyInfo.xcprivacy` exists when the app uses required-reason APIs (`UserDefaults`, file timestamps, system boot time, disk space). Missing → Medium (App Store rejection risk).
- **Logging.** `print`, `NSLog`, or `os_log` with `.public` on user data, tokens, or health data is Medium.
- **Build and release.** Signing files appear in `tracked_key_material`. Read CI or Xcode Cloud scripts (`ci_scripts/`) for secrets and unsigned-artifact paths.

### Android

Read every file in `android_config_files` and the module `build.gradle` or `build.gradle.kts` files.

- **Manifest.** `android:debuggable="true"` or `android:allowBackup="true"` in a release manifest is Medium. An `exported` activity, service, receiver, or provider with no permission is High when it acts on intent data; name the component.
- **Transport security.** `android:usesCleartextTraffic="true"` or a `network_security_config.xml` that permits cleartext or trusts user certificates in release is High. A per-domain exception is Low; name the domain.
- **Secrets in the app.** API keys in `gradle.properties`, `BuildConfig` fields, string resources, or Kotlin/Java literals ship inside the APK. Report each as High unless it is designed to be public; say which. `google-services.json` holds public client identifiers. Report it only when its project has no API key restrictions you can confirm from the repo, and then as unverifiable.
- **Credential storage.** Tokens or passwords in plain `SharedPreferences` or files are High. They belong in the Android Keystore or `EncryptedSharedPreferences`.
- **WebView.** A WebView that enables JavaScript (`setJavaScriptEnabled`) and exposes `addJavascriptInterface` to content that is not bundled is High. Enabling `setAllowFileAccess` for remote content is Medium.
- **Release build.** `minifyEnabled false` for release is Low. A release `signingConfig` with inline passwords is High. Signing keystores appear in `tracked_key_material`.
- **Purchases.** For Play Billing, find where entitlements are granted. A server that grants value on a client-sent purchase token without verifying it with Google Play is High.
- **Dependencies.** Without `gradle.lockfile` or dependency verification metadata, versions can float through dynamic versions (`+`, `latest.release`). Report each dynamic version as Medium. osv-scanner reads `gradle.lockfile` when it exists.

### Go

- semgrep `p/golang` and `p/gosec` cover code patterns. govulncheck reports only vulnerabilities whose code is reachable; say so when you cite it.
- Read the HTTP server setup: timeouts on `http.Server` (missing `ReadHeaderTimeout` is Medium), TLS configuration (a TLS config that sets `InsecureSkipVerify` is High), and the auth middleware coverage of each router group.
- Check `database/sql` calls that build queries with `fmt.Sprintf` or string concatenation. Parameterized calls with `?` or `$1` placeholders are not findings.
- Check `go.mod` for `replace` directives that point at local paths or forks; list them under licensing and IP.

### Rust

- semgrep `p/rust` covers code patterns. cargo-audit reports advisories and yanked crates from `Cargo.lock`.
- Count `unsafe` blocks per crate. Read the ones in code that parses untrusted input; an unchecked bound or aliasing assumption there is High.
- Check TLS clients that turn off certificate verification (for example via `danger_accept_invalid_certs`), which is High.
- Check `Cargo.toml` for git dependencies and path dependencies outside the repo; list them under licensing and IP.

### Rails

- Read `config/environments/production.rb`: `force_ssl`, `config.hosts`, and the credentials setup.
- semgrep `p/ruby` covers code patterns.

### Spring Boot

- Read `application*.properties` and `application*.yml`. Check actuator exposure, `server.ssl`, and the security configuration classes.
- semgrep `p/java` covers code patterns.

### Express, NestJS, Flask, FastAPI

- Read the app entry point. Check the security headers middleware, CORS configuration, auth middleware coverage, and debug flags.

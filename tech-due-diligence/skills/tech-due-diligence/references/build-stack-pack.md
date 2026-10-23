# Build a stack pack at run time

Use this when the inventory detects a stack that no pack in the `stacks` reference names: an
entry in `frameworks` or `ecosystems`, or a language in `languages` with at least 10% of the
source lines and no ecosystem (for example C or C++). Examples: PHP or Laravel, .NET, Elixir or
Phoenix, Dart or Flutter, Svelte, Nuxt, React Native.

Build one pack per such stack, then run it as its own lane, like a written pack.

## Find the stack's own surfaces

From the inventory and the code, list with `file:line`:

- **Entry points**: the app bootstrap, router or route table, and request handlers.
- **Config**: the settings files the production build loads, and how it picks them per environment.
- **Auth**: where requests are authenticated and authorized, and which routes skip it.
- **Data access**: the ORM or query layer, and any raw query or command execution.
- **Build and release**: the manifest, build scripts, and release or signing config.

## Write the checks

Write 5–10 checks, each one line, in the form of the written packs: what to read, what is a
finding, and its severity. Cover each category below that applies to the stack:

- **Debug and environment**: debug or development flags that can reach production.
- **Transport**: TLS settings, certificate verification turned off, cleartext allowed.
- **Secrets in the artifact**: keys or tokens in config, resources, or literals that ship to clients or into the build.
- **Credential storage**: tokens or passwords stored without the platform's secure store or hashing.
- **Injection sinks**: the stack's raw SQL, shell, template, or deserialization calls that take request data. Parameterized or escaped calls are not findings.
- **Auth coverage**: handlers or routes with no auth check, and admin surfaces.
- **Security headers and CORS**: for web stacks.
- **Dependencies**: floating versions, missing lockfiles, and git or path dependencies. List git and path dependencies under licensing and IP.
- **Release**: signing secrets inline, unsigned or debug release builds.

Use the severities of the written packs for the same kind of issue. Base each check on the
stack's own API names found in the code. Do not write a check for a feature the repo does not use.

## Report it

- Under Method, name each built pack, list its checks, and say it was built at run time.
- Findings from a built pack follow the same triage, evidence, and basis rules as any other lane.
- When the code is too thin to find the surfaces above, mark the pack `PARTIAL: <what is missing>`.

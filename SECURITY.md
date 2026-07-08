# Security Policy

### Reporting a vulnerability

Use [private vulnerability reporting](https://github.com/starfysh-tech/nautilai/security/advisories/new).
Reports stay private until a fix ships. Do not open a public issue for a vulnerability.

### Scope

nautilai plugins ship shell scripts and skills that **execute in your repository**
when you install and run them. In scope:

- A plugin script that could execute unintended code, exfiltrate secrets, or write
  outside the repo root.
- A skill or workflow that induces such behavior through its instructions.
- Setup steps that weaken a repo's security posture (e.g. disabling a required check
  without disclosure).

### Not in scope

- Claude Code itself — report to Anthropic.
- Vulnerabilities in a repo's own code that a plugin merely reports on.

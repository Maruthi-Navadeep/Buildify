# Security Policy

## Supported versions

The latest released version and `main` receive security fixes. Older tagged
releases are not maintained.

## Reporting a vulnerability

**Please do not open a public issue for security vulnerabilities.**

Report privately using GitHub Security Advisories:

1. Go to the [Security tab](https://github.com/Maruthi-Navadeep/Buildify/security/advisories/new).
2. Click **Report a vulnerability** and describe the issue, including steps to
   reproduce and the affected version/commit.

We aim to acknowledge reports within **72 hours** and to provide a remediation
timeline after triage. Please give us a reasonable window to release a fix
before any public disclosure.

## Scope & threat model

Buildify turns a device into a local LLM HTTP server that can be exposed
publicly through a tunnel. Security-sensitive areas include:

- **The HTTP server** (`lib/services/static_site_server.dart`, the AI server) —
  path traversal, response injection, and what it binds to.
- **Process spawning** (`lib/services/process_server.dart`,
  `lib/services/desktop_server_bridge.dart`) — command handling and the
  environment forwarded to child processes.
- **Tunnel exposure** — anything reachable over the public Cloudflare URL.
- **Local network discovery** (`lib/services/mdns_service.dart`) — the beacon
  requires a shared secret; report any way to bypass it.
- **Secret handling** — API keys and any use of secure storage.

When you run this app you are exposing services from your own device. Only
enable the public tunnel on networks and for content you control.

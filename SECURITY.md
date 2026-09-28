# Security and privacy

## Report a vulnerability privately

Use [GitHub private vulnerability reporting](https://github.com/EdgarHnd/Burro/security/advisories/new). Include the affected version/commit, a minimal synthetic reproduction, impact, and any suggested fix. Do not put vulnerabilities, credentials, provider databases, or live transcripts into public issues.

The latest version on the default branch is the supported development version. There is no promised response time or long-term support schedule yet.

## Trust model

Burro is an unsandboxed macOS app running as the current user. It reads Git state, same-user process information, and Codex/Claude metadata using normal filesystem permissions. It does not request Accessibility or Input Monitoring permissions for normal operation.

- Git inspections do not fetch or perform cleanup. Status checks disable optional locks and fsmonitor. Safe-candidate labels are advisory and can become stale immediately.
- Provider databases are opened read-only. Bounded transcript tails are parsed for lifecycle events; message bodies are not retained or exported. Authentication files are outside the readers' scope.
- Remote monitoring uses the user's existing OpenSSH trust and authentication. Hosts are explicitly configured; strict known-host checks, batch authentication, fixed commands, and disabled forwarding are required. Burro does not install a service or copy provider credentials to remote machines.
- Paths, titles, agent states, and completion metadata may travel from configured hosts to this Mac over SSH. Local unread lists are not sent to remote hosts.
- Preferences store repository roots, protection flags, comparison refs, notch settings, and explicit remote host configuration. Session metadata is held in memory. The CLI prints paths and titles, so redact output before sharing it.
- Provider storage schemas and URL routes are private interfaces. Unsupported or incomplete data must remain visible as uncertainty, never become evidence that deletion is safe.

A user-controlled SSH configuration can itself invoke programs such as ProxyCommand. Only add SSH hosts/configuration you trust. Burro is not an isolation boundary for a malicious local account, repository configuration, or remote host.

## Distribution

The public release contains source. Local build scripts ad-hoc sign bundles; this is not Developer ID distribution signing or Apple notarization. Do not treat an independently supplied Burro binary as an official signed release. CI does not publish app bundles or require signing credentials.

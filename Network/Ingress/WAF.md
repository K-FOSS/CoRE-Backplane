# CoRE-Backplane Network/Ingress WAF Guide

CoRE's opt-in web application firewall runs Coraza with OWASP Core Rule Set
(CRS) inside the existing Envoy data plane. The fleet owner is the
[`Apps/Network/Ingress.yaml`](../../Apps/Network/Ingress.yaml) ApplicationSet,
the reusable policy template is [`templates/WAF.yaml`](templates/WAF.yaml),
and the default configuration is in [`values.yaml`](values.yaml). See the
[Network stack overview](../README.md) for the parent stack.

Current status: implemented and repository-validated, pending isolated
runtime validation and deployment. It is not live protection. This change
does not reconcile Argo CD, mutate a cluster, or enable production-wide
blocking.

## Ownership, targets, and discovered versions

`Apps/Network/Base.yaml` owns the Envoy Gateway controller through the
`Network/Base` chart. `Apps/Network/Ingress.yaml` owns `GatewayClass`,
`EnvoyProxy`, the shared `core-prod/main-gw` Gateway, its traffic policies,
and the new `EnvoyExtensionPolicy`. Application charts continue to own their
`HTTPRoute` and `SecurityPolicy` resources. No Crossplane or Terraform resource
owns this HTTP filter, so neither system is involved.

Repository and read-only YVR inspection on 2026-10-29 found:

| Item | Repository desired state | Observed YVR state |
| --- | --- | --- |
| Envoy Gateway chart/controller | `gateway-helm`/`v1.9.2` | `envoyproxy/gateway:v1.9.2` |
| Envoy data plane | `distroless-v1.39.3` pinned by digest | `distroless-v1.39.1` pinned by digest |
| Extension API | `gateway.envoyproxy.io/v1alpha1` | `EnvoyExtensionPolicy` CRD serves `v1alpha1` with HTTPRoute targets, OCI Wasm, SHA-256 verification, and `failOpen` |
| Gateway topology | one unmerged data plane per Gateway | `core-prod/main-gw`; the HTTPS listener had 107 attached routes |
| Log collection | Envoy pods carry `logs=loki-myloginspace` | two YVR Envoy pods had that label; Alloy selects it and adds cluster/site metadata |

The data-plane difference is deployment drift, not a proposed upgrade. Before
deployment, confirm the published desired image and both sites' actual images.
The Gateway Service uses `externalTrafficPolicy: Local`, which preserves the
direct downstream address. No repository or observed `ClientTrafficPolicy`
configures trusted forwarded-header hops. Coraza and any future ban logic must
therefore use Envoy's downstream peer address and must not treat an arbitrary
`X-Forwarded-For` value as authoritative. A CDN or reverse proxy requires an
explicit, narrowly trusted proxy policy before its forwarded address can be
used.

The initial policy targets only YVR's
`core-home1-talos-prod-net-testing-prod` LibreSpeed HTTPRoute. YXL renders no
WAF policy, and every unselected YVR route is unaffected. This avoids initial
inspection of Authentik callbacks, SMS webhooks, Harbor and multipart uploads,
S3 signed requests, gRPC, and WebSocket applications.

## Integration decision

| Option | Compatibility and cost | Decision |
| --- | --- | --- |
| Coraza proxy-Wasm with `EnvoyExtensionPolicy` | Envoy Gateway v1.9 supports OCI Wasm and HTTPRoute attachment. The installed CRD confirms the exact fields. The requested `ghcr.io/corazawaf/coraza-proxy-wasm:main` image is selected, with its resolved manifest digest enforced by the policy. No controller flag, pod sidecar, or routing tier is required. | Selected; smallest route-scoped in-process change. |
| Coraza native/[dynamic module](https://www.envoyproxy.io/docs/envoy/latest/intro/arch_overview/advanced/dynamic_modules) | Envoy Gateway v1.9 exposes dynamic-module policy fields, but Coraza does not publish a supported Envoy dynamic-module artifact. This would require a custom module/image lifecycle and couple the shared library to Envoy's unstable dynamic-module ABI and exact data-plane build. | Rejected for this phase. |
| `EnvoyPatchPolicy` | Could inject a filter when extension APIs are insufficient, but patch paths depend on generated xDS names and protobuf structure. Upgrades and route changes can silently invalidate the patch. | Fallback only; unnecessary on v1.9.2. |
| Separate [ModSecurity](https://github.com/owasp-modsecurity/ModSecurity#readme)/[BunkerWeb](https://docs.bunkerweb.io/latest/) proxy | Mature alternative inspection engines, but adds another reverse-proxy tier, workload, failure domain, certificate/routing path, and observability surface. | Not implemented. |

The selected API and attachment follow the versioned [Envoy Gateway v1.9 Wasm
guide](https://gateway.envoyproxy.io/v1.9/tasks/extensibility/wasm/) and
[`EnvoyExtensionPolicy` v1.9 API](https://gateway.envoyproxy.io/v1.9/api/extension_types/#envoyextensionpolicy).
The module is the upstream [Coraza proxy-Wasm `main` image](https://github.com/corazawaf/coraza-proxy-wasm),
whose [configuration documentation](https://github.com/corazawaf/coraza-proxy-wasm/blob/main/README.md)
records the filter configuration. The image is referenced by the mutable `:main`
tag for registry compatibility, while Envoy Gateway verifies the immutable
amd64 image-manifest digest recorded in `values.yaml` (not the multi-platform
index digest). The upstream image metadata does not publish
a standalone CRS version for this image; retain the configured CRS compatibility
assumption until the image is mirrored and inspected in the isolated canary. Use the [OWASP CRS false-positive tuning
guide](https://coreruleset.org/docs/2-how-crs-works/2-3-false-positives-and-tuning/)
when reviewing canary events. Registry inspection verified manifest
digest `sha256:c9f2c0e03038b9961ddb8eb94ffd4dede0acf3ccaa4970255cb241f4c2543ea5`,
release revision `b0c1b024854049ffd5e8cc63a869bbb6de153b71`, amd64 architecture.
The upstream project warns of possible TinyGo memory leaks and
performance degradation; soak testing is a blocking promotion criterion.
The review manifest references the verified upstream GHCR digest. Site-local
Harbor mirroring and a digest comparison are explicit pre-deployment gates;
until that is done, a cold controller cache depends on GHCR availability and
the canary's fail-open behavior preserves traffic without providing WAF
inspection.

## Request processing and safety settings

The policy defaults to `SecRuleEngine DetectionOnly`, CRS paranoia level 1,
and a 1 MiB request-body and in-memory limit. Detection-only changes disruptive
rule actions into observations; it is distinct from `failOpen: true`, which
bypasses the module after fatal initialization/execution or invalid
configuration errors. Both are intentional for the canary. A failed image
download or policy programming error must still be detected from policy
conditions and controller/Envoy logs; fail-open is not evidence that the
policy loaded.

The module processes at most the first 1 MiB of an oversized body in this mode.
The remainder continues upstream, so partial processing has an explicit bypass
risk and an `INBOUND_DATA_ERROR`/body-processing event must be monitored.
Streaming requests are buffered only within that bound. Response-body
inspection is explicitly off, avoiding response buffering and leakage of
response content into audit output. Before blocking, choose per-route limits;
blocking mode normally changes oversized-body handling to rejection rather
than partial inspection.

The v1.9.2 [filter-order implementation](https://github.com/envoyproxy/gateway/blob/v1.9.2/internal/xds/translator/httpfilters.go)
places external authorization, API-key/basic/OAuth2/JWT authentication, and
the request buffer before Wasm; the router is last. Therefore a future WAF on
an Authentik-protected route runs after its authorization filter and before
the backend. This change does not reorder the shared filter chain and does not
replace or merge any `SecurityPolicy`.

`waf.policies[].exclusions` supports only a named CRS rule ID removed for an
exact path prefix, and requires a separate control-rule ID and reason. There
are no initial exclusions because no false positive has been observed. Add an
exclusion only after a captured event and controlled reproduction, for example:

```yaml
exclusions:
  - ruleId: '941100'
    controlRuleId: '1000100'
    pathPrefix: '/verified/callback'
    reason: 'Verified false positive for the documented callback payload shape'
```

Do not remove a CRS family, lower the global anomaly threshold, or exclude an
entire host to fix one endpoint.

## Protocol and application boundaries

- Authentik callbacks and protected routes require explicit login, callback,
  logout, cookie, and authorization tests before selection. WAF attachment
  must not replace their `SecurityPolicy`.
- SMS webhooks may contain sensitive message content. Tune only from redacted
  metadata and never log bodies, tokens, or query strings.
- Harbor, S3 signed requests, and multipart uploads are initially excluded.
  Body buffering, canonicalization, signature preservation, upload size, and
  latency require separate canaries and route-specific limits.
- gRPC is not selected. A later trial must preserve HTTP/2 framing and test
  streaming and trailers rather than claim ordinary HTTP-body coverage.
- A WAF can inspect the HTTP handshake before a WebSocket upgrade when its
  route is selected; it does not inspect WebSocket frames after upgrade.
- TLS terminated by `main-gw` can be inspected. TLS passthrough, including the
  SIPS listeners, remains encrypted to Envoy's HTTP filters. SIP/RTP, raw TCP,
  UDP, and other non-HTTP traffic are outside this WAF.

## Observability and privacy

Coraza 0.6.0 writes serial JSON audit records to Envoy stdout because the Wasm
runtime cannot write a normal audit file. The policy restricts audit parts to
`A`, `H`, and `Z`: transaction metadata, rule/audit messages, and terminator.
It deliberately omits request/response headers and bodies. Keep credentials,
cookies, authorization headers, SMS content, bodies, and sensitive query
strings out of debug/audit settings.

Part `H` and Coraza's rule-error callback can still contain the matched value
or request URI. The isolated log-format check is therefore a hard deployment
gate: use only synthetic non-sensitive values, inspect the exact Envoy-wrapped
record, and add a tested Alloy redaction/drop stage before permitting those
records into Loki if either field is present. If safe redaction cannot retain
the rule metadata, leave Coraza audit logging off and treat privacy-safe event
capture as a blocker; do not ingest the raw record.

Existing Alloy pod-log discovery already collects Envoy containers labeled
`logs=loki-myloginspace` and enriches them with cluster and site metadata for
Loki. That provides the raw collection path without changing the shared
gateway's currently disabled access log. Do not add a Loki parser or Grafana
dashboard until an isolated run captures the exact 0.6.0 JSON envelope as
emitted through Envoy. The parser must extract only verified fields: site,
static target route/host mapping, Coraza transaction or Envoy request ID when
present, rule ID, severity/anomaly score, action, body-processing errors, and
module-load failures. Correlation fields that are absent must remain absent,
not be synthesized.

Log-volume controls are route opt-in, PL1, `RelevantOnly`, audit parts `AHZ`,
and debug level 1. The module receives static `cluster` and `route` metric
labels from Helm values. The module documents `waf_filter_tx_total` and
`waf_filter_tx_interruptions` Envoy statistics, but their availability and
meaning in detection-only mode have not been verified on CoRE's Envoy build;
do not create Mimir alerts until the canary confirms the actual series and
labels.

## Validation and rollout runbook

Repository validation renders the two ApplicationSet value variants. Runtime
checks below must use a controlled canary and must never send attack payloads
to a production application.

1. Mirror the verified upstream digest into each site's existing Harbor GHCR
   [proxy-cache](https://goharbor.io/docs/2.12.0/administration/configure-proxy-cache/)
   or artifact project, verify the copied digest, and update only
   `waf.image.repository` if the mirror URL differs. Do not create a registry.
2. In an isolated cluster with Envoy Gateway v1.9.2 and the production CRD,
   apply the rendered policy and canary route. Require `Accepted=True` and
   `Programmed=True`, then confirm the Envoy Wasm VM loaded the pinned digest.
3. Send benign navigation and LibreSpeed telemetry requests. Record baseline
   and WAF p50/p95 latency, Envoy CPU, memory, and restart count during a soak.
4. Send controlled SQL-injection and XSS test strings only to the canary.
   Detection-only must return the backend response and emit redacted rule IDs,
   severity/anomaly score, action, route/site, and a usable correlation ID if
   the module provides one.
5. In the isolated canary only, set `waf.mode: 'On'`,
   `waf.requestBodyLimitAction: 'Reject'`, and `failOpen: false`.
   Confirm a malicious test receives the configured denial and does not reach
   backend logs. Confirm benign, oversized, partial JSON, streaming, and
   malformed multipart behavior.
6. Exercise module-download failure, invalid configuration, and runtime
   failure. Confirm the documented fail-open behavior and alertable load/error
   logs; restore the valid digest and confirm recovery.
7. Validate representative Authentik callback, webhook, API, upload, S3,
   gRPC, and WebSocket behavior on separate controlled routes before any such
   route is selected. Confirm unselected routes have no Wasm per-route config.
8. Roll back by setting the site's `waf.enabled` to `false` or removing only
   its policy entry, render again, and confirm the `EnvoyExtensionPolicy` is
   removed while the HTTPRoute and SecurityPolicy remain unchanged.

Promotion to blocking requires stable module memory/latency over the agreed
soak, no unexplained inspection errors, reviewed false positives with narrow
exclusions, verified privacy-safe logs and alerts, tested fail semantics, and
application-owner approval. Change one route at a time. Detection-only and
blocking policy entries must never select Authentik, Harbor, S3, webhook,
gRPC, or WebSocket routes by a broad label selector.

## Next phase: CrowdSec temporary bans

[`CrowdSec`](https://docs.crowdsec.net/) and router changes are intentionally
out of scope for this phase.
The next phase starts only after the canary has produced a verified Envoy
access-log and Coraza JSON corpus. Build and test parsers against those exact
records, then replay benign and synthetic events to prove scenario decisions
retain trustworthy source IP, route/host, rule ID, action, score, site, and
correlation fields without ingesting secrets or bodies. Parsing is not yet
verified and is a deployment gate, not a current capability.

Run a site-local CrowdSec decision path in YVR and YXL. Each site must continue
making and enforcing local decisions during an inter-site outage; sharing
signals may enhance detection but cannot be required for ingress availability.
Only the directly observed downstream address is trusted initially. A CDN or
proxy can supply a client address only after its egress CIDRs and header
behavior are explicitly validated and configured; otherwise decisions apply
to the proxy address and risk broad collateral damage.

Start with expiring IPv4 and IPv6 bans scoped to public web ingress. Define
break-glass, monitoring, scanner, and infrastructure allowlists; maximum ban
duration; renewal and expiry behavior; IPv4/IPv6 parity; forwarded-traffic
coverage; and rule ordering before enforcement. Keep SIP/RTP, mail, cluster
management, VPN, and other management traffic outside the initial match. An
optional Envoy bouncer can enforce at HTTP ingress. A VyOS firewall bouncer,
using deliberately placed [firewall groups](https://docs.vyos.io/en/latest/configuration/firewall/groups.html),
is a separate integration that must be validated for address families, stateful
forwarding chains, ordering, atomic membership updates, expiry, restart, and
site outage behavior before it receives decisions.

Ownership must remain split: existing Crossplane/Terraform workspaces manage
persistent VyOS firewall structure, named sets, attachment points, and durable
policy; the runtime bouncer manages only temporary set membership. Provider
reconciliation must neither erase active bans nor import them as permanent
desired state. Bouncer loss must expire entries safely, and persistent policy
rollback must not strand runtime rules. Local bans reduce unwanted traffic
after it reaches the site; they cannot prevent an attacker from saturating the
upstream Internet link.

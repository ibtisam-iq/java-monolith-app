# Trivy Security Scanning — Setup, Multi-Pass Architecture & Troubleshooting

The pipeline started with a basic single-pass Trivy image scan. Over several iterations, I expanded it into a production-grade three-pass architecture — and ran into a series of real CVE failures and pipeline bugs along the way. This document records exactly what I built, what broke, and how I fixed it.

> I used **AI-assisted analysis (Perplexity Pro)** throughout this process — for CVE research, Maven BOM override mechanics, and pipeline debugging. Using the right tool efficiently is itself a DevOps skill.

---

## Phase 1 — Initial Trivy Setup (Single Pass)

At first, I had a single Trivy image scan step in `ci.yml` — no separation of OS vs. library vulnerabilities, no exit-code strategy, no multi-pass logic:

```yaml
- name: Trivy — image scan
  uses: aquasecurity/trivy-action@0.35.0
  with:
    scan-type: image
    image-ref: ${{ env.IMAGE_NAME }}:${{ steps.versioning.outputs.image_tag }}
    severity:  CRITICAL,HIGH
    exit-code: '1'
    format:    table
```

This worked initially because the base image and the application JARs happened to have no CRITICAL findings at that point. The scan passed and the pipeline moved on.

---

## Phase 2 — Multi-Pass Architecture (Why I Redesigned It)

As I added more dependency upgrades to `pom.xml`, CRITICAL CVEs started appearing. I also learned that treating OS-level CVEs (owned by Ubuntu/Canonical) the same as JAR-level CVEs (owned by me) was wrong — failing the build on OS CVEs I cannot fix creates permanent pipeline blockage.

I redesigned the Trivy image scan into **three distinct passes**:

### The Architecture Decision

A Docker image contains two completely different layers of software with different ownership:

| Layer | Examples | Who owns fixing it |
|---|---|---|
| **OS packages** | glibc, openssl, zlib, libcurl | Base image vendor (Canonical for Ubuntu) |
| **Library JARs** | Spring Boot, Tomcat, Hibernate, Jackson | Me — declared in `pom.xml` |

Failing the build on OS CVEs blocks the pipeline indefinitely on issues outside my control. The industry-standard approach (used at Google, Netflix, Shopify) separates these two layers:

### Pass A — OS Packages (warn only)

```yaml
- name: Trivy — image scan OS packages (CRITICAL → warn only)
  uses: aquasecurity/trivy-action@0.35.0
  with:
    scan-type:  image
    image-ref:  ${{ env.IMAGE_NAME }}:${{ steps.versioning.outputs.image_tag }}
    vuln-type:  os
    severity:   CRITICAL,HIGH
    exit-code:  '0'       # never fail — vendor's responsibility
    format:     table
```

`exit-code: '0'` — findings are reported in the log but the build never fails on OS CVEs. Canonical decides if and when to patch these. I have no control over them.

### Pass B — Library JARs (CRITICAL fails the build)

```yaml
- name: Trivy — image scan JAR/library (CRITICAL → fail)
  uses: aquasecurity/trivy-action@0.35.0
  with:
    scan-type:  image
    image-ref:  ${{ env.IMAGE_NAME }}:${{ steps.versioning.outputs.image_tag }}
    vuln-type:  library
    severity:   CRITICAL
    exit-code:  '1'       # fail — these are MY dependencies in pom.xml
    format:     table
```

`exit-code: '1'` — any CRITICAL CVE in application JARs fails the build immediately. These are my dependencies. I own them. Fix = bump version in `pom.xml`.

### Pass C — Full Audit Artifact (all severities, never fails)

```yaml
- name: Trivy — image scan full report (audit artifact)
  uses: aquasecurity/trivy-action@0.35.0
  if: always()
  with:
    scan-type: image
    image-ref: ${{ env.IMAGE_NAME }}:${{ steps.versioning.outputs.image_tag }}
    severity:  CRITICAL,HIGH,MEDIUM,LOW
    exit-code: '0'
    format:    json
    output:    trivy-image-report.json
```

This pass generates a complete JSON report uploaded as a GitHub Actions artifact for security audit trail. It runs with `if: always()` so it is never skipped.

I also added a **filesystem scan** (Pass 0) that runs *before* the Docker build — scanning the repository itself for secrets, misconfigurations, and dependency vulnerabilities in source files before the image is even built.

---

## Phase 3 — CVE Failures After `pom.xml` Update

Once the multi-pass architecture was in place and Pass B had `exit-code: '1'`, the real work began. The pipeline started failing because Trivy was now correctly detecting CRITICAL CVEs in my application JARs.

### CVEs Found and Fixed

After upgrading `pom.xml` (from `pom-modernization.md`) to Spring Boot 3.4.4 and Java 21, Trivy's Pass B reported **7 CRITICAL vulnerabilities** in the built image. All of them were transitive dependencies — libraries I did not declare directly but that the Spring Boot BOM pulled in at specific versions.

#### Understanding the Two Override Mechanisms in Maven

Before fixing the CVEs, I had to understand how to override versions that the Spring Boot BOM controls:

| Mechanism | How it works | When to use |
|---|---|---|
| `<properties>` key override | Maven resolves `<properties>` before the BOM. If the BOM reads a known property key (e.g. `tomcat.version`), your value wins. | When the BOM exposes a documented property key for that library |
| `<dependencyManagement>` block | Entries in your own `pom.xml` always win over the parent BOM — Maven spec guarantee. | When the BOM does NOT expose a property key, or the key is unreliable |

**Critical lesson learned:** Setting `<thymeleaf.version>3.1.4.RELEASE</thymeleaf.version>` in `<properties>` had **no effect** — Spring Boot 3.4.5's BOM does not expose that property key for the Thymeleaf artifacts. The property was silently ignored and the BOM's vulnerable `3.1.3.RELEASE` version won. I had to use `<dependencyManagement>` instead.

#### CVE Fix Table

| Library | BOM-Pinned Version | Fixed Version | CVEs Resolved | Override Method |
|---|---|---|---|---|
| `tomcat-embed-core` | `10.1.39` | `10.1.54` | CVE-2026-29145 (CRITICAL), CVE-2026-34483 (HIGH), CVE-2026-34487 (HIGH) | `<tomcat.version>` in `<properties>` |
| `spring-security-core` | `6.4.4` | `6.5.9` | CVE-2025-41232 (CRITICAL), CVE-2025-41248 (HIGH) | `<spring-security.version>` in `<properties>` |
| `spring-security-web` | `6.4.4` | `6.5.9` | CVE-2026-22732 (CRITICAL) | Same key — both artifacts share `spring-security.version` |
| `thymeleaf` | `3.1.3.RELEASE` | `3.1.4.RELEASE` | CVE-2026-40477 (CRITICAL), CVE-2026-40478 (CRITICAL) | `<dependencyManagement>` block (property key silently ignored) |
| `thymeleaf-spring6` | `3.1.3.RELEASE` | `3.1.4.RELEASE` | CVE-2026-40477 (CRITICAL), CVE-2026-40478 (CRITICAL) | `<dependencyManagement>` block (separate artifact, same fix) |
| `spring-framework` | `6.2.x` | `6.2.17` | CVE-2025-41249, CVE-2025-41234, CVE-2026-22737 | `<spring-framework.version>` in `<properties>` |
| `logback-core` | `1.5.18` | `1.5.19` | CVE-2025-11226 (MEDIUM) | `<logback.version>` in `<properties>` |
| `jackson` (BOM) | `2.18.x` | `2.18.6` | GHSA-72hv-8253-57qq (MEDIUM) | `<jackson-bom.version>` in `<properties>` (NOT `jackson.version`) |

#### Important: Spring Security 6.5.9 — Why Not 6.4.x?

CVE-2026-22732 (CRITICAL) has **no fix in any 6.4.x release**. Trivy explicitly reports: *Fixed Version: 6.5.9, 7.0.4*. The fix was backported only into the 6.5.x and 7.0.x branches. Attempting to bump to any `6.4.x` version would never clear this CVE. Spring Security 6.5.x is fully compatible with Spring Boot 3.4.x — Spring Boot does not lock the Security minor version.

I also upgraded `spring-boot-starter-parent` from `3.4.4` to `3.4.5` as the first step — this resolved the majority of CVEs in a single BOM bump.

---

## Phase 4 — Pipeline Ordering Bug (Trivy Cannot Find the Image)

After fixing the CVEs in `pom.xml`, the pipeline failed again — but this time for a completely different reason:

```
FATAL — unable to find image "mibtisam/bankapp:0.0.1-SNAPSHOT-f7ff8dc-12"
* docker:  No such image
* remote:  MANIFEST_UNKNOWN — unknown tag
```

### Root Cause

The Docker build step used `docker/build-push-action@v6` with `load: true`:

```yaml
- name: Docker Build
  uses: docker/build-push-action@v6
  with:
    push: false
    load: true   # ← loads into Buildx's internal store, NOT the Docker daemon
```

`load: true` with Buildx puts the image into BuildKit's **isolated internal store** — not the standard Docker daemon that the rest of the runner (including Trivy) can query. When Trivy called `docker inspect`, the image did not exist from its perspective. The four backends it tried all failed:

| Backend | Why it failed |
|---|---|
| `docker` | Image in Buildx store, not daemon — `No such image` |
| `containerd` | `permission denied` on socket |
| `podman` | No socket found |
| `remote` (Docker Hub) | Image was never pushed yet — `MANIFEST_UNKNOWN` |

### The Fix

Replace the `build-push-action` local build step with a plain `docker build` command, which puts the image directly into the standard Docker daemon that Trivy queries. After Trivy passes, use `docker push` to push to all registries.

```bash
docker build \
  --tag ${{ env.IMAGE_NAME }}:${{ steps.versioning.outputs.image_tag }} \
  --tag ${{ env.IMAGE_NAME }}:latest \
  --build-arg SERVER_PORT=8000 \
  ${{ env.APP_DIR }}
```

This is a **pipeline ordering fix** — the CVEs were already gone from `pom.xml` at this point. The build was failing because Trivy simply could not see the image it was supposed to scan.

---

## Verification Command

After all fixes, run this to confirm no vulnerable versions remain in the dependency tree:

```bash
mvn dependency:tree | grep -E "tomcat|spring-security|spring-framework|thymeleaf|logback|jackson"
```

Expected output should show the patched versions (`10.1.54`, `6.5.9`, `3.1.4.RELEASE`, etc.) with no old pinned versions appearing anywhere in the tree.

---

## Final State — What Passes Now

| Trivy Pass | Scope | exit-code | Result |
|---|---|---|---|
| Pass 0 (FS scan) | Repository files, secrets, misconfig | `0` | Warn only |
| Pass A (image — OS) | Ubuntu base packages | `0` | Warn only — vendor's responsibility |
| Pass B (image — library, CRITICAL) | Application JARs | `1` | ✅ 0 CRITICAL CVEs — passes |
| Pass B (image — library, HIGH/MEDIUM) | Application JARs | `0` | Warn only |
| Pass C (image — full audit) | All layers, all severities | `0` | JSON artifact uploaded |

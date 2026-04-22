# SonarQube Quality Gate Failure — Deprecated API in SecurityConfig

During the CI pipeline run that followed the `pom.xml` security patch (Spring Security upgraded to `6.5.9`), the SonarQube Quality Gate failed for the first time. The build had been passing Quality Gate on every previous run. This document records what broke, why, and how I fixed it.

> I used **AI-assisted analysis (Perplexity Pro)** to identify the correct Spring Security 6.x replacement API. Using the right tool efficiently is itself a DevOps skill.

---

## What Failed

**SonarQube rule:** `java:S5738` — *"@Deprecated code marked for removal should never be used"*

**File:** `src/main/java/com/example/bankapp/config/SecurityConfig.java`

**Line 44:**

```java
.logoutRequestMatcher(new AntPathRequestMatcher("/logout"))
```

**Quality Gate condition triggered:** 0 new issues allowed on new code → 1 new issue introduced → gate failed.

---

## Why It Appeared Now (Not Before)

`AntPathRequestMatcher` was deprecated in Spring Security 5.8 and annotated `@Deprecated(forRemoval=true)` in Spring Security 6.x. Before the `pom.xml` patch, the project used Spring Security `6.4.4` — the annotation was present but SonarQube's severity assessment placed it below the Quality Gate threshold.

After upgrading to Spring Security `6.5.9`, the `forRemoval=true` flag became more imminent in the release timeline, and SonarQube rule `java:S5738` triggered as a **new issue** on the new code analysis period. Since the Quality Gate was configured to allow 0 new issues, the gate failed.

The important distinction: **my `pom.xml` change did not introduce broken code** — `AntPathRequestMatcher` still functioned correctly. SonarQube flagged it as a maintainability risk because the class is scheduled for removal in a future Spring Security release.

---

## The Fix

### Before (deprecated)

```java
import org.springframework.security.web.util.matcher.AntPathRequestMatcher;

// ...

.logout(logout -> logout
    .invalidateHttpSession(true)
    .clearAuthentication(true)
    .logoutRequestMatcher(new AntPathRequestMatcher("/logout"))   // ← deprecated
    .logoutSuccessUrl("/login?logout")
    .permitAll()
)
```

### After (Spring Security 6.x correct API)

```java
// import removed — AntPathRequestMatcher no longer needed

// ...

.logout(logout -> logout
    .invalidateHttpSession(true)
    .clearAuthentication(true)
    .logoutUrl("/logout")   // ← direct replacement, internally handles the matcher
    .logoutSuccessUrl("/login?logout")
    .permitAll()
)
```

**Two changes made:**
1. Removed the `import org.springframework.security.web.util.matcher.AntPathRequestMatcher` statement — no longer needed anywhere in the file.
2. Replaced `.logoutRequestMatcher(new AntPathRequestMatcher("/logout"))` with `.logoutUrl("/logout")`.

**Behaviour is identical.** `logoutUrl()` is the officially supported API in Spring Security 6.x. It handles the path matcher internally without requiring manual instantiation of `AntPathRequestMatcher`. Both map `GET` and `POST /logout` to the logout processing filter.

---

## Why the Downstream Steps Were Skipped

The Quality Gate failure caused all subsequent steps to show as **skipped (⊘)** in the GitHub Actions run:

| Step | Status | Reason |
|---|---|---|
| SonarQube — Quality Gate check | ❌ Failed | `java:S5738` triggered, exit code 1 |
| Publish JAR to Nexus | ⊘ Skipped | No `if: always()` — skipped after failure |
| Set up Docker Buildx | ⊘ Skipped | Same |
| Docker Build | ⊘ Skipped | Same |
| Trivy — image scan OS | ⊘ Skipped | Same |
| Trivy — image scan JAR (CRITICAL) | ⊘ Skipped | Same |
| Trivy — image scan JAR (HIGH/MED) | ❌ Failed | Has `if: always()` — ran, but image not built so scan failed |

This is standard GitHub Actions behaviour: when a step fails and subsequent steps have no `if: always()` condition, they are automatically skipped. The Quality Gate is intentionally placed before Docker build and Nexus publish — a failed quality check should block artifact creation, not just warn.

---

## Expected Result After Fix

| Stage | Expected |
|---|---|
| SonarQube Analysis | 0 new issues — `java:S5738` resolved |
| Quality Gate | ✅ PASS |
| Publish JAR to Nexus | ✅ runs |
| Docker Build | ✅ runs |
| Trivy image scan Pass B (CRITICAL) | ✅ 0 CRITICAL CVEs |
| Push to Docker Hub / GHCR / Nexus | ✅ all three push |
| Update CD repo | ✅ GitOps handoff completes |

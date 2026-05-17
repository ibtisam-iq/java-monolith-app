# ALB Troubleshooting — AWS Bare-Metal Deployment

During the AWS EC2 bare-metal deployment of this application behind an Application Load Balancer (ALB), two distinct issues surfaced in sequence. Both required diagnosis across multiple layers — infrastructure, application logs, and Spring Security configuration. This document records what each problem was, how it was diagnosed, and what was changed to resolve it.

---

## Issue 1 — ALB Health Checks Failing (Instances Marked `unhealthy`)

### Symptom

After the Auto Scaling Group (ASG) launched EC2 instances and registered them with the target group, the ALB repeatedly marked them as `unhealthy`. The ASG interpreted unhealthy instances as failed launches and entered a replacement loop — terminating instances and launching replacements, which also failed health checks.

```
|  i-0b30ae2882deb7bf0 |  draining   |
|  i-02dc8b14446e9f184 |  unhealthy  |
|  i-00106fa2c4522af1e |  initial    |
|  i-0d2edf3ca7a790144 |  draining   |
```

The cycle continued: `initial` → `unhealthy` → `draining` → terminated → new instance → repeat.

### Diagnosis

The first suspicion was the JAR file on S3 — whether the correct version had been uploaded. The S3 bucket confirmed the file was present:

```bash
aws s3 ls s3://java-monolith-artifacts/
# 2026-05-16 22:43:39   65348022 bankapp-0.0.1-SNAPSHOT.jar
```

To rule out an application startup failure, the unhealthy instance was accessed via SSH through the bastion host, and the systemd service logs were inspected:

```bash
sudo systemctl status bankapp
sudo journalctl -u bankapp -n 80 --no-pager
```

The logs showed the application had started cleanly:

```
Tomcat started on port 8000 (http)
Started BankappApplication in 11.796 seconds
```

Spring Boot, Hibernate, HikariPool, and the MySQL connection had all initialised without error. The application itself was not the problem.

The next step was to test the health endpoint directly from within the instance:

```bash
curl -s -o /dev/null -w "%{http_code}" http://localhost:8000/actuator/health
# 302
```

The endpoint returned `302` — a redirect — instead of `200`. Spring Security was intercepting unauthenticated requests to `/actuator/health` and redirecting them to the login page. The ALB health checker received the redirect, followed it, got an HTML login page, and marked the response as a failed health check.

### Root Cause

`SecurityConfig.java` contained the following rule:

```java
.authorizeHttpRequests(authz -> authz
        .requestMatchers("/register").permitAll()
        .anyRequest().authenticated()   // ← caught /actuator/health
)
```

The `.anyRequest().authenticated()` catch-all intercepted the health endpoint before it had any chance to respond. Spring Security redirected every unauthenticated hit — including the ALB health checker — to `/login`.

### Fix

A `permitAll()` matcher for `/actuator/health` was added **before** the catch-all rule. Spring Security evaluates matchers top-to-bottom and stops at the first match, so ordering is critical:

```java
.authorizeHttpRequests(authz -> authz
        .requestMatchers("/register").permitAll()
        .requestMatchers("/actuator/health").permitAll()   // ← added
        .anyRequest().authenticated()
)
```

**File changed:** `src/main/java/com/example/bankapp/config/SecurityConfig.java`  
**Commit:** `6dc03ed` — *fix: permit /actuator/health for ALB health checks*

After redeploying with the fix, the health endpoint returned `200` and `{"status":"UP"}`. The target group health status transitioned to `healthy` as expected.

---

## Issue 2 — Login Redirect Loop Behind ALB HTTPS

### Symptom

After the health check issue was resolved, the application became reachable at `https://bankapp.ibtisam-iq.com`. However, submitting the login form resulted in an infinite redirect loop — the browser was repeatedly sent back to `/login` without ever reaching the dashboard.

### Diagnosis

The deployment architecture placed the application behind an ALB configured with two listeners:

- Port `80` (HTTP) → redirect to HTTPS (`301`)
- Port `443` (HTTPS) → forward to target group on port `8000` (HTTP)

SSL termination happened at the ALB. The application itself received plain HTTP on port `8000`. This created three compounding problems.

**Problem A — Spring generated `http://` redirects after login.**  
The ALB set `X-Forwarded-Proto: https` on every forwarded request, but without `server.forward-headers-strategy=native`, Spring ignored this header. Spring saw the incoming request as `http://` and issued a post-login redirect to `http://bankapp.ibtisam-iq.com/dashboard`. The browser, enforcing HTTPS, immediately upgraded this to `https://`, which invalidated the session established on the `http://` leg. The result was an infinite loop.

**Problem B — The session cookie lacked the `Secure` flag.**  
Browsers only send cookies marked `Secure` over HTTPS connections. Without this flag, the session cookie set by Spring Security after a successful login was not transmitted on subsequent HTTPS requests. Spring Security saw no session token and treated every request as unauthenticated, redirecting back to `/login`.

**Problem C — No `SameSite` attribute on the session cookie.**  
Modern browsers block cookies without an explicit `SameSite` attribute. Without it, the session cookie risked being silently dropped by the browser on cross-context requests, compounding the session loss described above.

### Fix

Three properties were added to `application.properties`:

```properties
# Trust X-Forwarded-Proto header from ALB so Spring generates https:// redirects
server.forward-headers-strategy=native

# Mark session cookie as Secure — required for HTTPS-only transmission
server.servlet.session.cookie.secure=true

# Set SameSite=Lax — allows cookie on top-level navigations and form POSTs (login)
server.servlet.session.cookie.same-site=lax
```

Additionally, ALB sticky sessions were enabled on the target group to ensure all requests from a given browser session landed on the same EC2 instance, preventing cross-instance session loss caused by the absence of a shared session store:

```bash
aws elbv2 modify-target-group-attributes \
  --target-group-arn $TG_ARN \
  --attributes \
    Key=stickiness.enabled,Value=true \
    Key=stickiness.type,Value=lb_cookie \
    Key=stickiness.lb_cookie.duration_seconds,Value=86400
```

**File changed:** `src/main/resources/application.properties`  
**Commit:** `08fe939` — *fix: resolve HTTPS login redirect loop behind ALB*

After redeploying with these properties, the login form submitted correctly, the session cookie persisted across requests, and the application dashboard loaded as expected over HTTPS.

---

## Summary of Changes

| Issue | Root Cause | File Changed | Fix |
|---|---|---|---|
| ALB health checks failing | Spring Security blocked `/actuator/health` with a `302` redirect | `SecurityConfig.java` | Added `.requestMatchers("/actuator/health").permitAll()` before the `anyRequest()` catch-all |
| Login redirect loop | ALB SSL termination caused Spring to generate `http://` redirects; session cookie had no `Secure` or `SameSite` attribute | `application.properties` | Added `forward-headers-strategy=native`, `cookie.secure=true`, `cookie.same-site=lax`; enabled ALB sticky sessions |

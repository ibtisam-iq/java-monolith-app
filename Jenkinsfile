// ============================================================
// DevSecOps CI Pipeline — Java Monolith (BankApp)
// Tool: Jenkins Declarative Pipeline
// Stack: Maven 3.9 · Java 21 · SonarQube · Trivy · Nexus · Docker Hub · GHCR · ECR
// Credentials: sonarqube-token · github-creds · docker-creds · nexus-creds · ghcr-creds
// SonarQube server: sonar-server  |  Scanner: sonar-scanner
// Maven settings:   maven-settings (Config File Provider)
//
// ── REQUIRED JENKINS PLUGINS ──────────────────────────────────────────────────
// The following plugins MUST be installed for this pipeline to work:
//   - Pipeline Maven Integration Plugin  → provides withMaven() DSL
//     used in Build & Test, SonarQube Analysis, and Publish JAR.
//     Without it, those stages fail with "No such DSL method withMaven".
//   - SonarQube Scanner Plugin           → provides withSonarQubeEnv()
//   - Coverage Plugin                    → provides recordCoverage() DSL
//   - AnsiColor Plugin                   → provides ansiColor() option
//   - Config File Provider Plugin        → provides globalMavenSettingsConfig
// ──────────────────────────────────────────────────────────────────────────────
//
// ── MIGRATION NOTE ────────────────────────────────────────────────────────────
// This Jenkinsfile was originally authored inside a separate pipeline repository:
//
//   Repo:        ibtisam-iq/devsecops-pipelines
//   Script Path: pipelines/java-monolith/jenkins/Jenkinsfile
//
// It has been moved into the application source repository:
//
//   Repo:        ibtisam-iq/java-monolith-app
//   Script Path: Jenkinsfile   (repo root)
//
// Changes made during migration:
//   1. APP_DIR — updated (see environment block below)
//   2. Checkout stage — updated (see Stage 1 below)
//   3. Everything else is identical to the original.
// ──────────────────────────────────────────────────────────────────────────────

pipeline {

    // FIX #13 — was `agent any` which allows the pipeline to land on Windows
    // agents (if ever added), causing sh/trivy/docker failures.
    // `built-in || linux` restricts to the built-in node or any agent labeled
    // `linux`, ensuring shell-based steps always run on a Linux host.
    agent { label 'built-in || linux' }

    // ── tools block is for tools registered in Manage Jenkins → Tools ONLY.
    // JDK 21, Maven, Docker, Trivy, kubectl, Helm, Terraform, Ansible, AWS CLI
    // are all installed system-wide on the Jenkins OS via install-pipeline-tools
    // and are available on the OS PATH — Jenkins resolves them automatically
    // through shell without any UI registration.
    //
    // The ONLY tool registered in Manage Jenkins → Tools is sonar-scanner
    // (SonarQube Scanner), because it cannot be installed as a plain binary.
    // It is managed exclusively through Jenkins and does not go in the tools block
    // — it is injected via withSonarQubeEnv() instead.
    //
    // tools {
    //     jdk 'jdk-21'    // NOT needed — JDK 21 is on OS PATH via install-pipeline-tools
    // }

    // ── Environment variables available to every stage
    environment {
        // ── App metadata
        APP_NAME       = 'java-monolith'
        // APP_VERSION is intentionally NOT defined here.
        // It is computed dynamically in the Versioning stage via:
        //   mvn help:evaluate -Dexpression=project.version -q -DforceStdout
        // This ensures IMAGE_TAG always reflects the actual pom.xml version
        // and never drifts when the version is bumped (e.g. SNAPSHOT → RELEASE).
        //
        // GROUP_ID was removed — it was declared here but never referenced
        // anywhere in the pipeline (dead variable). Removing eliminates
        // confusion about whether it serves a purpose.

        // ── Docker Hub image
        DOCKER_USER    = 'mibtisam'
        IMAGE_NAME     = "${DOCKER_USER}/${APP_NAME}"
        // IMAGE_TAG is set dynamically in the Versioning stage below

        // ── GitHub Container Registry (ghcr.io)
        GHCR_USER      = 'ibtisam-iq'
        GHCR_IMAGE     = "ghcr.io/${GHCR_USER}/${APP_NAME}"

        // ── AWS ECR  [uncomment all four lines once ECR repo is provisioned]
        // AWS_REGION     = 'us-east-1'
        // AWS_ACCOUNT_ID = '123456789012'
        // ECR_REGISTRY   = "${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com"
        // ECR_IMAGE      = "${ECR_REGISTRY}/${APP_NAME}"

        // ── Nexus Registry — path-based routing (no dedicated Docker port needed)
        // Image format: nexus.ibtisam-iq.com/docker-hosted/java-monolith:<tag>
        // Nexus repo must be created with "Path based routing" selected (not port-based).
        // Docker Bearer Token Realm must be active in Security → Realms.
        //
        // NEXUS_URL purpose: Nexus web UI link only — used in the success {} echo
        // so the console output shows a clickable URL to the Nexus UI.
        // It is NOT used for docker login or docker push (those use NEXUS_DOCKER,
        // which is the bare hostname without https:// as required by the Docker CLI).
        NEXUS_URL         = 'https://nexus.ibtisam-iq.com'
        NEXUS_DOCKER      = 'nexus.ibtisam-iq.com'       // host for docker login
        NEXUS_DOCKER_REPO = 'docker-hosted'              // repo name segment in URL path

        // ── Source directory
        //
        // PREVIOUS (when this file lived in ibtisam-iq/devsecops-pipelines):
        //   APP_DIR = 'pipelines/java-monolith/app'
        //   Jenkins checked out the pipelines repo with submodules; the app
        //   source code was mounted at pipelines/java-monolith/app/ via Git submodule.
        //
        // CURRENT (now that this file lives in ibtisam-iq/java-monolith-app):
        //   APP_DIR = '.'
        //   Jenkins checks out this repo directly; the source code is at the
        //   workspace root, so all dir(APP_DIR) blocks resolve to '.'.
        //   No submodule setup is needed.
        //
        // APP_DIR = 'pipelines/java-monolith/app'   // ← original path (devsecops-pipelines repo)
        APP_DIR        = '.'                          // ← current path  (java-monolith-app repo root)
    }

    options {
        // numToKeepStr: keep last 10 build logs.
        // artifactNumToKeepStr: keep artifacts (Trivy JSON reports) for only
        // the last 5 builds. Without this, archiveArtifacts accumulates
        // trivy-fs-report.json and trivy-image-report.json from every build
        // indefinitely on the Jenkins master disk.
        buildDiscarder(logRotator(numToKeepStr: '10', artifactNumToKeepStr: '5'))

        // 60 minutes — accommodates cold starts on the self-hosted server
        // (jenkins.ibtisam-iq.com) where the Trivy DB may not yet be cached
        // and the Maven local repo may be empty. With --cache-dir /var/cache/trivy,
        // warm builds complete well within this limit.
        timeout(time: 60, unit: 'MINUTES')

        // abortPrevious: true is explicit — without it, behavior is Jenkins
        // Pipeline Plugin version-dependent: older versions queue the waiting
        // build, newer versions (Pipeline: Groovy 2794+ / LTS 2.387+) abort it.
        // Being explicit locks the intended behavior across Jenkins LTS upgrades.
        disableConcurrentBuilds(abortPrevious: true)

        timestamps()
        ansiColor('xterm')
    }

    stages {

        // ────────────────────────────────────────────────────────────────────
        // STAGE 1 — Checkout
        //
        // Uses `checkout scm` — Jenkins injects the exact SCM object
        // (branch, commit SHA, credentials) from the pipeline job
        // configuration that triggered this build.
        //
        // Why checkout scm instead of manual checkout([$class: 'GitSCM', ...]):
        //   - No hardcoded branch name (*/main) — follows whatever branch
        //     triggered the build, making branch-based when{} guards work.
        //   - Guarantees GIT_COMMIT and GIT_BRANCH env vars match the
        //     exact triggering commit — critical for the OCI revision label
        //     in Stage 8 (Docker Build) and the image tag in Stage 3.
        //   - Avoids a redundant second full clone of the repo.
        //
        // PREVIOUS manual form (kept for reference):
        //   checkout([
        //       $class: 'GitSCM',
        //       branches: [[name: '*/main']],
        //       extensions: [],
        //       userRemoteConfigs: [[
        //           url: 'https://github.com/ibtisam-iq/java-monolith-app.git',
        //           credentialsId: 'github-creds'
        //       ]]
        //   ])
        // ────────────────────────────────────────────────────────────────────
        stage('Checkout') {
            steps {
                echo '📥 Checking out source...'
                checkout scm
            }
        }

        // ────────────────────────────────────────────────────────────────────
        // STAGE 2 — Trivy Filesystem Scan
        // Scans the checked-out source tree for:
        //   - Hardcoded secrets (passwords, tokens, keys)
        //   - Known CVEs in dependency files (pom.xml, etc.)
        //   - Misconfigurations in Dockerfile, compose.yml
        //
        // Runs BEFORE build — fail-fast before wasting build time.
        //
        // TRIVY SCANNER NAME:
        //   --scanners secret,vuln,misconfig requires Trivy ≥ v0.38.0
        //   (released 2023-03). In older versions the flag was `config`.
        //   Verify your installed version: trivy --version
        //   If < v0.38.0, replace `misconfig` with `config`.
        //
        // TRIVY CACHE:
        //   --cache-dir /var/cache/trivy persists the vulnerability DB
        //   across builds. Create once on the Jenkins host: mkdir -p /var/cache/trivy
        //
        // --skip-dirs .git — excluded to avoid:
        //   (a) False positives: Trivy's secret scanner finds base64-encoded
        //       tokens in git pack files and commit history.
        //   (b) Slow scans: .git/ can be large; scanning it adds time with
        //       zero value — we care about source files, not git internals.
        //
        // TWO-PASS STRATEGY:
        //   Pass 1 — CRITICAL only, --exit-code 1 (NO || true)
        //            → pipeline FAILS if any CRITICAL finding exists.
        //              || true would silently swallow the failure — never add it.
        //   Pass 2 — HIGH,MEDIUM only, --exit-code 0
        //            → advisory only, printed to console as a table.
        //            NOTE: LOW is intentionally excluded from the filesystem scan.
        //            LOW-severity source-tree findings are noise (minor dep advisories,
        //            informational config hints) that produce alert fatigue without
        //            actionable remediation. LOW IS included in the image scan
        //            (Stage 9) because container LOW CVEs can affect runtime
        //            attack surface in ways source-tree linting does not.
        //
        // FIX #5 — archiveArtifacts path is the bare filename, NOT "${APP_DIR}/..."
        //   With APP_DIR='.', "${APP_DIR}/trivy-fs-report.json" expands to
        //   "./trivy-fs-report.json". Jenkins stores the artifact under that
        //   literal path (with leading "./"), breaking REST API access via
        //   curl .../artifact/trivy-fs-report.json. The dir(APP_DIR) block
        //   already sets the working directory — the filename alone is correct.
        // ────────────────────────────────────────────────────────────────────
        stage('Trivy Filesystem Scan') {
            steps {
                dir(APP_DIR) {
                    echo '🔎 Running Trivy filesystem scan on source tree...'
                    sh """
                        trivy fs \\
                            --cache-dir /var/cache/trivy \\
                            --skip-dirs .git \\
                            --scanners secret,vuln,misconfig \\
                            --exit-code 1 \\
                            --severity CRITICAL \\
                            --no-progress \\
                            --format json \\
                            --output trivy-fs-report.json \\
                            .

                        trivy fs \\
                            --cache-dir /var/cache/trivy \\
                            --skip-dirs .git \\
                            --scanners secret,vuln,misconfig \\
                            --exit-code 0 \\
                            --severity HIGH,MEDIUM \\
                            --no-progress \\
                            --format table \\
                            .
                    """
                    // FIX #5 — bare filename; dir(APP_DIR) already set CWD correctly.
                    archiveArtifacts artifacts: 'trivy-fs-report.json', allowEmptyArchive: true
                }
            }
        }

        // ────────────────────────────────────────────────────────────────────
        // STAGE 3 — Versioning
        // Build a unique, traceable image tag:
        //   <pom-version>-<short-git-sha>-<build-number>
        // e.g.  0.0.1-SNAPSHOT-ab3f12c-42
        //
        // FIX #12 — mvn help:evaluate is now run WITHOUT withMaven.
        //   withMaven activates ALL Maven event publishers (JUnit, JaCoCo,
        //   Surefire) for every Maven invocation it wraps. Wrapping a simple
        //   help:evaluate goal opens file handles and registers publishers
        //   for an execution that produces no test output — wasteful.
        //   help:evaluate only reads the POM version; it does not resolve
        //   parent POM artifacts at runtime, so Nexus credentials are not
        //   needed. The -s flag passes the managed settings file directly
        //   to supply any mirror/proxy config without activating publishers.
        //   If your parent POM is hosted in Nexus and requires auth to
        //   resolve, add nexus credentials to the settings file referenced
        //   by MAVEN_SETTINGS, or re-wrap with withMaven and accept the
        //   minor publisher overhead.
        //
        // FIX #7 — git rev-parse uses -C ${WORKSPACE} to always resolve the
        //   SHA from the workspace root, not the current dir(APP_DIR) CWD.
        //   If APP_DIR is ever a git submodule, rev-parse without -C would
        //   return the submodule's SHA — producing a misleading image tag
        //   that cannot be traced back to the parent repo commit.
        //
        // EMPTY VERSION GUARD:
        //   If mvn help:evaluate returns a blank string (e.g. due to a
        //   network failure resolving settings, or a mis-configured pom.xml),
        //   IMAGE_TAG would become "-ab3f12c-42" — valid Docker syntax but
        //   meaningless. error() aborts immediately with a clear message.
        // ────────────────────────────────────────────────────────────────────
        stage('Versioning') {
            steps {
                dir(APP_DIR) {
                    script {
                        // FIX #12 — no withMaven wrapper; pass settings directly with -s.
                        // configFileProvider is used to resolve the managed settings file
                        // path so Nexus mirror/proxy config is still honoured if needed.
                        def appVersion = ''
                        configFileProvider([configFile(fileId: 'maven-settings', variable: 'MAVEN_SETTINGS')]) {
                            appVersion = sh(
                                script: 'mvn help:evaluate -Dexpression=project.version -q -DforceStdout -s ${MAVEN_SETTINGS}',
                                returnStdout: true
                            ).trim()
                        }

                        if (!appVersion || appVersion.isEmpty()) {
                            error("❌ mvn help:evaluate returned an empty version string. " +
                                  "Check pom.xml <version> and Nexus connectivity. " +
                                  "IMAGE_TAG cannot be built without a valid version.")
                        }

                        // FIX #7 — -C ${WORKSPACE} guarantees we read the parent repo SHA,
                        // not a submodule SHA, regardless of what APP_DIR resolves to.
                        def shortSha  = sh(script: 'git -C ${WORKSPACE} rev-parse --short HEAD', returnStdout: true).trim()
                        env.IMAGE_TAG = "${appVersion}-${shortSha}-${BUILD_NUMBER}"
                        echo "🏷️  Image tag: ${IMAGE_TAG}"
                    }
                }
            }
        }

        // ────────────────────────────────────────────────────────────────────
        // STAGE 4 — Build & Test
        // withMaven injects the managed settings.xml (maven-settings)
        // so Nexus credentials never appear in source code.
        // JaCoCo runs automatically during the test phase
        // because it is bound to prepare-agent + report goals in pom.xml.
        //
        // NOTE: junit and recordCoverage publishers live in post { always }
        // guarded by a fileExists check — see post block below.
        // ────────────────────────────────────────────────────────────────────
        stage('Build & Test') {
            steps {
                dir(APP_DIR) {
                    echo '🔨 Compiling and running unit tests...'
                    withMaven(globalMavenSettingsConfig: 'maven-settings') {
                        sh 'mvn clean verify -B --no-transfer-progress'
                    }
                }
            }
        }

        // ────────────────────────────────────────────────────────────────────
        // STAGE 5 — SonarQube Analysis
        // withSonarQubeEnv injects SONAR_HOST_URL and the
        // sonarqube-token automatically — no hardcoding.
        //
        // FIX #4 — JaCoCo path normalized to ${WORKSPACE}/target/... directly.
        //   Previously: ${WORKSPACE}/${APP_DIR}/target/site/jacoco/jacoco.xml
        //   With APP_DIR='.', that expanded to WORKSPACE/./target/... which is
        //   valid POSIX but SonarQube Scanner 4.x uses Java's new File(path)
        //   internally and does NOT normalize "./" — the scanner looks for the
        //   literal string "./target/..." and silently drops coverage data.
        //   Fix: construct the path without APP_DIR. If APP_DIR ever changes
        //   from '.', update JACOCO_PATH to: ${WORKSPACE}/${APP_DIR}/target/...
        //   and verify your SonarQube scanner version normalizes the path.
        // ────────────────────────────────────────────────────────────────────
        stage('SonarQube Analysis') {
            steps {
                dir(APP_DIR) {
                    echo '🔍 Running SonarQube static analysis...'
                    withSonarQubeEnv('sonar-server') {
                        withMaven(globalMavenSettingsConfig: 'maven-settings') {
                            sh """
                                JACOCO_PATH="${WORKSPACE}/target/site/jacoco/jacoco.xml"
                                mvn sonar:sonar \\
                                    -Dsonar.projectKey=IbtisamIQbankapp \\
                                    -Dsonar.projectName=IbtisamIQbankapp \\
                                    -Dsonar.java.binaries=target/classes \\
                                    -Dsonar.coverage.jacoco.xmlReportPaths="\${JACOCO_PATH}" \\
                                    -B --no-transfer-progress
                            """
                        }
                    }
                }
            }
        }

        // ────────────────────────────────────────────────────────────────────
        // STAGE 6 — Quality Gate
        // Blocks the pipeline until SonarQube webhook fires
        // back to Jenkins with pass/fail result.
        // abortPipeline: true → fails the build on gate failure.
        // ────────────────────────────────────────────────────────────────────
        stage('Quality Gate') {
            steps {
                echo '🚦 Waiting for SonarQube Quality Gate...'
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        // ────────────────────────────────────────────────────────────────────
        // STAGE 7 — Publish JAR to Nexus
        // Pushes the built SNAPSHOT JAR to:
        //   https://nexus.ibtisam-iq.com/repository/maven-snapshots/
        // The server IDs (maven-releases / maven-snapshots) in
        // settings.xml match the <distributionManagement> in pom.xml.
        //
        // ARCHITECTURAL NOTE — JAR vs Docker build dependency:
        //   The JAR deployed here (Stage 7) is the same artifact built in
        //   Stage 4. The Docker multi-stage build (Stage 8) re-runs Maven
        //   internally inside the builder container. On a single agent with
        //   a shared .m2 cache, the Docker build reuses local cache — fine.
        //   On distributed/containerized agents with isolated Maven caches,
        //   the Docker build would pull the freshly-deployed SNAPSHOT from
        //   Nexus. This is correct behavior (Docker image = Nexus-verified
        //   artifact) but creates a build-time dependency on Nexus. Keep
        //   this in mind when moving to ephemeral build agents.
        // ────────────────────────────────────────────────────────────────────
        stage('Publish JAR to Nexus') {
            steps {
                dir(APP_DIR) {
                    echo '📦 Deploying JAR artifact to Nexus...'
                    withMaven(globalMavenSettingsConfig: 'maven-settings') {
                        sh 'mvn deploy -DskipTests -B --no-transfer-progress'
                    }
                }
            }
        }

        // ────────────────────────────────────────────────────────────────────
        // STAGE 8 — Docker Build
        // Builds the multi-stage image defined in the app's own Dockerfile:
        //   Stage 1 (builder): maven:3.9-temurin-21-alpine
        //   Stage 2 (runtime): eclipse-temurin:21-jre-jammy
        //
        // Tags the image for ALL registries in one build pass:
        //   - Docker Hub : mibtisam/java-monolith:<tag>
        //   - GHCR       : ghcr.io/ibtisam-iq/java-monolith:<tag>
        //   - ECR        : <account>.dkr.ecr.<region>.amazonaws.com/java-monolith:<tag>
        // Building once and tagging avoids rebuilding per registry.
        //
        // FIX #6 — added --pull flag.
        //   Without --pull, Docker uses whatever version of the base images
        //   (maven:3.9-temurin-21-alpine, eclipse-temurin:21-jre-jammy) is
        //   in the local daemon cache — potentially months old with known CVEs
        //   that Trivy (Stage 9) would immediately catch. In a DevSecOps
        //   pipeline where Trivy exists specifically to catch CVEs, building
        //   with stale base images defeats the purpose. --pull forces Docker
        //   to check the registry for a newer digest; it only downloads new
        //   layers if the digest changed — overhead is minimal.
        //
        // GIT_COMMIT is guaranteed to be the triggering commit SHA
        // because Stage 1 uses `checkout scm`.
        // ────────────────────────────────────────────────────────────────────
        stage('Docker Build') {
            steps {
                dir(APP_DIR) {
                    echo "🐳 Building Docker image: ${IMAGE_NAME}:${IMAGE_TAG}"
                    sh """
                        docker build --pull \\
                            --build-arg SERVER_PORT=8000 \\
                            --label "org.opencontainers.image.version=${IMAGE_TAG}" \\
                            --label "org.opencontainers.image.revision=${GIT_COMMIT}" \\
                            --label "org.opencontainers.image.created=\$(date -u +%Y-%m-%dT%H:%M:%SZ)" \\
                            -t ${IMAGE_NAME}:${IMAGE_TAG} \\
                            -t ${IMAGE_NAME}:latest \\
                            -t ${GHCR_IMAGE}:${IMAGE_TAG} \\
                            -t ${GHCR_IMAGE}:latest \\
                            .

                        # Uncomment once ECR variables above are set:
                        # docker tag ${IMAGE_NAME}:${IMAGE_TAG} \${ECR_IMAGE}:${IMAGE_TAG}
                        # docker tag ${IMAGE_NAME}:latest       \${ECR_IMAGE}:latest
                    """
                }
            }
        }

        // ────────────────────────────────────────────────────────────────────
        // STAGE 9 — Trivy Image Scan
        // Scans the freshly built image for CVEs BEFORE pushing to any
        // registry — fail-fast principle.
        //
        // TWO-PASS STRATEGY (same rationale as Stage 2):
        //   Pass 1 — CRITICAL only, --exit-code 1 (NO || true)
        //   Pass 2 — HIGH,MEDIUM,LOW, --exit-code 0 (advisory)
        //            NOTE: LOW is intentionally INCLUDED here (unlike Stage 2).
        //            Container LOW CVEs can affect runtime attack surface in
        //            ways source-tree scanning does not capture. Stage 2
        //            omits LOW because source-tree LOW findings are noise;
        //            image LOW findings are worth surfacing for review.
        //
        // FIX #5 — archiveArtifacts uses bare filename (same fix as Stage 2).
        // ────────────────────────────────────────────────────────────────────
        stage('Trivy Image Scan') {
            steps {
                dir(APP_DIR) {
                    echo "🛡️  Scanning image with Trivy: ${IMAGE_NAME}:${IMAGE_TAG}"
                    sh """
                        trivy image \\
                            --cache-dir /var/cache/trivy \\
                            --exit-code 1 \\
                            --severity CRITICAL \\
                            --no-progress \\
                            --format json \\
                            --output trivy-image-report.json \\
                            ${IMAGE_NAME}:${IMAGE_TAG}

                        trivy image \\
                            --cache-dir /var/cache/trivy \\
                            --exit-code 0 \\
                            --severity HIGH,MEDIUM,LOW \\
                            --no-progress \\
                            --format table \\
                            ${IMAGE_NAME}:${IMAGE_TAG}
                    """
                    // FIX #5 — bare filename; dir(APP_DIR) already set CWD correctly.
                    archiveArtifacts artifacts: 'trivy-image-report.json', allowEmptyArchive: true
                }
            }
        }

        // ────────────────────────────────────────────────────────────────────
        // STAGE 10–14 — Publish (main branch only)
        //
        // WHY expression{} INSTEAD OF when { branch 'main' }:
        //   The branch{} directive requires a Multibranch Pipeline job, which
        //   injects the BRANCH_NAME variable. On a standard Pipeline job (the
        //   most common type on self-hosted Jenkins), BRANCH_NAME is never set
        //   and branch{} silently evaluates to false — skipping every publish
        //   with no error message, on every build, forever.
        //
        // WHY env.GIT_BRANCH AND NOT BRANCH_NAME:
        //   checkout scm always sets GIT_BRANCH on standard Pipeline jobs.
        //   On standard jobs it takes the form "origin/main" (with remote prefix).
        //   On Multibranch Pipeline jobs it is typically just "main".
        //
        // WHY THE NULL GUARD (env.GIT_BRANCH != null):
        //   When a build is triggered via the Jenkins REST API without SCM
        //   parameters, GIT_BRANCH may not be populated — env.GIT_BRANCH is
        //   null in Groovy. Calling null ==~ /regex/ throws NPE, crashing
        //   the when{} evaluation. The null guard short-circuits before the
        //   regex is evaluated.
        //
        // WHY THE ANCHORED REGEX ^(origin\/)?main$:
        //   Matches ONLY "origin/main" (standard Pipeline) or "main"
        //   (Multibranch). Prevents feature/fix-main-bug from triggering
        //   pushes to all registries.
        // ────────────────────────────────────────────────────────────────────
        stage('Publish') {
            when {
                expression {
                    env.GIT_BRANCH != null &&
                    (env.GIT_BRANCH ==~ /^(origin\/)?main$/)
                }
            }
            stages {

                // ────────────────────────────────────────────────────────────
                // STAGE 10 — Push to Docker Hub
                //
                // docker logout registry-1.docker.io — explicit registry
                // argument is required. Bare `docker logout` (no args) logs
                // out of docker.io AND clears the entire ~/.docker/config.json
                // on some Docker Engine versions, wiping credentials for all
                // other registries (GHCR, Nexus, ECR) currently held on the agent.
                // ────────────────────────────────────────────────────────────
                stage('Push to Docker Hub') {
                    steps {
                        echo "🚀 Pushing image to Docker Hub: ${IMAGE_NAME}"
                        withCredentials([usernamePassword(
                            credentialsId: 'docker-creds',
                            usernameVariable: 'DOCKER_USERNAME',
                            passwordVariable: 'DOCKER_PASSWORD'
                        )]) {
                            sh """
                                echo "\${DOCKER_PASSWORD}" | docker login -u "\${DOCKER_USERNAME}" --password-stdin
                                docker push ${IMAGE_NAME}:${IMAGE_TAG}
                                docker push ${IMAGE_NAME}:latest
                                docker logout registry-1.docker.io
                            """
                        }
                    }
                }

                // ────────────────────────────────────────────────────────────
                // STAGE 11 — Push to GitHub Container Registry (GHCR)
                // ghcr.io/ibtisam-iq/java-monolith:<tag>
                //
                // Credential setup in Jenkins:
                //   Kind:     Username with password
                //   Username: ibtisam-iq
                //   Password: GitHub PAT with scopes: write:packages, read:packages
                //   ID:       ghcr-creds
                //
                // NOTE: You can reuse github-creds if your existing PAT
                // already has write:packages scope. If so, replace
                // 'ghcr-creds' with 'github-creds' below.
                // ────────────────────────────────────────────────────────────
                stage('Push to GHCR') {
                    steps {
                        echo "🐙 Pushing image to GitHub Container Registry: ${GHCR_IMAGE}"
                        withCredentials([usernamePassword(
                            credentialsId: 'ghcr-creds',
                            usernameVariable: 'GHCR_USERNAME',
                            passwordVariable: 'GHCR_TOKEN'
                        )]) {
                            sh """
                                echo "\${GHCR_TOKEN}" | docker login ghcr.io -u "\${GHCR_USERNAME}" --password-stdin
                                docker push ${GHCR_IMAGE}:${IMAGE_TAG}
                                docker push ${GHCR_IMAGE}:latest
                                docker logout ghcr.io
                            """
                        }
                    }
                }

                // ────────────────────────────────────────────────────────────
                // STAGE 12 — Push to Nexus Docker Registry
                // Uses path-based routing — no dedicated Docker port needed.
                // Image URL: nexus.ibtisam-iq.com/docker-hosted/java-monolith:<tag>
                //
                // Pre-requisites in Nexus UI:
                //   1. Create hosted Docker repo with "Path based routing" selected
                //   2. Security → Realms → enable "Docker Bearer Token Realm"
                // ────────────────────────────────────────────────────────────
                stage('Push to Nexus Registry') {
                    steps {
                        echo "📤 Pushing image to Nexus Docker registry (path-based)..."
                        withCredentials([usernamePassword(
                            credentialsId: 'nexus-creds',
                            usernameVariable: 'NEXUS_USER',
                            passwordVariable: 'NEXUS_PASS'
                        )]) {
                            sh """
                                echo "\${NEXUS_PASS}" | docker login ${NEXUS_DOCKER} -u "\${NEXUS_USER}" --password-stdin
                                docker tag ${IMAGE_NAME}:${IMAGE_TAG} ${NEXUS_DOCKER}/${NEXUS_DOCKER_REPO}/${APP_NAME}:${IMAGE_TAG}
                                docker tag ${IMAGE_NAME}:latest       ${NEXUS_DOCKER}/${NEXUS_DOCKER_REPO}/${APP_NAME}:latest
                                docker push ${NEXUS_DOCKER}/${NEXUS_DOCKER_REPO}/${APP_NAME}:${IMAGE_TAG}
                                docker push ${NEXUS_DOCKER}/${NEXUS_DOCKER_REPO}/${APP_NAME}:latest
                                docker logout ${NEXUS_DOCKER}
                            """
                        }
                    }
                }

                // ────────────────────────────────────────────────────────────
                // STAGE 13 — Push to AWS ECR  [COMMENTED OUT]
                // Uncomment and configure once AWS credentials and
                // ECR repository are provisioned.
                //
                // Pre-requisites:
                //   1. Create ECR repo:
                //        aws ecr create-repository --repository-name java-monolith --region us-east-1
                //   2. Add AWS credentials to Jenkins (CloudBees AWS Credentials plugin)
                //        ID: aws-creds
                //   3. Set the four ECR variables in environment {} above.
                //   4. Uncomment docker tag lines in Stage 8 above.
                //   5. Uncomment this entire stage.
                // ────────────────────────────────────────────────────────────
                // stage('Push to AWS ECR') {
                //     steps {
                //         echo "☁️  Pushing image to AWS ECR: ${ECR_IMAGE}"
                //         withCredentials([[
                //             $class:            'AmazonWebServicesCredentialsBinding',
                //             credentialsId:     'aws-creds',
                //             accessKeyVariable: 'AWS_ACCESS_KEY_ID',
                //             secretKeyVariable: 'AWS_SECRET_ACCESS_KEY'
                //         ]]) {
                //             sh """
                //                 aws ecr get-login-password --region ${AWS_REGION} \
                //                     | docker login --username AWS --password-stdin ${ECR_REGISTRY}
                //                 docker push ${ECR_IMAGE}:${IMAGE_TAG}
                //                 docker push ${ECR_IMAGE}:latest
                //                 docker logout ${ECR_REGISTRY}
                //             """
                //         }
                //     }
                // }

                // ────────────────────────────────────────────────────────────
                // STAGE 14 — Update Image Tag in CD Repo
                // CI → CD Handoff: commits the new image tag into
                // platform-engineering-systems so ArgoCD detects the change
                // and triggers a rolling deployment.
                //
                // ── CREDENTIAL SECURITY FLOW ─────────────────────────────
                //   Step 0: IMAGE_TAG guard — abort if empty (see below).
                //   Step 1: Clone using token-in-URL (only way git CLI supports
                //           auth for a one-shot HTTPS clone without SSH keys).
                //   Step 2: IMMEDIATELY clear the token-bearing URL from
                //           .git/config after clone — prevents token leaking
                //           via `git remote -v` or accident debug output.
                //   Step 3: Restore the BARE HTTPS URL (no credentials) as
                //           the new origin. Required by the credential helper.
                //   Step 4: Push via git credential helper — credentials fed
                //           via stdin at push time only, never stored in files.
                //
                // ── GROOVY vs SHELL INTERPOLATION (CRITICAL) ─────────────
                //   Inside """...""", Groovy interpolates ${VAR} at PARSE TIME.
                //   Variables injected by withCredentials (GIT_USER, GIT_TOKEN)
                //   exist only in the SHELL environment — not in Groovy scope.
                //   Escape rule: \${VAR} → Groovy passes through → shell expands.
                //   This applies to GIT_USER, GIT_TOKEN, and IMAGE_TAG (see below).
                //
                // ── IMAGE_TAG GUARD ───────────────────────────────────────
                //   FIX #1 — both echo and git commit message now use \${IMAGE_TAG}
                //   (escaped) so the SHELL evaluates them at runtime — consistent
                //   with the guard above and the documented rule in this header.
                //   If IMAGE_TAG is somehow null (Stage 3 never ran), Groovy
                //   would render unescaped ${IMAGE_TAG} as the 4-char string
                //   "null" — ArgoCD would deploy image tag "null". Escaping
                //   ensures the shell guard catches it first and exits 1.
                //
                // ── FIX #9 — cd-repo renamed to _cd_repo_tmp ─────────────
                //   If a directory named 'cd-repo' is ever added to the app
                //   source, rm -rf cd-repo would silently delete it from the
                //   workspace. The _cd_repo_tmp prefix is distinct enough to
                //   never collide with real application source directories.
                //
                // ── FIX #2 — git push origin HEAD ────────────────────────
                //   Was: git push origin main (hardcoded branch name).
                //   If the CD repo's default branch is ever renamed, the push
                //   fails with "src refspec main does not match any".
                //   HEAD always refers to the currently checked-out branch,
                //   making the push resilient to branch renames.
                //
                // ── FIX #3 — git diff --cached --quiet guard ─────────────
                //   Was: git commit -m "..." || echo "Nothing to commit"
                //   || echo swallows ALL non-zero git commit exits — including
                //   detached HEAD, merge conflicts, broken .git/config — not
                //   just "nothing to commit". A merge conflict would then
                //   surface as a confusing non-fast-forward push error.
                //   git diff --cached --quiet exits 0 if nothing staged,
                //   1 if there are staged changes. This precisely isolates
                //   "nothing staged" from a real commit failure.
                //
                // ── GIT IDENTITY ─────────────────────────────────────────
                //   --local scopes identity to this repo's .git/config only.
                // ────────────────────────────────────────────────────────────
                stage('Update CD Repo') {
                    steps {
                        echo '🔄 Updating image tag in CD repo (platform-engineering-systems)...'
                        withCredentials([usernamePassword(
                            credentialsId: 'github-creds',
                            usernameVariable: 'GIT_USER',
                            passwordVariable: 'GIT_TOKEN'
                        )]) {
                            sh """
                                # ── IMAGE_TAG GUARD ──────────────────────────────────────
                                # \${IMAGE_TAG} escaped — shell evaluates at runtime.
                                # Unescaped ${IMAGE_TAG} would be Groovy-interpolated at
                                # parse time; if null, renders as "null" and guard never fires.
                                if [ -z "\${IMAGE_TAG}" ]; then
                                    echo '❌ IMAGE_TAG is empty — aborting CD repo update'
                                    exit 1
                                fi

                                # FIX #9 — unique tmp name avoids collision with app source dirs.
                                rm -rf _cd_repo_tmp

                                # Step 1: Clone with token in URL.
                                # \${GIT_USER} / \${GIT_TOKEN} escaped — shell expands from
                                # withCredentials env, not Groovy (see header note).
                                git clone https://\${GIT_USER}:\${GIT_TOKEN}@github.com/ibtisam-iq/platform-engineering-systems.git _cd_repo_tmp

                                cd _cd_repo_tmp

                                # Step 2: Clear token-bearing URL immediately.
                                git remote set-url origin ""

                                # Step 3: Restore bare HTTPS URL — credential helper requires
                                # a non-empty remote URL; empty URL → fatal git error.
                                git remote set-url origin "https://github.com/ibtisam-iq/platform-engineering-systems.git"

                                # --local scopes identity to this repo only.
                                git config --local user.email "jenkins@ibtisam-iq.com"
                                git config --local user.name  "Jenkins CI"

                                mkdir -p systems/java-monolith

                                # Once K8s/Helm manifests exist, replace with:
                                # sed -i "s|image: ibtisam-iq/java-monolith:.*|image: ibtisam-iq/java-monolith:\${IMAGE_TAG}|g" \\
                                #     deployments/java-monolith/deployment.yaml

                                # FIX #1 — \${IMAGE_TAG} escaped so shell evaluates at runtime.
                                # Unescaped ${IMAGE_TAG} interpolated by Groovy at parse time;
                                # if Stage 3 never ran, env.IMAGE_TAG is null → writes
                                # "IMAGE_TAG=null" into image.env → ArgoCD deploys tag "null".
                                echo "IMAGE_TAG=\${IMAGE_TAG}" > systems/java-monolith/image.env

                                git add systems/java-monolith/image.env

                                # FIX #3 — precise "nothing staged" detection.
                                # git diff --cached --quiet exits 0 if nothing staged (skip commit),
                                # exits 1 if staged changes exist (run commit).
                                # Unlike `|| echo`, this does NOT suppress real commit errors
                                # (detached HEAD, merge conflicts, broken .git/config).
                                git diff --cached --quiet \\
                                    && echo "ℹ️ Nothing to commit — image tag unchanged" \\
                                    || git commit -m "ci: update java-monolith image tag to \${IMAGE_TAG} [skip ci]"

                                # Step 4: Push via credential helper.
                                # Credentials fed via stdin at push time only — never stored.
                                # printf with %s is immune to special chars in token values.
                                # \${GIT_USER} / \${GIT_TOKEN} escaped (see header note).
                                #
                                # FIX #2 — HEAD instead of hardcoded 'main'.
                                # If CD repo default branch is renamed, HEAD still works.
                                git -c credential.helper='!f() { printf "username=%s\\n" "\${GIT_USER}"; printf "password=%s\\n" "\${GIT_TOKEN}"; }; f' \\
                                    push origin HEAD
                            """
                        }
                    }
                }

            } // end stages (Publish)
        } // end stage('Publish')

    } // end stages

    // ────────────────────────────────────────────────────────────────────────
    // POST — Publishers, Cleanup & Notifications
    //
    // ORDERING (intentional — do not reorder):
    //   1. junit + recordCoverage — guarded by fileExists (FIX #8) so empty
    //      coverage data points are not written for pre-test-stage failures.
    //      Must run BEFORE cleanWs() removes report files from workspace.
    //   2. script{} block — Docker named rmi + dangling prune.
    //   3. cleanWs() — always last.
    //
    // FIX #8 — fileExists guard prevents recordCoverage from writing
    //   zero-coverage data points when the pipeline fails before Stage 4
    //   (Build & Test). Without the guard, every Trivy or Versioning failure
    //   appends a zero-coverage record to the trend graph — causing apparent
    //   coverage drops that are actually just pre-test infrastructure failures,
    //   not real test regressions.
    // ────────────────────────────────────────────────────────────────────────
    post {
        always {
            // ── 1. Test & coverage publishers — guarded by fileExists (FIX #8)
            script {
                if (fileExists("${APP_DIR}/target/surefire-reports")) {
                    junit testResults: "${APP_DIR}/target/surefire-reports/*.xml",
                          allowEmptyResults: true

                    recordCoverage(
                        tools: [[
                            parser: 'JACOCO',
                            pattern: "${APP_DIR}/target/site/jacoco/jacoco.xml"
                        ]],
                        sourceCodeRetention: 'EVERY_BUILD'
                    )
                } else {
                    echo '⏭️  Skipping junit + recordCoverage — no surefire-reports directory found (pipeline failed before Build & Test stage).'
                }
            }

            // ── 2. Docker cleanup — named rmi + dangling prune
            script {
                if (env.IMAGE_TAG) {
                    echo '🧹 Cleaning up local Docker images...'
                    sh """
                        docker rmi ${IMAGE_NAME}:${IMAGE_TAG}                                    || true
                        docker rmi ${IMAGE_NAME}:latest                                          || true
                        docker rmi ${GHCR_IMAGE}:${IMAGE_TAG}                                   || true
                        docker rmi ${GHCR_IMAGE}:latest                                         || true
                        docker rmi ${NEXUS_DOCKER}/${NEXUS_DOCKER_REPO}/${APP_NAME}:${IMAGE_TAG} || true
                        docker rmi ${NEXUS_DOCKER}/${NEXUS_DOCKER_REPO}/${APP_NAME}:latest       || true
                        # docker rmi \${ECR_IMAGE}:${IMAGE_TAG}                                 || true
                        # docker rmi \${ECR_IMAGE}:latest                                       || true
                    """
                } else {
                    echo '⏭️  Skipping docker rmi — IMAGE_TAG not set (pipeline failed before Versioning stage).'
                }

                // Prune dangling (<none>:<none>) image layers.
                sh 'docker image prune -f || true'
            }

            // ── 3. Workspace cleanup — always last
            cleanWs()
        }

        success {
            // FIX #10 — branch context added so non-main builds don't imply
            // images were pushed to registries when Publish stages were skipped.
            script {
                def published = (env.GIT_BRANCH != null && env.GIT_BRANCH ==~ /^(origin\/)?main$/)
                    ? 'PUBLISHED to all registries ✅'
                    : 'NOT PUBLISHED — non-main branch (build + scan only)'
                echo """
            ╔══════════════════════════════════════════════════════════╗
            ║  ✅  PIPELINE SUCCEEDED
            ╠══════════════════════════════════════════════════════════╣
            ║  Branch : ${env.GIT_BRANCH}
            ║  Status : ${published}
            ║  Image  : ${IMAGE_NAME}:${IMAGE_TAG}
            ║  GHCR   : ${GHCR_IMAGE}:${IMAGE_TAG}
            ║  Nexus  : ${NEXUS_URL}
            ╚══════════════════════════════════════════════════════════╝
                """
            }
        }

        failure {
            echo """
            ╔══════════════════════════════════════════════════════════╗
            ║  ❌  PIPELINE FAILED                                     ║
            ║  Check console output for details                        ║
            ╚══════════════════════════════════════════════════════════╝
            """
        }

        unstable {
            echo '⚠️  Pipeline is UNSTABLE — test failures detected.'
        }
    }
}

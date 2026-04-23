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
//     used in Versioning, Build & Test, SonarQube Analysis, and Publish JAR.
//     Without it, those stages fail with "No such DSL method withMaven".
//   - SonarQube Scanner Plugin           → provides withSonarQubeEnv()
//   - Coverage Plugin                    → provides recordCoverage() DSL
//   - AnsiColor Plugin                   → provides ansiColor() option
//   - Config File Provider Plugin        → provides globalMavenSettingsConfig
// ──────────────────────────────────────────────────────────────────────────────
//
// ── MIGRATION NOTE ────────────────────────────────────────────────────────────
// This Jenkinsfile was originally authored inside a separate
// pipeline repository:
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

    agent any

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
        buildDiscarder(logRotator(numToKeepStr: '10'))
        // 60 minutes — accommodates cold starts on the self-hosted server
        // (jenkins.ibtisam-iq.com) where the Trivy DB may not yet be cached
        // and the Maven local repo may be empty. With --cache-dir /var/cache/trivy,
        // warm builds complete well within this limit.
        timeout(time: 60, unit: 'MINUTES')
        disableConcurrentBuilds()
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
        //   across builds. Create once: mkdir -p /var/cache/trivy
        //
        // --skip-dirs .git — excluded to avoid:
        //   (a) False positives: Trivy's secret scanner finds base64-encoded
        //       tokens in git pack files and commit history.
        //   (b) Slow scans: .git/ can be large; scanning it adds time with
        //       zero value — we care about source files, not git internals.
        //
        // TWO-PASS STRATEGY:
        //   Pass 1 — CRITICAL only, --exit-code 1 (NO || true)
        //            → pipeline FAILS if any CRITICAL CVE found.
        //              || true would silently swallow the failure —
        //              never add it here.
        //   Pass 2 — HIGH,MEDIUM, --exit-code 0
        //            → advisory only, printed to console as a table.
        //
        // Full CRITICAL report archived as trivy-fs-report.json.
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
        // APP_VERSION is read dynamically from pom.xml via mvn help:evaluate
        // wrapped in withMaven so Nexus credentials are injected via
        // settings.xml. This is required if pom.xml inherits from a parent
        // POM hosted in Nexus — without withMaven, Maven cannot resolve
        // the parent and help:evaluate returns an empty string, producing
        // a malformed tag like "-ab3f12c-42".
        // ────────────────────────────────────────────────────────────────────
        stage('Versioning') {
            steps {
                dir(APP_DIR) {
                    script {
                        def appVersion = ''
                        withMaven(globalMavenSettingsConfig: 'maven-settings') {
                            appVersion = sh(
                                script: 'mvn help:evaluate -Dexpression=project.version -q -DforceStdout',
                                returnStdout: true
                            ).trim()
                        }
                        def shortSha  = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
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
        // NOTE: junit and recordCoverage publishers must live in the
        // top-level post { always } block — not in a stage-level post.
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
        // ────────────────────────────────────────────────────────────────────
        stage('SonarQube Analysis') {
            steps {
                dir(APP_DIR) {
                    echo '🔍 Running SonarQube static analysis...'
                    withSonarQubeEnv('sonar-server') {
                        withMaven(globalMavenSettingsConfig: 'maven-settings') {
                            sh """
                                mvn sonar:sonar \\
                                    -Dsonar.projectKey=IbtisamIQbankapp \\
                                    -Dsonar.projectName=IbtisamIQbankapp \\
                                    -Dsonar.java.binaries=target/classes \\
                                    -Dsonar.coverage.jacoco.xmlReportPaths=target/site/jacoco/jacoco.xml \\
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
        // Builds the multi-stage image defined in the app's
        // own Dockerfile (Stage1: maven:3.9-temurin-21-alpine,
        // Stage2: eclipse-temurin:21-jre-jammy).
        // Tags the image for ALL three registries in one build:
        //   - Docker Hub : mibtisam/java-monolith:<tag>
        //   - GHCR       : ghcr.io/ibtisam-iq/java-monolith:<tag>
        //   - ECR        : <account>.dkr.ecr.<region>.amazonaws.com/java-monolith:<tag>
        // Building once and tagging avoids rebuilding per registry.
        //
        // GIT_COMMIT is guaranteed to be the triggering commit SHA
        // because Stage 1 uses `checkout scm`.
        // ────────────────────────────────────────────────────────────────────
        stage('Docker Build') {
            steps {
                dir(APP_DIR) {
                    echo "🐳 Building Docker image: ${IMAGE_NAME}:${IMAGE_TAG}"
                    sh """
                        docker build \\
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
        // Scans the freshly built image for CVEs BEFORE
        // pushing to any registry — fail-fast principle.
        //
        // Wrapped in dir(APP_DIR) for consistency with Stage 2
        // so the JSON report lands in the same relative path
        // regardless of whether APP_DIR changes in future.
        //
        // TWO-PASS STRATEGY (same rationale as Stage 2):
        //   Pass 1 — CRITICAL only, --exit-code 1 (NO || true)
        //   Pass 2 — HIGH,MEDIUM,LOW, --exit-code 0 (advisory)
        //
        // --cache-dir /var/cache/trivy — same DB cache as Stage 2.
        // Results archived as trivy-image-report.json.
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
                    archiveArtifacts artifacts: 'trivy-image-report.json', allowEmptyArchive: true
                }
            }
        }

        // ────────────────────────────────────────────────────────────────────
        // STAGE 10–14 — Publish (main branch only)
        //
        // Gated with an expression{} condition on GIT_BRANCH — NOT
        // `when { branch 'main' }`. The branch{} directive requires a
        // Multibranch Pipeline job (which injects BRANCH_NAME). On a
        // standard Pipeline job (the most common type on self-hosted
        // Jenkins), BRANCH_NAME is never set and branch{} would always
        // evaluate to false — silently skipping every publish.
        //
        // GIT_BRANCH is always set by `checkout scm` on standard
        // Pipeline jobs. It takes the form "origin/main" after a
        // checkout, so the regex .*\/main matches that reliably.
        // The bare == 'main' arm handles Multibranch Pipeline jobs
        // where BRANCH_NAME is injected directly without the remote prefix.
        // ────────────────────────────────────────────────────────────────────
        stage('Publish') {
            when {
                expression {
                    env.GIT_BRANCH ==~ /.*\/main/ || env.GIT_BRANCH == 'main'
                }
            }
            stages {

                // ────────────────────────────────────────────────────────────
                // STAGE 10 — Push to Docker Hub
                //
                // docker logout registry-1.docker.io — explicit registry
                // argument required. Bare `docker logout` (no args) logs
                // out of docker.io AND clears the entire
                // ~/.docker/config.json on some Docker Engine versions,
                // wiping credentials for all other registries on the agent.
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
                // platform-engineering-systems so ArgoCD detects
                // the change and triggers deployment.
                //
                // CREDENTIAL SECURITY:
                //   1. Clone with token in URL (required by git CLI)
                //   2. Immediately clear origin URL: git remote set-url origin ""
                //      Prevents token leaking via `git remote -v`
                //   3. Restore BARE HTTPS URL (no credentials) to origin
                //      before pushing. This is required — the credential
                //      helper needs a valid remote URL to push to.
                //   4. Push via Git credential helper — credentials passed
                //      via stdin, never embedded in any URL or log output.
                //
                // GROOVY INTERPOLATION NOTE (CRITICAL):
                //   Inside """...""", Groovy interpolates ${VAR}. To pass
                //   shell variables (like GIT_USER / GIT_TOKEN injected by
                //   withCredentials), the $ must be escaped as \$ so Groovy
                //   passes them through to the shell unexpanded:
                //     echo "username=\${GIT_USER}"   → shell sees $GIT_USER ✔
                //     echo "username=${GIT_USER}"    → Groovy expands to ""  ✘
                //
                // GIT IDENTITY: --local scopes CI identity to this repo only.
                // DIRECTORY SAFETY: mkdir -p guards first-run and deletion.
                // IMAGE_TAG GUARD: exits early if IMAGE_TAG is empty to
                //   prevent ArgoCD deploying a blank image tag.
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
                                # Guard: abort early if IMAGE_TAG is empty.
                                # Prevents committing IMAGE_TAG= (blank) which
                                # would cause ArgoCD to deploy with no image tag.
                                if [ -z "${IMAGE_TAG}" ]; then
                                    echo '❌ IMAGE_TAG is empty — aborting CD repo update'
                                    exit 1
                                fi

                                rm -rf cd-repo
                                git clone https://\${GIT_USER}:\${GIT_TOKEN}@github.com/ibtisam-iq/platform-engineering-systems.git cd-repo

                                cd cd-repo

                                # Step 1: Clear token-bearing URL immediately after clone.
                                git remote set-url origin ""

                                # Step 2: Restore bare HTTPS URL (no credentials).
                                # Required so the credential helper below has a
                                # valid remote to push to.
                                git remote set-url origin "https://github.com/ibtisam-iq/platform-engineering-systems.git"

                                # Scope CI identity to this repo only.
                                git config --local user.email "jenkins@ibtisam-iq.com"
                                git config --local user.name  "Jenkins CI"

                                # Ensure the target directory exists.
                                mkdir -p systems/java-monolith

                                # Once K8s/Helm manifests exist, replace with:
                                # sed -i "s|image: ibtisam-iq/java-monolith:.*|image: ibtisam-iq/java-monolith:${IMAGE_TAG}|g" \\
                                #     deployments/java-monolith/deployment.yaml

                                echo "IMAGE_TAG=${IMAGE_TAG}" > systems/java-monolith/image.env

                                git add systems/java-monolith/image.env
                                git commit -m "ci: update java-monolith image tag to ${IMAGE_TAG} [skip ci]" || echo "Nothing to commit"

                                # Push via credential helper — token passed via stdin only,
                                # never embedded in the remote URL or visible in any log.
                                # \${GIT_USER} / \${GIT_TOKEN} — \$ escapes Groovy interpolation
                                # so the shell receives the literal env var names and expands
                                # them at runtime from the withCredentials environment.
                                git -c credential.helper='!f() { echo "username=\${GIT_USER}"; echo "password=\${GIT_TOKEN}"; }; f' \\
                                    push origin main
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
    // ORDERING:
    //   1. junit + recordCoverage — consume XML report files before
    //      cleanWs() removes them.
    //   2. docker rmi — guarded by if (env.IMAGE_TAG) to prevent
    //      malformed commands if Versioning stage never ran.
    //   3. docker image prune -f — removes dangling (<none>) image
    //      layers left behind when a build is aborted mid-pipeline
    //      by disableConcurrentBuilds(). Runs unconditionally so
    //      even aborted builds are cleaned up on the next run.
    //   4. cleanWs() — runs last, removes the entire workspace.
    // ────────────────────────────────────────────────────────────────────────
    post {
        always {
            // ── 1. Test results
            junit testResults: "${APP_DIR}/target/surefire-reports/*.xml",
                  allowEmptyResults: true

            // ── Code coverage
            recordCoverage(
                tools: [[
                    parser: 'JACOCO',
                    pattern: "${APP_DIR}/target/site/jacoco/jacoco.xml"
                ]],
                sourceCodeRetention: 'EVERY_BUILD'
            )

            // ── 2. Named image cleanup (only if IMAGE_TAG was set)
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
            }

            // ── 3. Dangling image prune
            // Removes <none>:<none> image layers that accumulate when
            // builds are aborted mid-pipeline by disableConcurrentBuilds().
            // Runs unconditionally after every build so the agent's Docker
            // daemon stays clean without needing a cron job.
            sh 'docker image prune -f || true'

            // ── 4. Workspace cleanup — always last
            cleanWs()
        }
        success {
            echo """
            ╔══════════════════════════════════════════════════════════╗
            ║  ✅  PIPELINE SUCCEEDED
            ╠══════════════════════════════════════════════════════════╣
            ║  Image  : ${IMAGE_NAME}:${IMAGE_TAG}
            ║  GHCR   : ${GHCR_IMAGE}:${IMAGE_TAG}
            ║  Nexus  : ${NEXUS_URL}
            ╚══════════════════════════════════════════════════════════╝
            """
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

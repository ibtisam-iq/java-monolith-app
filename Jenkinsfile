// ============================================================
// DevSecOps CI Pipeline — Java Monolith (BankApp)
// Tool: Jenkins Declarative Pipeline
// Stack: Maven 3.9 · Java 21 · SonarQube · Trivy · Nexus · Docker Hub · GHCR · ECR
// Credentials: sonarqube-token · github-creds · docker-creds · nexus-creds · ghcr-creds
// SonarQube server: sonar-server  |  Scanner: sonar-scanner
// Maven settings:   maven-settings (Config File Provider)
//
// ── REQUIRED JENKINS PLUGINS ─────────────────────────────────
// The following plugins MUST be installed for this pipeline to work:
//   - Pipeline Maven Integration Plugin  → provides withMaven() DSL
//     used in Build & Test, SonarQube Analysis, and Publish JAR stages.
//     Without it, those stages fail with "No such DSL method withMaven".
//   - SonarQube Scanner Plugin           → provides withSonarQubeEnv()
//   - Coverage Plugin                    → provides recordCoverage() DSL
//   - AnsiColor Plugin                   → provides ansiColor() option
//   - Config File Provider Plugin        → provides globalMavenSettingsConfig
// ─────────────────────────────────────────────────────────────
//
// ── MIGRATION NOTE ───────────────────────────────────────────
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
// ─────────────────────────────────────────────────────────────

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
        GROUP_ID       = 'com.ibtisamiq'

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
        // 60 minutes — increased from 45 to accommodate cold starts on the
        // self-hosted server (jenkins.ibtisam-iq.com) where the Trivy DB has
        // not yet been cached and the Maven local repo may be empty.
        // With --cache-dir /var/cache/trivy (see Stage 2 and Stage 9), repeated
        // builds will be significantly faster and well within this limit.
        timeout(time: 60, unit: 'MINUTES')
        disableConcurrentBuilds()
        timestamps()
        ansiColor('xterm')
    }

    stages {

        // ────────────────────────────────────────────────
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
        //   - Avoids a redundant second full clone of the repo (Jenkins
        //     already did a lightweight checkout to read this Jenkinsfile).
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
        // ────────────────────────────────────────────────
        stage('Checkout') {
            steps {
                echo '📥 Checking out source...'
                checkout scm
            }
        }

        // ────────────────────────────────────────────────
        // STAGE 2 — Trivy Filesystem Scan
        // Scans the entire checked-out source tree for:
        //   - Hardcoded secrets (passwords, tokens, keys)
        //   - Known CVEs in dependency files
        //     (pom.xml, package.json, requirements.txt)
        //   - Misconfigurations in Dockerfile, compose.yml
        //
        // Runs BEFORE build — fail-fast on secrets or
        // critical dependency CVEs before wasting build time.
        //
        // TRIVY SCANNER NAME:
        //   --scanners secret,vuln,misconfig requires Trivy ≥ v0.38.0
        //   (released 2023-03). In older versions the flag was `config`.
        //   Verify your installed version: trivy --version
        //   If < 0.38.0, upgrade Trivy or replace `misconfig` with `config`.
        //
        // TRIVY CACHE:
        //   --cache-dir /var/cache/trivy persists the vulnerability DB
        //   across builds on this self-hosted server, avoiding a ~50 MB
        //   download on every run. Create once: mkdir -p /var/cache/trivy
        //
        // TWO-PASS STRATEGY:
        //   Pass 1 — CRITICAL only, --exit-code 1 (NO || true)
        //            → pipeline FAILS if any CRITICAL CVE found.
        //              This is the enforcement gate. || true would
        //              completely negate --exit-code 1 and silently
        //              swallow the failure — never add it here.
        //   Pass 2 — HIGH,MEDIUM, --exit-code 0
        //            → advisory only, printed to console as a table.
        //              || true is acceptable here because exit-code
        //              is already 0 (non-blocking by design).
        //
        // Full CRITICAL report archived as trivy-fs-report.json.
        // ────────────────────────────────────────────────
        stage('Trivy Filesystem Scan') {
            steps {
                dir(APP_DIR) {
                    echo '🔎 Running Trivy filesystem scan on source tree...'
                    sh """
                        trivy fs \\
                            --cache-dir /var/cache/trivy \\
                            --scanners secret,vuln,misconfig \\
                            --exit-code 1 \\
                            --severity CRITICAL \\
                            --no-progress \\
                            --format json \\
                            --output trivy-fs-report.json \\
                            .

                        trivy fs \\
                            --cache-dir /var/cache/trivy \\
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

        // ────────────────────────────────────────────────
        // STAGE 3 — Versioning
        // Build a unique, traceable image tag:
        //   <pom-version>-<short-git-sha>-<build-number>
        // e.g.  0.0.1-SNAPSHOT-ab3f12c-42
        //
        // APP_VERSION is read dynamically from pom.xml via mvn help:evaluate
        // so the tag always reflects the real version — no hardcoding that
        // can drift when the pom.xml version is bumped.
        // ────────────────────────────────────────────────
        stage('Versioning') {
            steps {
                dir(APP_DIR) {
                    script {
                        def appVersion = sh(
                            script: 'mvn help:evaluate -Dexpression=project.version -q -DforceStdout',
                            returnStdout: true
                        ).trim()
                        def shortSha   = sh(script: 'git rev-parse --short HEAD', returnStdout: true).trim()
                        env.IMAGE_TAG  = "${appVersion}-${shortSha}-${BUILD_NUMBER}"
                        echo "🏷️  Image tag: ${IMAGE_TAG}"
                    }
                }
            }
        }

        // ────────────────────────────────────────────────
        // STAGE 4 — Build & Test
        // withMaven injects the managed settings.xml (maven-settings)
        // so Nexus credentials never appear in source code.
        // JaCoCo runs automatically during the test phase
        // because it is bound to prepare-agent + report goals in pom.xml.
        //
        // NOTE: No post block here — junit and recordCoverage are
        // publishers that must live in the top-level post { always }
        // block. Stage-level post only supports plain steps, not
        // Jenkins publisher DSLs.
        // ────────────────────────────────────────────────
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

        // ────────────────────────────────────────────────
        // STAGE 5 — SonarQube Analysis
        // withSonarQubeEnv injects SONAR_HOST_URL and the
        // sonarqube-token automatically — no hardcoding.
        // ────────────────────────────────────────────────
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

        // ────────────────────────────────────────────────
        // STAGE 6 — Quality Gate
        // Blocks the pipeline until SonarQube webhook fires
        // back to Jenkins with pass/fail result.
        // abortPipeline: true → fails the build on gate failure.
        // ────────────────────────────────────────────────
        stage('Quality Gate') {
            steps {
                echo '🚦 Waiting for SonarQube Quality Gate...'
                timeout(time: 5, unit: 'MINUTES') {
                    waitForQualityGate abortPipeline: true
                }
            }
        }

        // ────────────────────────────────────────────────
        // STAGE 7 — Publish JAR to Nexus
        // Pushes the built SNAPSHOT JAR to:
        //   https://nexus.ibtisam-iq.com/repository/maven-snapshots/
        // The server IDs (maven-releases / maven-snapshots) in
        // settings.xml match the <distributionManagement> in pom.xml.
        // ────────────────────────────────────────────────
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

        // ────────────────────────────────────────────────
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
        // because Stage 1 now uses `checkout scm`.
        // ────────────────────────────────────────────────
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

        // ────────────────────────────────────────────────
        // STAGE 9 — Trivy Image Scan
        // Scans the freshly built image for CVEs BEFORE
        // pushing to any registry — fail-fast principle.
        //
        // TWO-PASS STRATEGY (same rationale as Stage 2):
        //   Pass 1 — CRITICAL only, --exit-code 1 (NO || true)
        //            → pipeline FAILS if any CRITICAL CVE is found
        //              in the final runtime image layers. Adding
        //              || true here would silently swallow failures
        //              and allow vulnerable images to be pushed.
        //   Pass 2 — HIGH,MEDIUM,LOW, --exit-code 0
        //            → advisory only, printed as a table to console.
        //
        // --cache-dir /var/cache/trivy — same DB cache as Stage 2.
        // Results archived as trivy-image-report.json.
        // ────────────────────────────────────────────────
        stage('Trivy Image Scan') {
            steps {
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

        // ────────────────────────────────────────────────
        // STAGE 10–14 — Publish (main branch only)
        //
        // All registry push stages and the CD repo update are
        // grouped inside this parent stage and gated with:
        //   when { branch 'main' }
        //
        // This prevents feature/* and develop branches from:
        //   - Pushing SNAPSHOT images to Docker Hub, GHCR, Nexus
        //   - Polluting the CD repo with non-production tags
        //
        // The when{} condition is evaluated before any nested stage
        // runs, so all five sub-stages are skipped together if the
        // triggering branch is not main.
        // ────────────────────────────────────────────────
        stage('Publish') {
            when {
                branch 'main'
            }
            stages {

                // ────────────────────────────────────────
                // STAGE 10 — Push to Docker Hub
                // Credential ID: docker-creds (Username with Password)
                // Pushes both versioned tag and :latest.
                // ────────────────────────────────────────
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
                                docker logout
                            """
                        }
                    }
                }

                // ────────────────────────────────────────
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
                // ────────────────────────────────────────
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

                // ────────────────────────────────────────
                // STAGE 12 — Push to Nexus Docker Registry
                // Uses path-based routing — no dedicated Docker port needed.
                // Image URL: nexus.ibtisam-iq.com/docker-hosted/java-monolith:<tag>
                //
                // Pre-requisites in Nexus UI:
                //   1. Create hosted Docker repo with "Path based routing" selected
                //   2. Security → Realms → enable "Docker Bearer Token Realm"
                //
                // Credential ID: nexus-creds (Username with Password)
                // ────────────────────────────────────────
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

                // ────────────────────────────────────────
                // STAGE 13 — Push to AWS ECR  [COMMENTED OUT]
                // Uncomment and configure once AWS credentials and
                // ECR repository are provisioned.
                //
                // Pre-requisites:
                //   1. Create ECR repo:
                //        aws ecr create-repository --repository-name java-monolith --region us-east-1
                //
                //   2. Add AWS credentials to Jenkins:
                //        Kind:     AWS Credentials (requires CloudBees AWS Credentials plugin)
                //        ID:       aws-creds
                //        Access Key ID + Secret Access Key for an IAM user/role with
                //        AmazonEC2ContainerRegistryPowerUser policy attached.
                //
                //   3. Set the four ECR variables in environment {} above:
                //        AWS_REGION, AWS_ACCOUNT_ID, ECR_REGISTRY, ECR_IMAGE
                //
                //   4. Uncomment the docker tag lines in the Docker Build stage above.
                //
                //   5. Uncomment this entire stage.
                // ────────────────────────────────────────
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
                //
                //                 docker push ${ECR_IMAGE}:${IMAGE_TAG}
                //                 docker push ${ECR_IMAGE}:latest
                //
                //                 docker logout ${ECR_REGISTRY}
                //             """
                //         }
                //     }
                // }

                // ────────────────────────────────────────
                // STAGE 14 — Update Image Tag in CD Repo
                // CI → CD Handoff: commits the new image tag into
                // platform-engineering-systems so ArgoCD detects
                // the change and triggers deployment.
                //
                // CREDENTIAL SECURITY:
                //   The token is needed for both clone and push. To keep
                //   it out of the remote URL (and therefore out of
                //   .git/config and console log output), we:
                //     1. Clone with the token in the URL (unavoidable for git CLI)
                //     2. Immediately clear it: git remote set-url origin ""
                //     3. Use Git credential helper for push — credentials
                //        are passed via stdin, never embedded in any URL.
                //        Format: git -c credential.helper='!f() {...}; f' push origin main
                //   This means the token NEVER appears in the URL in either
                //   .git/config or the Jenkins console log.
                //
                // GIT IDENTITY:
                //   git config --local scopes the CI identity to this
                //   repo's .git/config only — does not bleed into other
                //   pipelines running on the same Jenkins agent.
                //
                // DIRECTORY SAFETY:
                //   mkdir -p systems/java-monolith ensures the target
                //   directory exists before writing image.env. Without
                //   this, the echo redirect fails on first run or if
                //   the directory was ever deleted from the CD repo.
                // ────────────────────────────────────────
                stage('Update CD Repo') {
                    steps {
                        echo '🔄 Updating image tag in CD repo (platform-engineering-systems)...'
                        withCredentials([usernamePassword(
                            credentialsId: 'github-creds',
                            usernameVariable: 'GIT_USER',
                            passwordVariable: 'GIT_TOKEN'
                        )]) {
                            sh """
                                rm -rf cd-repo
                                git clone https://\${GIT_USER}:\${GIT_TOKEN}@github.com/ibtisam-iq/platform-engineering-systems.git cd-repo

                                cd cd-repo

                                # Clear the token-bearing URL from .git/config immediately
                                # after cloning — prevents leaking via `git remote -v`.
                                git remote set-url origin ""

                                # Scope CI identity to this repo only (not --global).
                                git config --local user.email "jenkins@ibtisam-iq.com"
                                git config --local user.name  "Jenkins CI"

                                # Ensure the target directory exists before writing.
                                # Required on first run or if systems/java-monolith/
                                # was ever deleted from the CD repo.
                                mkdir -p systems/java-monolith

                                # Once K8s/Helm manifests exist, replace the echo below with:
                                # sed -i "s|image: ibtisam-iq/java-monolith:.*|image: ibtisam-iq/java-monolith:${IMAGE_TAG}|g" \\
                                #     deployments/java-monolith/deployment.yaml

                                echo "IMAGE_TAG=${IMAGE_TAG}" > systems/java-monolith/image.env

                                git add systems/java-monolith/image.env
                                git commit -m "ci: update java-monolith image tag to ${IMAGE_TAG} [skip ci]" || echo "Nothing to commit"

                                # Push using Git credential helper — credentials are passed
                                # via stdin, never embedded in the remote URL or visible
                                # in the console log.
                                git -c credential.helper='!f() { echo "username=\${GIT_USER}"; echo "password=\${GIT_TOKEN}"; }; f' \\
                                    push origin main
                            """
                        }
                    }
                }

            } // end stages (Publish)
        } // end stage('Publish')

    } // end stages

    // ────────────────────────────────────────────────────
    // POST — Publishers, Cleanup & Notifications
    //
    // junit and recordCoverage are Jenkins publisher steps.
    // Publishers MUST live here in the top-level post block —
    // they are NOT supported inside a stage-level post block.
    //
    // ORDERING RATIONALE:
    //   1. junit + recordCoverage run FIRST — they consume the
    //      XML report files from the workspace. They must complete
    //      before cleanWs() removes the workspace.
    //   2. docker rmi runs SECOND — cleans up local image layers
    //      from the Jenkins agent's Docker daemon. Guarded with
    //      if (env.IMAGE_TAG) so that if the pipeline failed before
    //      Stage 3 (Versioning), IMAGE_TAG is empty and we skip the
    //      docker rmi block entirely rather than running malformed
    //      commands like `docker rmi java-monolith:` with no tag.
    //   3. cleanWs() runs LAST — removes the entire workspace
    //      including any leftover cd-repo directory.
    // ────────────────────────────────────────────────────
    post {
        always {
            // ── 1. Test results (publishers first, before workspace is wiped)
            //
            // CURRENT path (java-monolith-app repo root, APP_DIR = '.'):
            junit testResults: "${APP_DIR}/target/surefire-reports/*.xml",
                  allowEmptyResults: true

            // ── Code coverage (Coverage Plugin — recordCoverage DSL)
            // Requires: "Coverage" plugin (not the old JaCoCo plugin).
            // jacoco.xml is generated by JaCoCo report goal bound in pom.xml.
            recordCoverage(
                tools: [[
                    parser: 'JACOCO',
                    pattern: "${APP_DIR}/target/site/jacoco/jacoco.xml"
                ]],
                sourceCodeRetention: 'EVERY_BUILD'
            )

            // ── 2. Docker image cleanup
            // Guarded with if (env.IMAGE_TAG) to prevent malformed
            // `docker rmi image:` commands when the pipeline fails
            // before Stage 3 (Versioning) and IMAGE_TAG was never set.
            script {
                if (env.IMAGE_TAG) {
                    echo '🧹 Cleaning up local Docker images...'
                    sh """
                        docker rmi ${IMAGE_NAME}:${IMAGE_TAG}                                    || true
                        docker rmi ${IMAGE_NAME}:latest                                          || true
                        docker rmi ${GHCR_IMAGE}:${IMAGE_TAG}                                    || true
                        docker rmi ${GHCR_IMAGE}:latest                                          || true
                        docker rmi ${NEXUS_DOCKER}/${NEXUS_DOCKER_REPO}/${APP_NAME}:${IMAGE_TAG} || true
                        docker rmi ${NEXUS_DOCKER}/${NEXUS_DOCKER_REPO}/${APP_NAME}:latest       || true
                        # docker rmi \${ECR_IMAGE}:${IMAGE_TAG}                                  || true  (uncomment with ECR vars)
                        # docker rmi \${ECR_IMAGE}:latest                                        || true  (uncomment with ECR vars)
                    """
                } else {
                    echo '⏭️  Skipping docker rmi — IMAGE_TAG not set (pipeline failed before Versioning stage).'
                }
            }

            // ── 3. Workspace cleanup — runs last, after publishers and docker rmi.
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

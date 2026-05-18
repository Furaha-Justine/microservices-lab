// ─────────────────────────────────────────────────────────────
// ShopNow — CI/CD Pipeline
//
// Stages:
//   1. Test         — backend + frontend tests (parallel)
//   2. ECR Login    — authenticate Docker to ECR
//   3. Build & Push — frontend + backend images (parallel)
//   4. Deploy       — backend first, then frontend (rolling)
//   5. Verify       — hit ALB /health to confirm live
//
// Jenkins prerequisites (install on your PC):
//   - Docker
//   - AWS CLI v2
//   - jq  (brew install jq  /  apt install jq)
//   - Node.js 20+
//
// Jenkins credentials to configure (Manage Jenkins → Credentials):
//   - Secret Text  id: shopnow-aws-key-id      → from: terraform output jenkins_access_key_id
//   - Secret Text  id: shopnow-aws-secret-key  → from: terraform output -raw jenkins_secret_access_key
//
// Jenkins env var to configure (Manage Jenkins → System → Global properties):
//   - ALB_DNS  → from: terraform output alb_dns_name
// ─────────────────────────────────────────────────────────────

// ── Helper: register new task definition revision + update service ──
def deployService(String taskFamily, String service, String cluster, String newImage) {
    sh """
        set -e

        echo "── Fetching current task definition for ${taskFamily} ──"
        aws ecs describe-task-definition \
            --task-definition ${taskFamily} \
            --query 'taskDefinition' \
            --output json | \
        jq 'del(.taskDefinitionArn, .revision, .status, .requiresAttributes,
                .compatibilities, .registeredAt, .registeredBy)' \
        > /tmp/${taskFamily}-taskdef.json

        echo "── Injecting new image: ${newImage} ──"
        jq --arg IMG '${newImage}' \
            '.containerDefinitions[0].image = \$IMG' \
            /tmp/${taskFamily}-taskdef.json \
        > /tmp/${taskFamily}-taskdef-new.json

        echo "── Registering new task definition revision ──"
        NEW_ARN=\$(aws ecs register-task-definition \
            --cli-input-json file:///tmp/${taskFamily}-taskdef-new.json \
            --query 'taskDefinition.taskDefinitionArn' \
            --output text)
        echo "New revision: \$NEW_ARN"

        echo "── Updating ECS service ──"
        aws ecs update-service \
            --cluster ${cluster} \
            --service ${service} \
            --task-definition \$NEW_ARN \
            --output text > /dev/null

        echo "── Waiting for ${service} to reach steady state (up to 10 min) ──"
        aws ecs wait services-stable \
            --cluster ${cluster} \
            --services ${service}

        echo "── ${service} deployed successfully ──"

        rm -f /tmp/${taskFamily}-taskdef.json /tmp/${taskFamily}-taskdef-new.json
    """
}

// ─────────────────────────────────────────────────────────────
pipeline {
    agent any

    environment {
        // ── Tool paths (Jenkins shell doesn't inherit Mac PATH) ───
        PATH = "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:${env.PATH}"

        // ── AWS credentials via named profile in ~/.aws/credentials ───
        AWS_PROFILE        = 'shopnow-jenkins'
        AWS_DEFAULT_REGION = 'eu-west-1'

        // ── Project config ────────────────────────────────────
        PROJECT          = 'shopnow'
        ECS_CLUSTER      = 'shopnow-cluster'
        FRONTEND_SERVICE = 'shopnow-frontend'
        BACKEND_SERVICE  = 'shopnow-backend'

        // ── Set ALB_DNS as a Jenkins global env var after first terraform apply ──
        // Manage Jenkins → System → Global properties → Environment variables
        // ALB_DNS = 'shopnow-alb-xxxxxxxxx.us-east-1.elb.amazonaws.com'
    }

    options {
        buildDiscarder(logRotator(numToKeepStr: '10'))
        timeout(time: 40, unit: 'MINUTES')
        disableConcurrentBuilds()
    }

    stages {

        // ── Stage 1: Checkout ─────────────────────────────────
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    // Short git SHA used as the Docker image tag
                    env.IMAGE_TAG = sh(
                        script: 'git rev-parse --short HEAD',
                        returnStdout: true
                    ).trim()

                    // Derive ECR registry URL from the AWS account
                    env.AWS_ACCOUNT_ID = sh(
                        script: 'aws sts get-caller-identity --query Account --output text',
                        returnStdout: true
                    ).trim()

                    env.ECR_REGISTRY = "${env.AWS_ACCOUNT_ID}.dkr.ecr.${env.AWS_DEFAULT_REGION}.amazonaws.com"

                    env.FRONTEND_IMAGE = "${env.ECR_REGISTRY}/${env.PROJECT}/frontend:${env.IMAGE_TAG}"
                    env.BACKEND_IMAGE  = "${env.ECR_REGISTRY}/${env.PROJECT}/backend:${env.IMAGE_TAG}"

                    echo "Branch:       ${env.GIT_BRANCH}"
                    echo "Image tag:    ${env.IMAGE_TAG}"
                    echo "ECR registry: ${env.ECR_REGISTRY}"
                }
            }
        }

        // ── Stage 2: Tests ────────────────────────────────────
        stage('Test') {
            parallel {
                stage('Backend tests') {
                    steps {
                        dir('backend') {
                            sh 'npm ci --prefer-offline'
                            sh 'npm test -- --forceExit --ci'
                        }
                    }
                    post {
                        always {
                            junit allowEmptyResults: true,
                                  testResults: 'backend/coverage/**/*.xml'
                        }
                    }
                }

                stage('Frontend tests') {
                    steps {
                        dir('frontend') {
                            sh 'npm ci --prefer-offline'
                            sh 'npm test -- --forceExit --ci'
                        }
                    }
                    post {
                        always {
                            junit allowEmptyResults: true,
                                  testResults: 'frontend/coverage/**/*.xml'
                        }
                    }
                }
            }
        }

        // ── Stage 3: ECR Login ────────────────────────────────
        stage('ECR Login') {
            steps {
                sh """
                    aws ecr get-login-password --region ${AWS_DEFAULT_REGION} | \
                    docker login --username AWS --password-stdin ${ECR_REGISTRY}
                """
            }
        }

        // ── Stage 4: Build & Push ─────────────────────────────
        // Both images build in parallel to save time.
        // Tagged with git SHA (for traceability) and :latest.
        stage('Build & Push') {
            parallel {
                stage('Frontend image') {
                    steps {
                        sh """
                            echo "── Building frontend ──"
                            docker build \
                                --platform linux/amd64 \
                                --target production \
                                --cache-from ${ECR_REGISTRY}/${PROJECT}/frontend:latest \
                                -t ${FRONTEND_IMAGE} \
                                -t ${ECR_REGISTRY}/${PROJECT}/frontend:latest \
                                frontend/

                            echo "── Pushing frontend ──"
                            docker push ${FRONTEND_IMAGE}
                            docker push ${ECR_REGISTRY}/${PROJECT}/frontend:latest
                        """
                    }
                }

                stage('Backend image') {
                    steps {
                        sh """
                            echo "── Building backend ──"
                            docker build \
                                --platform linux/amd64 \
                                --target production \
                                --cache-from ${ECR_REGISTRY}/${PROJECT}/backend:latest \
                                -t ${BACKEND_IMAGE} \
                                -t ${ECR_REGISTRY}/${PROJECT}/backend:latest \
                                backend/

                            echo "── Pushing backend ──"
                            docker push ${BACKEND_IMAGE}
                            docker push ${ECR_REGISTRY}/${PROJECT}/backend:latest
                        """
                    }
                }
            }
        }

        // ── Stage 5: Deploy backend ───────────────────────────
        // Backend deploys first — frontend depends on it.
        // ECS circuit breaker auto-rolls back if health checks fail.
        stage('Deploy backend') {
            steps {
                script {
                    deployService(
                        "${PROJECT}-backend",
                        BACKEND_SERVICE,
                        ECS_CLUSTER,
                        BACKEND_IMAGE
                    )
                }
            }
        }

        // ── Stage 6: Deploy frontend ──────────────────────────
        stage('Deploy frontend') {
            steps {
                script {
                    deployService(
                        "${PROJECT}-frontend",
                        FRONTEND_SERVICE,
                        ECS_CLUSTER,
                        FRONTEND_IMAGE
                    )
                }
            }
        }

        // ── Stage 7: Verify ───────────────────────────────────
        // Polls the ALB /health endpoint until it returns 200.
        // Fails the build (and leaves ECS in the new state) if
        // the ALB never responds — investigate CloudWatch logs.
        stage('Verify') {
            steps {
                script {
                    if (!env.ALB_DNS) {
                        echo "ALB_DNS not set — skipping live health check."
                        echo "Set ALB_DNS in Jenkins → Manage Jenkins → System → Global properties."
                        return
                    }
                }
                sh """
                    echo "── Polling ALB health endpoint ──"
                    RETRIES=12
                    for i in \$(seq 1 \$RETRIES); do
                        STATUS=\$(curl -s -o /dev/null -w "%{http_code}" \
                            --max-time 10 \
                            http://${ALB_DNS}/health || echo "000")

                        echo "Attempt \$i/\$RETRIES → HTTP \$STATUS"

                        if [ "\$STATUS" = "200" ]; then
                            echo ""
                            echo "✓ Deployment verified — app is live at http://${ALB_DNS}"
                            exit 0
                        fi
                        sleep 15
                    done

                    echo "Health check failed after \$RETRIES attempts."
                    exit 1
                """
            }
        }
    }

    // ── Post-build ────────────────────────────────────────────
    post {
        success {
            echo """
            ┌────────────────────────────────────────────────┐
            │  Deployment complete                           │
            │  App:       http://${env.ALB_DNS ?: 'see ALB_DNS output'}
            │  Image tag: ${env.IMAGE_TAG}                  │
            └────────────────────────────────────────────────┘
            """
        }

        failure {
            echo """
            Deployment failed at stage: ${env.STAGE_NAME}
            ECS circuit breaker will auto-rollback the affected service.
            Check CloudWatch Logs: /ecs/shopnow/backend  and  /ecs/shopnow/frontend
            """
        }

        always {
            // Log out of ECR and clean workspace regardless of outcome
            sh 'docker logout ${ECR_REGISTRY} 2>/dev/null || true'
            cleanWs()
        }
    }
}

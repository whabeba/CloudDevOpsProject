@Library('ivolve-shared-library') _

/**
 * auth-service (Python / Flask + MySQL) CI pipeline.
 *
 * Stages: checkout -> build -> Trivy scan -> ECR login -> push -> cleanup
 *         -> update the Kubernetes overlay (GitOps promotion for ArgoCD).
 */
pipeline {
    agent any

    options {
        timeout(time: 45, unit: 'MINUTES')
        buildDiscarder(logRotator(numToKeepStr: '20', artifactNumToKeepStr: '10'))
        disableConcurrentBuilds()
        timestamps()
    }

    parameters {
        string(name: 'IMAGE_TAG', defaultValue: '', description: 'Image tag (default: BUILD_NUMBER-GIT_SHA)')
        string(name: 'AWS_REGION', defaultValue: 'us-east-1', description: 'AWS region holding the ECR repository')
        choice(name: 'SCAN_SEVERITY', choices: ['HIGH,CRITICAL', 'MEDIUM,HIGH,CRITICAL', 'CRITICAL'], description: 'Trivy severities that fail the build')
        booleanParam(name: 'SKIP_SCAN', defaultValue: false, description: 'Skip the Trivy scan (not recommended)')
        booleanParam(name: 'UPDATE_MANIFESTS', defaultValue: true, description: 'Commit the new tag to the GitOps overlay')
    }

    environment {
        SERVICE = 'auth-service'
        CONTEXT = 'auth-service'
        DOCKERFILE = 'auth-service/Dockerfile'
        OVERLAY = 'k8s/overlays/prod'
        GIT_BRANCH = 'main'
        USE_INSTANCE_PROFILE = 'true'
    }

    stages {
        stage('Checkout') {
            steps {
                checkout scm
                script {
                    env.TAG = params.IMAGE_TAG?.trim() ?: "${env.BUILD_NUMBER}-${env.GIT_COMMIT?.take(7)}"
                    env.TAG = env.TAG.toLowerCase()
                }
            }
        }

        stage('Build image') {
            steps {
                script {
                    env.REGISTRY = ecrLogin(
                        region: params.AWS_REGION,
                        useInstanceProfile: env.USE_INSTANCE_PROFILE == 'true'
                    )
                    env.IMAGE = "${env.REGISTRY}/${env.SERVICE}:${env.TAG}"
                    echo "Building ${env.IMAGE}"
                    buildImage(image: env.IMAGE, context: env.CONTEXT, dockerfile: env.DOCKERFILE)
                }
            }
        }

        stage('Scan image') {
            when {
                expression { !params.SKIP_SCAN }
            }
            steps {
                script {
                    trivyScan(
                        image: env.IMAGE,
                        name: env.SERVICE,
                        severity: params.SCAN_SEVERITY,
                        exitOnFindings: true
                    )
                }
            }
        }

        stage('Push to ECR') {
            steps {
                script {
                    pushImage(image: env.IMAGE)
                }
            }
        }

        stage('Cleanup local image') {
            steps {
                script {
                    cleanupImage(image: env.IMAGE, prune: true)
                }
            }
        }

        stage('Update Kubernetes manifests') {
            when {
                expression {
                    params.UPDATE_MANIFESTS && env.GIT_BRANCH == 'main'
                }
            }
            steps {
                script {
                    updateManifests(
                        name: env.SERVICE,
                        image: "${env.REGISTRY}/${env.SERVICE}",
                        tag: env.TAG,
                        overlay: env.OVERLAY,
                        branch: env.GIT_BRANCH,
                        sshCredentialsId: 'github-ssh'
                    )
                }
            }
        }
    }

    post {
        always {
            archiveArtifacts artifacts: 'reports/**', allowEmptyArchive: true, fingerprint: true
            sh 'docker system df || true'
        }
        success {
            echo "Deployed ${env.SERVICE}:${env.TAG}"
        }
        failure {
            echo "Pipeline failed for ${env.SERVICE} (${env.BUILD_NUMBER})"
        }
        cleanup {
            cleanWs(deleteDirs: true, notFailBuild: true)
        }
    }
}

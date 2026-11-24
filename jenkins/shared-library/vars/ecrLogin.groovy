/**
 * Log in to Amazon ECR and return the registry host, e.g.
 *   123456789012.dkr.ecr.us-east-1.amazonaws.com
 *
 * Credentials (all of type "Secret text"):
 *   aws-account-id        -> 12 digit account id
 *   aws-access-key-id     -> IAM access key
 *   aws-secret-access-key -> IAM secret key
 *
 * On EC2 the instance profile is used automatically instead; pass
 * useInstanceProfile: true (optionally with registry:).
 *
 * Usage:
 *   def registry = ecrLogin(region: 'us-east-1')
 *   def image = "${registry}/frontend:${env.TAG}"
 */
def call(Map args = [:]) {
    String region = args.region ?: 'us-east-1'

    if (args.useInstanceProfile == true) {
        String registry = args.registry ?: sh(
            returnStdout: true,
            script: "aws sts get-caller-identity --query Account --output text --region ${region}"
        ).trim() + ".dkr.ecr.${region}.amazonaws.com"

        withEnv(["REGION=${region}", "REGISTRY=${registry}"]) {
            sh '''
                aws ecr get-login-password --region "$REGION" \
                  | docker login --username AWS --password-stdin "$REGISTRY"
            '''
        }
        return registry
    }

    return withCredentials([
        string(credentialsId: args.accountIdCredentialsId ?: 'aws-account-id', variable: 'AWS_ACCOUNT_ID'),
        string(credentialsId: args.accessKeyCredentialsId ?: 'aws-access-key-id', variable: 'AWS_ACCESS_KEY_ID'),
        string(credentialsId: args.secretKeyCredentialsId ?: 'aws-secret-access-key', variable: 'AWS_SECRET_ACCESS_KEY')
    ]) {
        String registry = args.registry ?: "${env.AWS_ACCOUNT_ID}.dkr.ecr.${region}.amazonaws.com"
        withEnv(["REGION=${region}", "REGISTRY=${registry}"]) {
            sh '''
                aws ecr get-login-password --region "$REGION" \
                  | docker login --username AWS --password-stdin "$REGISTRY"
            '''
        }
        return registry
    }
}

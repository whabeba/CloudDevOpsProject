/**
 * Build a Docker image.
 *
 * Usage:
 *   buildImage(image: "123.dkr.ecr.us-east-1.amazonaws.com/frontend:42",
 *              context: "frontend",
 *              dockerfile: "frontend/Dockerfile")
 */
def call(Map args = [:]) {
    if (!args.image) {
        error("buildImage: 'image' is required")
    }

    String image = args.image
    String context = args.context ?: '.'
    String dockerfile = args.dockerfile ?: "${context}/Dockerfile"
    String buildArgs = args.buildArgs ?: ''
    String extraArgs = args.extraArgs ?: ''

    sh """
        docker build \\
            --pull \\
            --label "org.opencontainers.image.revision=\${GIT_COMMIT}" \\
            --label "org.opencontainers.image.source=\${GIT_URL}" \\
            -t ${image} \\
            -f ${dockerfile} \\
            ${buildArgs} \\
            ${extraArgs} \\
            ${context}
    """
}

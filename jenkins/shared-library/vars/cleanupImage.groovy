/**
 * Remove an image from the Jenkins host after it has been pushed to ECR.
 * Keeps the build workspace (and the EC2 disk) small.
 *
 * Usage:
 *   cleanupImage(image: "123.dkr.ecr.us-east-1.amazonaws.com/frontend:42")
 */
def call(Map args = [:]) {
    if (!args.image) {
        error("cleanupImage: 'image' is required")
    }

    sh """
        docker rmi -f ${args.image} || true
        ${args.prune ? 'docker image prune -af --filter "until=24h" || true' : ''}
    """
}

/**
 * Push an image to its registry.
 *
 * Usage:
 *   pushImage(image: "123.dkr.ecr.us-east-1.amazonaws.com/frontend:42")
 */
def call(Map args = [:]) {
    if (!args.image) {
        error("pushImage: 'image' is required")
    }

    sh "docker push ${args.image}"
}

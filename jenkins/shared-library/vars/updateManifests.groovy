/**
 * Point a Kustomize overlay at a freshly built image and push the change so
 * ArgoCD picks it up (GitOps promotion).
 *
 * Usage:
 *   updateManifests(
 *       name: "frontend",
 *       image: "123.dkr.ecr.us-east-1.amazonaws.com/frontend",
 *       tag: "42",
 *       overlay: "k8s/overlays/prod",
 *       branch: "main",
 *       sshCredentialsId: "github-ssh"
 *   )
 *
 * The commit is only created when the overlay actually changes, so repeated
 * builds of the same tag do not produce empty commits.
 */
def call(Map args = [:]) {
    if (!args.name || !args.image || !args.tag) {
        error("updateManifests: 'name', 'image' and 'tag' are required")
    }

    String name = args.name
    String image = args.image
    String tag = args.tag
    String overlay = args.overlay ?: 'k8s/overlays/prod'
    String file = "${overlay}/kustomization.yaml"
    String branch = args.branch ?: 'main'
    String gitUserName = args.gitUserName ?: 'Jenkins CI'
    String gitUserEmail = args.gitUserEmail ?: 'jenkins@ivolve.local'
    String message = args.message ?: "ci(${name}): deploy ${tag}"

    sh """
        set -e
        test -f ${file}
        awk -v img='${name}' -v tag='${tag}' '
            /^[[:space:]]*-[[:space:]]+name:/ { inblock = (\$3 == img) }
            inblock && /^[[:space:]]+newName:/ { sub(/newName:.*/, "newName: ${image}") }
            inblock && /^[[:space:]]+newTag:/ { sub(/newTag:.*/, "newTag: ${tag}"); inblock = 0 }
            { print }
        ' ${file} > ${file}.tmp
        mv ${file}.tmp ${file}
        git config user.name '${gitUserName}'
        git config user.email '${gitUserEmail}'
        git add ${file}
        if git diff --cached --quiet; then
            echo "Manifests already point at ${name}:${tag}; nothing to commit."
            exit 0
        fi
        git commit -m '${message}'
    """

    if (args.sshCredentialsId) {
        sshagent(credentials: [args.sshCredentialsId]) {
            sh "git push origin HEAD:${branch}"
        }
    } else {
        withCredentials([usernamePassword(
            credentialsId: args.gitCredentialsId ?: 'git-credentials',
            usernameVariable: 'GIT_USER',
            passwordVariable: 'GIT_TOKEN'
        )]) {
            sh """
                set -e
                remote=\$(git remote get-url origin)
                case "\$remote" in
                  https://*) git push "https://\${GIT_USER}:\${GIT_TOKEN}@\${remote#https://}" HEAD:${branch} ;;
                  *)         git push origin HEAD:${branch} ;;
                esac
            """
        }
    }
}

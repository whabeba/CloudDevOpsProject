/**
 * Scan an image with Trivy and fail the build on findings.
 *
 * Usage:
 *   trivyScan(image: "repo:tag", severity: "HIGH,CRITICAL", exitOnFindings: true)
 *
 * The table report is always written to reports/trivy-<name>.txt so the
 * Jenkinsfile can archive it even when the step fails.
 */
def call(Map args = [:]) {
    if (!args.image) {
        error("trivyScan: 'image' is required")
    }

    String image = args.image
    String name = args.name ?: image.replaceAll('[^a-zA-Z0-9]', '_')
    String severity = args.severity ?: 'HIGH,CRITICAL'
    boolean ignoreUnfixed = args.ignoreUnfixed != false
    boolean exitOnFindings = args.exitOnFindings != false
    int timeout = args.timeoutMinutes ?: 15

    sh """
        mkdir -p reports
        trivy image \\
            --no-progress \\
            --scanners vuln \\
            --severity ${severity} \\
            ${ignoreUnfixed ? '--ignore-unfixed' : ''} \\
            --format table \\
            --output reports/trivy-${name}.txt \\
            ${args.withSbom ? "--format cyclonedx --output reports/sbom-${name}.json" : ''} \\
            ${exitOnFindings ? '--exit-code 1' : '--exit-code 0'} \\
            ${image}
    """
}

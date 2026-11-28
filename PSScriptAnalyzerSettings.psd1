# Shared PSScriptAnalyzer settings for CI (`make lint` and .github/workflows/ci.yml).
@{
    Severity     = @('Error', 'Warning')

    ExcludeRules = @(
        # The helpdesk scripts are interactive console tools; coloured Write-Host output is intended.
        'PSAvoidUsingWriteHost'
    )
}

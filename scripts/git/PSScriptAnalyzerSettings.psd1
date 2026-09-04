@{
    # This is an interactive terminal script: colored, non-pipeline status output is intentional.
    # PowerShell 7 reads UTF-8 without a BOM, and PowerShell 5.x is explicitly unsupported.
    ExcludeRules = @(
        'PSAvoidUsingWriteHost'
        'PSUseBOMForUnicodeEncodedFile'
    )
}

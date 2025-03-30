<#
.SYNOPSIS
Generates a large number of unique ASA access-list entries for testing purposes.

.DESCRIPTION
Creates a text file containing a specified number of ASA 'access-list' lines.
Each line follows the format:
access-list INSIDE_OUT extended permit tcp host 10.0.0.1 host 10.1.0.1 eq <port_number>
The port number starts from a base value and increments for each line to ensure uniqueness.

.PARAMETER OutputFile
The path to the output file where the ACL lines will be saved.
Default: 'large_acl_config.txt'

.PARAMETER NumberOfLines
The number of ACL lines to generate.
Default: 50000

.PARAMETER StartPort
The starting port number for the 'eq' part of the ACL.
Default: 10001

.EXAMPLE
.\generate_large_acl.ps1
# Generates 50,000 lines starting from port 10001 into 'large_acl_config.txt'

.EXAMPLE
.\generate_large_acl.ps1 -OutputFile acl_test_100k.txt -NumberOfLines 100000 -StartPort 20000
# Generates 100,000 lines starting from port 20000 into 'acl_test_100k.txt'

.NOTES
Author: AI Assistant
Date:   2023-10-27
Version: 1.0
Consider disk space and potential performance impact when generating very large files.
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$OutputFile = "large_acl_config.txt",

    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 1000000)] # Set a reasonable upper limit
    [int]$NumberOfLines = 50000,

    [Parameter(Mandatory=$false)]
    [ValidateRange(1, 65535)] # Standard port range, though ASA might allow higher
    [int]$StartPort = 10001
)

Write-Host "Generating $NumberOfLines ACL lines into '$OutputFile'..."
Write-Host "Starting port number: $StartPort"

# Prepare the base string format
$aclFormat = "access-list INSIDE_OUT extended permit tcp host 10.0.0.1 host 10.1.0.1 eq {0}"

# Use StreamWriter for better performance with large files
# Ensure using statement handles closing the writer properly, even on error
try {
    # Explicitly use UTF8 encoding without BOM
    $encoding = New-Object System.Text.UTF8Encoding($false)
    $writer = New-Object System.IO.StreamWriter($OutputFile, $false, $encoding) # $false for append=false

    # Loop to generate lines
    for ($i = 0; $i -lt $NumberOfLines; $i++) {
        # Calculate the current port number
        # Check if calculated port exceeds a reasonable limit (e.g., 65535, though ASA might handle larger)
        $currentPort = $StartPort + $i
        if ($currentPort -gt 65535) {
             Write-Warning "Generated port number $currentPort exceeds 65535. Continuing generation."
             # Or potentially stop:
             # Write-Error "Generated port number $currentPort exceeds 65535. Stopping generation."
             # break
        }

        # Format the ACL string
        $aclLine = $aclFormat -f $currentPort

        # Write the line to the file
        $writer.WriteLine($aclLine)

        # Optionally provide progress update for very large numbers
        if (($i + 1) % 10000 -eq 0) {
            Write-Host "Generated $(($i + 1)) lines..."
        }
    }
}
catch {
    Write-Error "An error occurred during file generation: $($_.Exception.Message)"
}
finally {
    # Ensure the writer is closed and disposed
    if ($writer -ne $null) {
        $writer.Close()
        $writer.Dispose()
    }
}

Write-Host "Finished generating $NumberOfLines ACL lines."
Write-Host "Output saved to: $OutputFile"

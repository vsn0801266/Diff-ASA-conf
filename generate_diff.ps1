<#
.SYNOPSIS
Compares two ASA configuration files (old and new) and generates difference commands,
handling object network parent/child removal, object-group member removal context,
prioritizing removal command order based on dependencies, adding separators, and preserving indent on 'no' commands.
Outputs processing time and a summary of changes.

.DESCRIPTION
Reads 'old_conf.txt' and 'new_conf.txt', identifies the differences,
and outputs commands to 'diff_commands.txt' that transform the old configuration
into the new one. Lines only in old_conf get a 'no ' prefix (unless they already
start with 'no ', in which case the 'no ' is removed). Lines only in new_conf are output as is.
Removal commands are prioritized and separated by '!': 1. ACLs, 2. Group Members, 3. Groups, 4. Objects, 5. Others.
Handles 'object network'/'host'/'subnet' parent/child removal and 'object-group network' member context.
'no' commands retain the original line's indentation.
Outputs total processing time and a summary count of added/removed lines and generated removal commands by type.

.PARAMETER OldConfigFile
Path to the old configuration file. Default: 'old_conf.txt'

.PARAMETER NewConfigFile
Path to the new configuration file. Default: 'new_conf.txt'

.PARAMETER DiffOutputFile
Path to the output file for difference commands. Default: 'diff_commands.txt'

.EXAMPLE
.\generate_diff.ps1

.EXAMPLE
.\generate_diff.ps1 -OldConfigFile .\configs\current.cfg -NewConfigFile .\configs\proposed.cfg -DiffOutputFile .\output\delta.txt

.NOTES
Author: AI Assistant
Date:   2023-10-27
Version: 2.0 (Add processing time, detailed summary, Fix HashSet creation, Add priority separators, Preserve indent, Prioritize removal order, Add context, Handle object child removal)
Requires: PowerShell
Encoding: Assumes UTF-8 primarily, falls back to system default for input. Outputs UTF-8.
Review the output file carefully before applying commands to a device. Performance on extremely large files (>50k lines) might vary.
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$OldConfigFile = "old_conf.txt",

    [Parameter(Mandatory=$false)]
    [string]$NewConfigFile = "new_conf.txt",

    [Parameter(Mandatory=$false)]
    [string]$DiffOutputFile = "diff_commands.txt"
)

# --- Start Timer ---
$startTime = Get-Date
Write-Host "Starting comparison of '$OldConfigFile' and '$NewConfigFile' at $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))..."

# --- Function to read and preprocess file content (returns ordered array) ---
function Get-ProcessedContent {
    param(
        [string]$FilePath
    )
    if (-not (Test-Path $FilePath)) {
        Write-Error "Error: File not found at $FilePath"
        return $null
    }
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $lines = [System.Collections.Generic.List[string]]::new()
    try {
        # Optimization: Read all lines at once if memory allows
        $allLines = Get-Content $FilePath -Encoding UTF8 -ErrorAction Stop -ReadCount 0 # Read all lines
        foreach($line in $allLines) {
             if ($line.Length -gt 0 -or $line.Trim().Length -gt 0) { $lines.Add($line) }
        }
        Write-Verbose "Successfully read $FilePath as UTF-8"
    } catch [System.Text.DecoderFallbackException] {
        Write-Warning "Failed to read $FilePath as UTF-8. Retrying with system default encoding."
        $lines.Clear()
        try {
            $allLines = Get-Content $FilePath -Encoding Default -ErrorAction Stop -ReadCount 0
             foreach($line in $allLines) {
                 if ($line.Length -gt 0 -or $line.Trim().Length -gt 0) { $lines.Add($line) }
             }
            Write-Verbose "Successfully read $FilePath with system default encoding"
        } catch {
             Write-Error "Error reading file ${FilePath} even with default encoding: $($_.Exception.Message)"
             return $null
        }
    } catch {
        Write-Error "Error reading file ${FilePath}: $($_.Exception.Message)"
        return $null
    } finally {
        $sw.Stop()
        Write-Verbose "Reading $FilePath took $($sw.Elapsed.TotalMilliseconds) ms"
    }
    return $lines.ToArray()
}

# --- Read and process files ---
$oldLinesOriginal = Get-ProcessedContent -FilePath $OldConfigFile
$newLinesOriginal = Get-ProcessedContent -FilePath $NewConfigFile

if ($null -eq $oldLinesOriginal -or $null -eq $newLinesOriginal) {
    Write-Error "Aborting due to file reading errors."
    if (-not (Test-Path $OldConfigFile)) { Write-Error "$OldConfigFile not found."}
    if (-not (Test-Path $NewConfigFile)) { Write-Error "$NewConfigFile not found."}
    exit 1
}

# Create trimmed versions for set-based comparison
Write-Host "Processing lines..."
$swProc = [System.Diagnostics.Stopwatch]::StartNew()
$oldLinesTrimmed = $oldLinesOriginal | ForEach-Object { $_.Trim() } | Where-Object { $_ }
$newLinesTrimmed = $newLinesOriginal | ForEach-Object { $_.Trim() } | Where-Object { $_ }

$oldLinesTrimmedSet = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::Ordinal)
$newLinesTrimmedSet = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::Ordinal)

# Populate HashSets (measure this part?)
if ($null -ne $oldLinesTrimmed) { foreach ($line in $oldLinesTrimmed) { $null = $oldLinesTrimmedSet.Add($line) } }
if ($null -ne $newLinesTrimmed) { foreach ($line in $newLinesTrimmed) { $null = $newLinesTrimmedSet.Add($line) } }
$swProc.Stop()
Write-Verbose "Line trimming and HashSet population took $($swProc.Elapsed.TotalMilliseconds) ms"


# --- Calculate Differences ---
Write-Host "Calculating differences..."
$swDiff = [System.Diagnostics.Stopwatch]::StartNew()
# Find lines present only in the old config (candidates for removal)
$removedLinesCandidates = @{} # Hashtable: original line index -> trimmed line
for ($i = 0; $i -lt $oldLinesOriginal.Length; $i++) {
    $trimmed = $oldLinesOriginal[$i].Trim()
    if ($trimmed -and -not $newLinesTrimmedSet.Contains($trimmed)) {
        $removedLinesCandidates[$i] = $trimmed
    }
}

# Find lines present only in the new config (candidates for addition)
$addedLinesOriginal = [System.Collections.Generic.List[string]]::new()
for ($i = 0; $i -lt $newLinesOriginal.Length; $i++) {
     $trimmed = $newLinesOriginal[$i].Trim()
     if ($trimmed -and -not $oldLinesTrimmedSet.Contains($trimmed)) {
         $addedLinesOriginal.Add($newLinesOriginal[$i])
     }
}
$swDiff.Stop()
Write-Verbose "Difference calculation took $($swDiff.Elapsed.TotalMilliseconds) ms"

Write-Host "Found $($removedLinesCandidates.Count) lines (trimmed comparison) present only in '$OldConfigFile'."
Write-Host "Found $($addedLinesOriginal.Count) lines (trimmed comparison) present only in '$NewConfigFile'."

$outputCommands = [System.Collections.Generic.List[string]]::new()
$outputCommands.Add("! Difference commands to transition from $OldConfigFile to $NewConfigFile")
$outputCommands.Add("!")

# --- Initialize Summary Counters ---
$summary = @{
    AddedLines = $addedLinesOriginal.Count
    RemovedCandidates = $removedLinesCandidates.Count
    GeneratedRemovals = 0
    Priority1_ACL = 0
    Priority2_GroupMember = 0
    Priority3_Group = 0
    Priority4_Object = 0
    Priority5_Other = 0
    Priority99_Warning = 0
    SkippedObjectChildren = 0 # Counter for specifically skipped children
}

# --- Generate removal/reversal commands ---
if ($removedLinesCandidates.Count -gt 0) {
    $outputCommands.Add("! --- Commands to remove/reverse lines from old config (prioritized) ---")
    Write-Host "Generating removal commands..."
    $swRemoveGen = [System.Diagnostics.Stopwatch]::StartNew()

    $removedTrimmedSetForCheck = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::Ordinal)
    if ($null -ne $removedLinesCandidates) {
        foreach ($trimmedLine in $removedLinesCandidates.Values) {
            if ($trimmedLine) { $null = $removedTrimmedSetForCheck.Add($trimmedLine) }
        }
    }

    $removalCommandsWithDetails = [System.Collections.Generic.List[object]]::new()

    foreach ($i in ($removedLinesCandidates.Keys | Sort-Object)) {
        $currentOriginalLine = $oldLinesOriginal[$i]
        $currentTrimmedLine = $removedLinesCandidates[$i]

        if (-not $removedTrimmedSetForCheck.Contains($currentTrimmedLine)) { continue }

        $skipOutput = $false
        $parentContext = $null
        $generatedCommand = $null
        $priority = 5
        $indent = ""

        if ($currentOriginalLine -match '^(\s+)') { $indent = $matches[1] }

        # Determine Command Type and Priority
        if ($currentTrimmedLine.StartsWith("access-list ")) { $priority = 1 }
        elseif ($indent.Length -gt 0 -and ($currentTrimmedLine.StartsWith("network-object ") -or $currentTrimmedLine.StartsWith("service-object ") -or $currentTrimmedLine.StartsWith("group-object ") )) {
             for ($j = $i - 1; $j -ge 0; $j--) {
                $potentialParentOriginal = $oldLinesOriginal[$j]; $potentialParentTrimmed = $potentialParentOriginal.Trim()
                if (-not $potentialParentOriginal.StartsWith(" ") -and $potentialParentTrimmed.StartsWith("object-group ")) { $parentContext = $potentialParentTrimmed; break }
                elseif (-not $potentialParentOriginal.StartsWith(" ")) { break }
             }
             if ($parentContext) { $priority = 2 } else { $priority = 5 }
        }
        elseif ($currentTrimmedLine.StartsWith("object-group ")) { $priority = 3 }
        elseif ($currentTrimmedLine.StartsWith("object ")) { $priority = 4 }
        elseif ($indent.Length -gt 0 -and ($currentTrimmedLine.StartsWith("host ") -or $currentTrimmedLine.StartsWith("subnet ") -or $currentTrimmedLine.StartsWith("service "))) {
            if ($i -gt 0) {
                $previousOriginalLine = $oldLinesOriginal[$i - 1]; $previousTrimmedLine = $previousOriginalLine.Trim()
                if ($previousTrimmedLine.StartsWith("object ") -and $removedTrimmedSetForCheck.Contains($previousTrimmedLine)) {
                    $skipOutput = $true; $summary.SkippedObjectChildren++ # Increment skip counter
                    Write-Verbose "Skipping 'no' for '$currentTrimmedLine' because parent '$previousTrimmedLine' is also being removed."
                }
            }
        }

        # Generate the actual command
        if (-not $skipOutput) {
            if ($currentTrimmedLine.StartsWith("no ", [System.StringComparison]::OrdinalIgnoreCase)) {
                $commandPart = $currentTrimmedLine.Substring(3).TrimStart()
                if ($commandPart) {
                    $generatedCommand = $commandPart
                    if ($commandPart.StartsWith("access-list ")) { $priority = 1 }
                } else {
                     $generatedCommand = "! Warning: Could not parse command to remove 'no': $currentTrimmedLine"; $priority = 99
                }
            } else {
                $generatedCommand = "no $currentTrimmedLine"
            }

            $details = [PSCustomObject]@{ Priority = $priority; Context = $parentContext; Indent = $indent; Command = $generatedCommand }
            $removalCommandsWithDetails.Add($details)

            # Increment summary counters based on final priority
            $summary.GeneratedRemovals++
            switch ($priority) {
                1  { $summary.Priority1_ACL++ }
                2  { $summary.Priority2_GroupMember++ }
                3  { $summary.Priority3_Group++ }
                4  { $summary.Priority4_Object++ }
                5  { $summary.Priority5_Other++ }
                99 { $summary.Priority99_Warning++ }
            }
        }
    }
    $swRemoveGen.Stop()
    Write-Verbose "Removal command generation took $($swRemoveGen.Elapsed.TotalMilliseconds) ms"

    # Sort by Priority, then Context (nulls first), then Command
    Write-Host "Sorting removal commands..."
    $swSort = [System.Diagnostics.Stopwatch]::StartNew()
    $sortedRemovalCommands = $removalCommandsWithDetails | Sort-Object Priority, @{Expression={$_.Context -eq $null}; Descending=$true}, Context, Command
    $swSort.Stop()
    Write-Verbose "Sorting removal commands took $($swSort.Elapsed.TotalMilliseconds) ms"


    # Output the sorted removal commands, adding context and priority separators
    $lastContext = -join ("UniqueString", (Get-Random))
    $lastPriority = -1
    foreach ($item in $sortedRemovalCommands) {
        if ($item.Priority -ne $lastPriority -and $lastPriority -ne -1) {
             $outputCommands.Add("!"); $lastContext = -join ("UniqueString", (Get-Random))
        }
        if ($item.Priority -eq 2 -and $null -ne $item.Context -and $item.Context -ne $lastContext) {
            $outputCommands.Add($item.Context); $lastContext = $item.Context
        }
        elseif ($item.Priority -ne 2 -or $null -eq $item.Context) {
             $lastContext = -join ("UniqueString", (Get-Random))
        }
        $outputCommands.Add(($item.Indent + $item.Command))
        $lastPriority = $item.Priority
    }
    if ($sortedRemovalCommands.Count -gt 0) { $outputCommands.Add("!") }

} else {
     $outputCommands.Add("! No lines to remove from old config.")
     $outputCommands.Add("!")
}

# --- Generate addition commands ---
if ($addedLinesOriginal.Count -gt 0) {
    $outputCommands.Add("! --- Commands to add lines from new config (in original order) ---")
    Write-Host "Adding addition commands..."
    # Addition is simple list copy, usually very fast
    foreach ($line in $addedLinesOriginal) { $outputCommands.Add($line) }
    $outputCommands.Add("!")
} else {
     $outputCommands.Add("! No new lines to add from new config.")
     $outputCommands.Add("!")
}

# --- Write commands to output file ---
Write-Host "Writing output file '$DiffOutputFile'..."
$swWrite = [System.Diagnostics.Stopwatch]::StartNew()
try {
    Set-Content -Path $DiffOutputFile -Value $outputCommands -Encoding UTF8 -Force -ErrorAction Stop
    $swWrite.Stop()
    Write-Verbose "Writing output file took $($swWrite.Elapsed.TotalMilliseconds) ms"
    Write-Host "Difference commands successfully written to '$DiffOutputFile'"

    # --- Stop Timer and Print Summary ---
    $endTime = Get-Date
    $elapsedTime = $endTime - $startTime

    Write-Host "`n--- Processing Summary ---"
    Write-Host "Comparison started : $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Host "Comparison finished: $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    Write-Host ("Total processing time: {0:N2} seconds" -f $elapsedTime.TotalSeconds)
    Write-Host "--------------------------"
    Write-Host "Lines added          : $($summary.AddedLines)"
    Write-Host "Lines removed (total): $($summary.RemovedCandidates)"
    Write-Host "  Generated 'no'/'rev' commands: $($summary.GeneratedRemovals)"
    Write-Host "    - Priority 1 (ACLs)        : $($summary.Priority1_ACL)"
    Write-Host "    - Priority 2 (Group Members): $($summary.Priority2_GroupMember)"
    Write-Host "    - Priority 3 (Groups)      : $($summary.Priority3_Group)"
    Write-Host "    - Priority 4 (Objects)     : $($summary.Priority4_Object)"
    Write-Host "    - Priority 5 (Others)      : $($summary.Priority5_Other)"
    Write-Host "    - Skipped (Object Children): $($summary.SkippedObjectChildren)"
    Write-Host "    - Warnings (Parse Errors)  : $($summary.Priority99_Warning)"
    Write-Host "--------------------------"


    Write-Host "`n--- Important Considerations ---"
    Write-Host "1. Review Output: Carefully review '$DiffOutputFile' before applying."
    Write-Host "2. Command Order: Removal commands are prioritized and separated by '!'. Added lines retain order."
    Write-Host "3. Modified Lines: Appear as a 'no <old>' (with indent) and '<new>' pair (comparison based on trimmed)."
    Write-Host "4. 'no' Reversal: Check if the reversal logic for removed 'no' commands is correct."
    Write-Host "5. Context: Removal context for object children and group members handled. Check priorities if needed."
    Write-Host "6. Indentation: 'no' commands retain original indentation. Added commands retain original format."
    Write-Host "7. Encoding: Input files were attempted as UTF-8 then system default. Output is UTF-8."
    Write-Host "8. Trimming: Comparison logic uses trimmed lines, but output formatting uses original lines where possible."

} catch {
    $swWrite.Stop()
    Write-Error "Error writing output file ${DiffOutputFile}: $($_.Exception.Message)"
    exit 1
}

Write-Host "Script finished."

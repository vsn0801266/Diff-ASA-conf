<#
.SYNOPSIS
Compares two ASA configuration files (old and new) and generates difference commands,
handling object network parent/child removal, object-group member removal context,
prioritizing removal command order based on dependencies, adding separators, and preserving indent on 'no' commands.
Outputs processing time and a detailed summary of changes with colored console output. Allows selection of priorities to output and optional removal command generation to file.

.DESCRIPTION
Reads 'old_conf.txt' and 'new_conf.txt', identifies the differences,
and outputs commands to 'diff_commands.txt'.
- Added lines are always output to the file.
- Removal commands ('no ...' or reversed 'no no ...') are processed and prioritized:
  1. ACLs, 2. Group Members, 3. Groups, 4. Objects, 5. Others, 99. Warnings.
- By default (-GenerateRemovalCommands switch NOT present), removal commands are printed to the standard output (console) in Red.
- If -GenerateRemovalCommands switch IS present, removal commands with priorities specified in -IncludePriority (default: 1,2,3,4) are output to the file, separated by '!', with context and original indentation.
- 'object network' child lines ('host','subnet','service') are skipped if the parent 'object network' is also removed; skipped lines are printed to standard output in Yellow.
- Other informational messages and summary are printed in Blue.

.PARAMETER OldConfigFile
Path to the old configuration file. Default: 'old_conf.txt'

.PARAMETER NewConfigFile
Path to the new configuration file. Default: 'new_conf.txt'

.PARAMETER DiffOutputFile
Path to the output file for difference commands. Default: 'diff_commands.txt'

.PARAMETER IncludePriority
An array of integer priorities for removal commands to include in the output file when -GenerateRemovalCommands is specified.
Default: @(1, 2, 3, 4) (ACLs, Group Members, Groups, Objects)
Valid priorities: 1, 2, 3, 4, 5, 99.

.PARAMETER GenerateRemovalCommands
Switch parameter. If present, generates prioritized removal commands (filtered by -IncludePriority) into the output file.
If absent (default), removal commands are printed to the standard output only (in Red).

.EXAMPLE
# Default behavior: Show removals (Red) and skipped (Yellow) on console, output additions to file
.\generate_diff.ps1

.EXAMPLE
# Generate removals (Priorities 1-4) and additions to file, show skipped (Yellow) on console
.\generate_diff.ps1 -GenerateRemovalCommands

.NOTES
Author: T.K
Date:   2025-03-31
Version: 2.2 (Colored console output, Selectable output priority, Optional removal generation, Skipped output to console, Counter refinement, Fix HashSet creation, Add priority separators, Preserve indent, Prioritize removal order, Add context, Handle object child removal)
Requires: PowerShell (Colors might vary based on console settings)
Encoding: Assumes UTF-8 primarily, falls back to system default for input. Outputs UTF-8.
Review the output file and console output carefully. Performance on extremely large files might vary.
#>
param(
    [Parameter(Mandatory=$false)]
    [string]$OldConfigFile = "old_conf.txt",

    [Parameter(Mandatory=$false)]
    [string]$NewConfigFile = "new_conf.txt",

    [Parameter(Mandatory=$false)]
    [string]$DiffOutputFile = "diff_commands.txt",

    [Parameter(Mandatory=$false)]
    [ValidateSet(1,2,3,4,5,99)]
    [int[]]$IncludePriority = @(1, 2, 3, 4),

    [Parameter(Mandatory=$false)]
    [switch]$GenerateRemovalCommands
)

# --- Start Timer & Initial Messages ---
$startTime = Get-Date
Write-Host "Starting comparison of '$OldConfigFile' and '$NewConfigFile' at $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))..." -ForegroundColor Blue
Write-Host "Generate Removal Commands to File: $($GenerateRemovalCommands.IsPresent)" -ForegroundColor Blue
if ($GenerateRemovalCommands.IsPresent) {
    Write-Host "Included Removal Priorities for File Output: $($IncludePriority -join ', ')" -ForegroundColor Blue
} else {
    Write-Host "Removal commands will be shown on console only (in Red)." -ForegroundColor Blue
}

# --- Function to read and preprocess file content ---
function Get-ProcessedContent {
    param([string]$FilePath)
    # ... (Function remains the same) ...
    if (-not (Test-Path $FilePath)) { Write-Error "Error: File not found at $FilePath"; return $null }
    $sw = [System.Diagnostics.Stopwatch]::StartNew(); $lines = [System.Collections.Generic.List[string]]::new()
    try { $allLines = Get-Content $FilePath -Encoding UTF8 -ErrorAction Stop -ReadCount 0; foreach($line in $allLines) { if ($line.Length -gt 0 -or $line.Trim().Length -gt 0) { $lines.Add($line) } }; Write-Verbose "Successfully read $FilePath as UTF-8" }
    catch [System.Text.DecoderFallbackException] { Write-Warning "Failed to read $FilePath as UTF-8. Retrying with system default encoding."; $lines.Clear(); try { $allLines = Get-Content $FilePath -Encoding Default -ErrorAction Stop -ReadCount 0; foreach($line in $allLines) { if ($line.Length -gt 0 -or $line.Trim().Length -gt 0) { $lines.Add($line) } } ; Write-Verbose "Successfully read $FilePath with system default encoding" } catch { Write-Error "Error reading file ${FilePath} even with default encoding: $($_.Exception.Message)"; return $null } }
    catch { Write-Error "Error reading file ${FilePath}: $($_.Exception.Message)"; return $null }
    finally { $sw.Stop(); Write-Verbose "Reading $FilePath took $($sw.Elapsed.TotalMilliseconds) ms" }
    return $lines.ToArray()
}

# --- Read and process files ---
$oldLinesOriginal = Get-ProcessedContent -FilePath $OldConfigFile
$newLinesOriginal = Get-ProcessedContent -FilePath $NewConfigFile
if ($null -eq $oldLinesOriginal -or $null -eq $newLinesOriginal) { Write-Error "Aborting due to file reading errors."; exit 1 }

Write-Host "Processing lines..." -ForegroundColor Blue
# ... (Line processing and HashSet population remains the same) ...
$swProc = [System.Diagnostics.Stopwatch]::StartNew(); $oldLinesTrimmed = $oldLinesOriginal | ForEach-Object { $_.Trim() } | Where-Object { $_ }; $newLinesTrimmed = $newLinesOriginal | ForEach-Object { $_.Trim() } | Where-Object { $_ }; $oldLinesTrimmedSet = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::Ordinal); $newLinesTrimmedSet = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::Ordinal); if ($null -ne $oldLinesTrimmed) { foreach ($line in $oldLinesTrimmed) { $null = $oldLinesTrimmedSet.Add($line) } }; if ($null -ne $newLinesTrimmed) { foreach ($line in $newLinesTrimmed) { $null = $newLinesTrimmedSet.Add($line) } }; $swProc.Stop(); Write-Verbose "Line trimming and HashSet population took $($swProc.Elapsed.TotalMilliseconds) ms"

# --- Calculate Differences ---
Write-Host "Calculating differences..." -ForegroundColor Blue
# ... (Difference calculation remains the same) ...
$swDiff = [System.Diagnostics.Stopwatch]::StartNew(); $removedLinesCandidates = @{}; for ($i = 0; $i -lt $oldLinesOriginal.Length; $i++) { $trimmed = $oldLinesOriginal[$i].Trim(); if ($trimmed -and -not $newLinesTrimmedSet.Contains($trimmed)) { $removedLinesCandidates[$i] = $trimmed } }; $addedLinesOriginal = [System.Collections.Generic.List[string]]::new(); for ($i = 0; $i -lt $newLinesOriginal.Length; $i++) { $trimmed = $newLinesOriginal[$i].Trim(); if ($trimmed -and -not $oldLinesTrimmedSet.Contains($trimmed)) { $addedLinesOriginal.Add($newLinesOriginal[$i]) } }; $swDiff.Stop(); Write-Verbose "Difference calculation took $($swDiff.Elapsed.TotalMilliseconds) ms"

$initialRemovedCount = $removedLinesCandidates.Count
$initialAddedCount = $addedLinesOriginal.Count
Write-Host "Found $initialRemovedCount lines present only in '$OldConfigFile' (removal candidates)." -ForegroundColor Blue
Write-Host "Found $initialAddedCount lines present only in '$NewConfigFile' (to be added)." -ForegroundColor Blue

# --- Initialize Summary Counters ---
$summary = @{ AddedLines = $initialAddedCount; RemovedCandidates = $initialRemovedCount; GeneratedRemovals = 0; Priority1_ACL = 0; Priority2_GroupMember = 0; Priority3_Group = 0; Priority4_Object = 0; Priority5_Other = 0; Priority99_Warning = 0; SkippedObjectChildren = 0 }

# List to store processed removal command details
$removalCommandsWithDetails = [System.Collections.Generic.List[object]]::new()

# --- Process Removal Candidates ---
if ($removedLinesCandidates.Count -gt 0) {
    Write-Host "Processing removal candidates..." -ForegroundColor Blue
    $swRemoveGen = [System.Diagnostics.Stopwatch]::StartNew()
    $removedTrimmedSetForCheck = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::Ordinal)
    if ($null -ne $removedLinesCandidates) { foreach ($trimmedLine in $removedLinesCandidates.Values) { if ($trimmedLine) { $null = $removedTrimmedSetForCheck.Add($trimmedLine) } } }

    foreach ($i in ($removedLinesCandidates.Keys | Sort-Object)) {
        $currentOriginalLine = $oldLinesOriginal[$i]; $currentTrimmedLine = $removedLinesCandidates[$i]
        if (-not $removedTrimmedSetForCheck.Contains($currentTrimmedLine)) { continue }
        $skipOutput = $false; $parentContext = $null; $generatedCommand = $null; $priority = 5; $indent = ""
        if ($currentOriginalLine -match '^(\s+)') { $indent = $matches[1] }

        # Determine Command Type and Priority
        # ... (Priority logic remains the same) ...
        if ($currentTrimmedLine.StartsWith("access-list ")) { $priority = 1 }
        elseif ($indent.Length -gt 0 -and ($currentTrimmedLine.StartsWith("network-object ") -or $currentTrimmedLine.StartsWith("service-object ") -or $currentTrimmedLine.StartsWith("group-object ") )) { for ($j = $i - 1; $j -ge 0; $j--) { $potentialParentOriginal = $oldLinesOriginal[$j]; $potentialParentTrimmed = $potentialParentOriginal.Trim(); if (-not $potentialParentOriginal.StartsWith(" ") -and $potentialParentTrimmed.StartsWith("object-group ")) { $parentContext = $potentialParentTrimmed; break }; elseif (-not $potentialParentOriginal.StartsWith(" ")) { break } }; if ($parentContext) { $priority = 2 } else { $priority = 5 } }
        elseif ($currentTrimmedLine.StartsWith("object-group ")) { $priority = 3 }
        elseif ($currentTrimmedLine.StartsWith("object ")) { $priority = 4 }
        elseif ($indent.Length -gt 0 -and ($currentTrimmedLine.StartsWith("host ") -or $currentTrimmedLine.StartsWith("subnet ") -or $currentTrimmedLine.StartsWith("service "))) {
            if ($i -gt 0) { $previousOriginalLine = $oldLinesOriginal[$i - 1]; $previousTrimmedLine = $previousOriginalLine.Trim(); if ($previousTrimmedLine.StartsWith("object ") -and $removedTrimmedSetForCheck.Contains($previousTrimmedLine)) {
                    $skipOutput = $true; $summary.SkippedObjectChildren++;
                    # --- MODIFIED: Output Skipped Line in Yellow ---
                    Write-Host "[Skipped]: $($indent)no $currentTrimmedLine (Parent object also removed)" -ForegroundColor Yellow
                 } }
        }

        # Generate the actual command
        if (-not $skipOutput) {
            if ($currentTrimmedLine.StartsWith("no ", [System.StringComparison]::OrdinalIgnoreCase)) { $commandPart = $currentTrimmedLine.Substring(3).TrimStart(); if ($commandPart) { $generatedCommand = $commandPart; if ($commandPart.StartsWith("access-list ")) { $priority = 1 } } else { $generatedCommand = "! Warning: Could not parse command to remove 'no': $currentTrimmedLine"; $priority = 99 } }
            else { $generatedCommand = "no $currentTrimmedLine" }
            $details = [PSCustomObject]@{ Priority = $priority; Context = $parentContext; Indent = $indent; Command = $generatedCommand }
            $removalCommandsWithDetails.Add($details)
            $summary.GeneratedRemovals++; switch ($priority) { 1 { $summary.Priority1_ACL++ }; 2 { $summary.Priority2_GroupMember++ }; 3 { $summary.Priority3_Group++ }; 4 { $summary.Priority4_Object++ }; 5 { $summary.Priority5_Other++ }; 99 { $summary.Priority99_Warning++ } }
        }
    }
    $swRemoveGen.Stop()
    Write-Verbose "Removal command processing took $($swRemoveGen.Elapsed.TotalMilliseconds) ms"
}

# --- Prepare Output Commands ---
$outputCommands = [System.Collections.Generic.List[string]]::new()
$outputCommands.Add("! Difference commands to transition from $OldConfigFile to $NewConfigFile")
$outputCommands.Add("! Generated on $(Get-Date)")
$outputCommands.Add("!")

# --- Handle Removal Commands (Output to File or Console) ---
if ($removalCommandsWithDetails.Count -gt 0) {
    Write-Host "Sorting removal commands..." -ForegroundColor Blue
    $swSort = [System.Diagnostics.Stopwatch]::StartNew()
    $sortedRemovalCommands = $removalCommandsWithDetails | Sort-Object Priority, @{Expression={$_.Context -eq $null}; Descending=$true}, Context, Command
    $swSort.Stop()
    Write-Verbose "Sorting removal commands took $($swSort.Elapsed.TotalMilliseconds) ms"

    if ($GenerateRemovalCommands.IsPresent) {
        # --- Output Removals to FILE ---
        Write-Host "Adding selected removal commands to output file list..." -ForegroundColor Blue
        $outputCommands.Add("! --- prioritized removal commands (Output to file enabled, Priorities: $($IncludePriority -join ', ')) ---")
        # ... (File output logic remains the same) ...
        $lastContext = -join ("UniqueString", (Get-Random)); $lastPriority = -1; $outputtedRemovalCount = 0
        foreach ($item in $sortedRemovalCommands) { if ($item.Priority -in $IncludePriority) { if ($item.Priority -ne $lastPriority -and $lastPriority -ne -1) { $outputCommands.Add("!"); $lastContext = -join ("UniqueString", (Get-Random)) }; if ($item.Priority -eq 2 -and $null -ne $item.Context -and $item.Context -ne $lastContext) { $outputCommands.Add($item.Context); $lastContext = $item.Context }; elseif ($item.Priority -ne 2 -or $null -eq $item.Context) { $lastContext = -join ("UniqueString", (Get-Random)) }; $outputCommands.Add(($item.Indent + $item.Command)); $lastPriority = $item.Priority; $outputtedRemovalCount++ } }; if ($outputtedRemovalCount -gt 0) { $outputCommands.Add("!") }
        Write-Host "$outputtedRemovalCount removal commands added to file list based on included priorities." -ForegroundColor Blue

    } else {
        # --- Output Removals to CONSOLE ---
        Write-Host "`n--- Removal Commands (Output to Console Only) ---" -ForegroundColor Blue
        $outputCommands.Add("! --- removal commands omitted from file (output to console) ---")
        $lastContext = -join ("UniqueString", (Get-Random)); $lastPriority = -1
        foreach ($item in $sortedRemovalCommands) {
             if ($item.Priority -ne $lastPriority -and $lastPriority -ne -1) { Write-Host "!" -ForegroundColor Blue; $lastContext = -join ("UniqueString", (Get-Random)) } # Blue separator
             if ($item.Priority -eq 2 -and $null -ne $item.Context -and $item.Context -ne $lastContext) { Write-Host "[CONTEXT] $($item.Context)" -ForegroundColor Cyan; $lastContext = $item.Context } # Cyan context
             elseif ($item.Priority -ne 2 -or $null -eq $item.Context) { $lastContext = -join ("UniqueString", (Get-Random)) }
             # --- MODIFIED: Output Removal Command in Red ---
             Write-Host "[REMOVAL (P$($item.Priority))] $($item.Indent)$($item.Command)" -ForegroundColor Red
             $lastPriority = $item.Priority
        }
         Write-Host "--- End of Removal Commands (Console Output) ---`n" -ForegroundColor Blue
         $outputCommands.Add("!")
    }
} else {
     $outputCommands.Add("! No removal commands generated.")
     $outputCommands.Add("!")
}

# --- Generate addition commands ---
if ($addedLinesOriginal.Count -gt 0) {
    $outputCommands.Add("! --- Commands to add lines from new config (in original order) ---")
    Write-Host "Adding addition commands to output file list..." -ForegroundColor Blue
    foreach ($line in $addedLinesOriginal) { $outputCommands.Add($line) }
    $outputCommands.Add("!")
} else {
     $outputCommands.Add("! No new lines to add from new config.")
     $outputCommands.Add("!")
}

# --- Write commands to output file ---
Write-Host "Writing output file '$DiffOutputFile'..." -ForegroundColor Blue
$swWrite = [System.Diagnostics.Stopwatch]::StartNew()
try {
    Set-Content -Path $DiffOutputFile -Value $outputCommands -Encoding UTF8 -Force -ErrorAction Stop
    $swWrite.Stop()
    Write-Verbose "Writing output file took $($swWrite.Elapsed.TotalMilliseconds) ms"
    Write-Host "Difference commands successfully written to '$DiffOutputFile'" -ForegroundColor Green # Green for success

    # --- Stop Timer and Print Summary ---
    $endTime = Get-Date
    $elapsedTime = $endTime - $startTime

    Write-Host "`n--- Processing Summary ---" -ForegroundColor Blue
    Write-Host "Comparison started : $($startTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Blue
    Write-Host "Comparison finished: $($endTime.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Blue
    Write-Host ("Total processing time: {0:N2} seconds" -f $elapsedTime.TotalSeconds) -ForegroundColor Blue
    Write-Host "--------------------------" -ForegroundColor Blue
    Write-Host "Lines added               : $($summary.AddedLines)" -ForegroundColor Blue
    Write-Host "Lines removed (candidates): $($summary.RemovedCandidates)" -ForegroundColor Blue
    Write-Host "Generated removal commands: $($summary.GeneratedRemovals)" -ForegroundColor Blue
    Write-Host "  Priority 1 (ACLs)        : $($summary.Priority1_ACL)" -ForegroundColor Blue
    Write-Host "  Priority 2 (Group Members): $($summary.Priority2_GroupMember)" -ForegroundColor Blue
    Write-Host "  Priority 3 (Groups)      : $($summary.Priority3_Group)" -ForegroundColor Blue
    Write-Host "  Priority 4 (Objects)     : $($summary.Priority4_Object)" -ForegroundColor Blue
    Write-Host "  Priority 5 (Others)      : $($summary.Priority5_Other)" -ForegroundColor Blue
    Write-Host "Skipped (Obj Children)    : $($summary.SkippedObjectChildren)" -ForegroundColor Yellow # Yellow for skipped count
    Write-Host "Warnings (Parse Errors)   : $($summary.Priority99_Warning)" -ForegroundColor Magenta # Magenta for warnings count
    Write-Host "--------------------------" -ForegroundColor Blue
    if ($GenerateRemovalCommands.IsPresent) {
        Write-Host "Removal commands included in '$DiffOutputFile' for priorities: $($IncludePriority -join ', ')" -ForegroundColor Blue
    } else {
        Write-Host "Removal commands were printed to the console (not included in '$DiffOutputFile')." -ForegroundColor Blue
    }

    Write-Host "`n--- Important Considerations ---" -ForegroundColor Blue
    # ... (Considerations remain the same) ...
    Write-Host "1. Review Output: Carefully review '$DiffOutputFile' AND console output (colors indicate type) before applying." -ForegroundColor Blue
    Write-Host "2. Command Order: Removal commands are prioritized. Added lines retain order. Check console (Red) if removals aren't in the file." -ForegroundColor Blue
    Write-Host "3. Modified Lines: Appear as a 'no <old>' (potentially Red on console) and '<new>' (in file)." -ForegroundColor Blue
    Write-Host "4. 'no' Reversal: Check the reversal logic." -ForegroundColor Blue
    Write-Host "5. Context/Skipping: Context/skipping handled for objects/groups. Verify console output (Yellow) for skipped lines." -ForegroundColor Blue
    Write-Host "6. Indentation: 'no' commands (file or Red console) retain original indent. Added commands retain original format." -ForegroundColor Blue
    Write-Host "7. Encoding: UTF-8 used for output." -ForegroundColor Blue
    Write-Host "8. Trimming: Comparison uses trimmed lines, output uses original/trimmed appropriately." -ForegroundColor Blue


} catch {
    $swWrite.Stop()
    Write-Error "Error writing output file ${DiffOutputFile}: $($_.Exception.Message)" # Errors are typically Red by default
    exit 1
}

Write-Host "Script finished." -ForegroundColor Green # Green for overall success

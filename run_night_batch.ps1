# WikiMapper Night Batch Runner (PowerShell)
# Runs between 12:30 AM and 4:30 AM
# Supports both single-machine and multi-machine modes

param(
    [int]$MachineId = -1,
    [int]$TotalMachines = -1,
    [switch]$MultiMachine
)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

$VenvDir = "venv"
$RequirementsFile = "requirements.txt"
$PythonScript = "main.py"
$LogFile = "batch_run.log"

# If both machine ID and total machines are set, use multi-machine script
if ($MachineId -ge 0 -and $TotalMachines -gt 0) {
    $PythonScript = "main_multi_machine.py"
    $LogFile = "batch_run_machine_$MachineId.log"
    $MultiMachine = $true
} elseif ($MultiMachine) {
    Write-Host "ERROR: Multi-machine mode requires --MachineId and --TotalMachines parameters"
    Write-Host "Usage: .\run_night_batch.ps1 -MachineId 0 -TotalMachines 3"
    exit 1
}

# Function to log messages
function Log-Message {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    Write-Host $logEntry
    Add-Content -Path $LogFile -Value $logEntry
}

Log-Message "Starting WikiMapper batch run..."

# Log multi-machine configuration if applicable
if ($MultiMachine) {
    Log-Message "Multi-machine mode enabled:"
    Log-Message "  Machine ID: $MachineId"
    Log-Message "  Total machines: $TotalMachines"
    Log-Message "  Script: $PythonScript"
}

# Create virtual environment if it doesn't exist
if (-not (Test-Path $VenvDir)) {
    Log-Message "Virtual environment not found. Creating..."
    python -m venv $VenvDir
    
    if ($LASTEXITCODE -ne 0) {
        Log-Message "ERROR: Failed to create virtual environment"
        exit 1
    }
    
    Log-Message "Virtual environment created successfully"
}

# Activate virtual environment
Log-Message "Activating virtual environment..."
& "$VenvDir\Scripts\Activate.ps1"

if ($LASTEXITCODE -ne 0) {
    Log-Message "ERROR: Failed to activate virtual environment"
    exit 1
}

# Install/update dependencies
if (-not (Test-Path $RequirementsFile)) {
    Log-Message "Creating requirements.txt..."
    "requests" | Out-File -FilePath $RequirementsFile -Encoding utf8
}

Log-Message "Installing dependencies..."
pip install -q -r $RequirementsFile

if ($LASTEXITCODE -ne 0) {
    Log-Message "ERROR: Failed to install dependencies"
    exit 1
}

# Run the main script
Log-Message "Starting $PythonScript..."
Log-Message "Running continuously (24/7 mode)..."

# Build command arguments for multi-machine mode if applicable
$pythonArgs = @()
if ($MultiMachine) {
    $pythonArgs += "--machine-id", $MachineId
    $pythonArgs += "--total-machines", $TotalMachines
    Log-Message "Running command: python $PythonScript --machine-id $MachineId --total-machines $TotalMachines"
} else {
    Log-Message "Running command: python $PythonScript"
}

# Run the Python script directly and capture output
if ($pythonArgs.Count -gt 0) {
    & python $PythonScript $pythonArgs 2>&1 | Tee-Object -FilePath $LogFile -Append
} else {
    & python $PythonScript 2>&1 | Tee-Object -FilePath $LogFile -Append
}

$exitCode = $LASTEXITCODE

Log-Message "Main script finished with exit code: $exitCode"

# Deactivate virtual environment
deactivate

Log-Message "Batch run complete"

exit $exitCode

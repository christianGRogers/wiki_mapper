# WikiMapper Night Batch Runner (PowerShell)
# Runs between 12:30 AM and 4:30 AM

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $ScriptDir

$VenvDir = "venv"
$RequirementsFile = "requirements.txt"
$PythonScript = "main.py"
$LogFile = "batch_run.log"

# Function to log messages
function Log-Message {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    Write-Host $logEntry
    Add-Content -Path $LogFile -Value $logEntry
}

# Function to check if current time is within allowed window
function Is-TimeAllowed {
    $currentTime = Get-Date
    $startTime = Get-Date -Hour 0 -Minute 30 -Second 0
    $endTime = Get-Date -Hour 4 -Minute 30 -Second 0
    
    return ($currentTime -ge $startTime -and $currentTime -le $endTime)
}

# Check if we're in the allowed time window
if (-not (Is-TimeAllowed)) {
    Log-Message "Not in allowed time window (12:30 AM - 4:30 AM). Exiting."
    exit 0
}

Log-Message "Starting WikiMapper batch run..."

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

# Run the main script with time limit
Log-Message "Starting main.py..."
Log-Message "Will run until 4:30 AM..."

# Start the Python process as a job to capture output while monitoring
$job = Start-Job -ScriptBlock {
    param($scriptPath, $venvPath)
    
    # Activate venv in job
    & "$venvPath\Scripts\Activate.ps1"
    
    # Run Python and capture output
    & python $scriptPath 2>&1
} -ArgumentList $PythonScript, $VenvDir

Log-Message "Python process started with Job ID: $($job.Id)"

# Monitor the job and display output in real-time
while ($job.State -eq 'Running') {
    # Check if time window has ended
    if (-not (Is-TimeAllowed)) {
        Log-Message "Time window ended (4:30 AM reached). Stopping process..."
        Stop-Job -Job $job
        Remove-Job -Job $job -Force
        Log-Message "Process stopped successfully"
        break
    }
    
    # Get any new output from the job and display it
    $output = Receive-Job -Job $job
    if ($output) {
        foreach ($line in $output) {
            Write-Host $line
            Add-Content -Path $LogFile -Value $line
        }
    }
    
    Start-Sleep -Seconds 1  # Check every second for output
}

# Get any remaining output
$output = Receive-Job -Job $job
if ($output) {
    foreach ($line in $output) {
        Write-Host $line
        Add-Content -Path $LogFile -Value $line
    }
}

# Get exit code
$exitCode = 0
if ($job.State -eq 'Failed') {
    $exitCode = 1
}

Remove-Job -Job $job -Force

Log-Message "Main script finished with exit code: $exitCode"

# Deactivate virtual environment
deactivate

Log-Message "Batch run complete"

exit $exitCode

#!/bin/bash

# WikiMapper Night Batch Runner
# Runs between 12:30 AM and 4:30 AM

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VENV_DIR="venv"
REQUIREMENTS_FILE="requirements.txt"
PYTHON_SCRIPT="main.py"
LOG_FILE="batch_run.log"

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

# Function to check if current time is within allowed window
is_time_allowed() {
    current_hour=$(date +%H)
    current_minute=$(date +%M)
    current_time=$((10#$current_hour * 60 + 10#$current_minute))
    
    # 12:30 AM = 30 minutes, 4:30 AM = 270 minutes
    start_time=30
    end_time=2000
    
    if [ $current_time -ge $start_time ] && [ $current_time -le $end_time ]; then
        return 0  # true
    else
        return 1  # false
    fi
}

# Function to calculate minutes until start time
minutes_until_start() {
    current_hour=$(date +%H)
    current_minute=$(date +%M)
    current_time=$((10#$current_hour * 60 + 10#$current_minute))
    
    start_time=30  # 12:30 AM
    
    if [ $current_time -lt $start_time ]; then
        # Same day - just wait until 12:30 AM
        echo $((start_time - current_time))
    else
        # After 4:30 AM - wait until 12:30 AM next day
        minutes_until_midnight=$((1440 - current_time))
        echo $((minutes_until_midnight + start_time))
    fi
}

# Wait until we're in the allowed time window
if ! is_time_allowed; then
    wait_minutes=$(minutes_until_start)
    wait_hours=$((wait_minutes / 60))
    wait_mins=$((wait_minutes % 60))
    
    log_message "Not in allowed time window yet."
    log_message "Waiting ${wait_hours}h ${wait_mins}m until 12:30 AM to start..."
    log_message "You can safely leave this running in screen/tmux."
    
    # Wait in 5-minute intervals, checking if we've reached start time
    while ! is_time_allowed; do
        sleep 300  # Sleep for 5 minutes
        
        # Log progress every hour
        current_minute=$(date +%M)
        if [ "$current_minute" = "00" ] || [ "$current_minute" = "30" ]; then
            remaining=$(minutes_until_start)
            remaining_hours=$((remaining / 60))
            remaining_mins=$((remaining % 60))
            log_message "Still waiting... ${remaining_hours}h ${remaining_mins}m until 12:30 AM"
        fi
    done
fi

log_message "Time window reached! Starting WikiMapper batch run..."

# Create virtual environment if it doesn't exist or is invalid
if [ ! -f "$VENV_DIR/bin/activate" ]; then
    log_message "Virtual environment not found or invalid. Creating..."
    
    # Remove any existing incomplete venv directory
    if [ -d "$VENV_DIR" ]; then
        log_message "Removing incomplete virtual environment..."
        rm -rf "$VENV_DIR"
    fi
    
    # Check if python3 is available
    if ! command -v python3 &> /dev/null; then
        log_message "ERROR: python3 not found. Please install Python 3."
        exit 1
    fi
    
    log_message "Using Python: $(which python3)"
    log_message "Python version: $(python3 --version)"
    
    # Try to create venv
    python3 -m venv "$VENV_DIR" 2>&1 | tee -a "$LOG_FILE"
    
    if [ $? -ne 0 ]; then
        log_message "ERROR: Failed to create virtual environment"
        
        # Get Python version to suggest correct package
        PYTHON_VERSION=$(python3 --version 2>&1 | grep -oP 'Python \K[0-9]+\.[0-9]+' | head -1)
        
        if [ ! -z "$PYTHON_VERSION" ]; then
            log_message "Try: sudo apt-get install python${PYTHON_VERSION}-venv"
        else
            log_message "Try: sudo apt-get install python3-venv"
        fi
        
        log_message "Or try: sudo apt install python3-virtualenv && python3 -m virtualenv venv"
        exit 1
    fi
    
    # Verify creation was successful
    if [ ! -f "$VENV_DIR/bin/activate" ]; then
        log_message "ERROR: Virtual environment created but activate script not found"
        log_message "The venv module may not be properly installed"
        exit 1
    fi
    
    log_message "Virtual environment created successfully"
fi

# Activate virtual environment
log_message "Activating virtual environment..."
source "$VENV_DIR/bin/activate"

if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to activate virtual environment"
    exit 1
fi

# Install/update dependencies
if [ ! -f "$REQUIREMENTS_FILE" ]; then
    log_message "Creating requirements.txt..."
    echo "requests" > "$REQUIREMENTS_FILE"
fi

log_message "Installing dependencies..."
pip install -q -r "$REQUIREMENTS_FILE"

if [ $? -ne 0 ]; then
    log_message "ERROR: Failed to install dependencies"
    exit 1
fi

# Run the main script with time limit
log_message "Starting main.py..."
log_message "Will run until 4:30 AM..."

# Run the script and tee output to both console and log file
# This allows real-time viewing while also logging
python "$PYTHON_SCRIPT" 2>&1 | while IFS= read -r line; do
    echo "$line" | tee -a "$LOG_FILE"
    
    # Check if time window has ended (check periodically, not on every line)
    if [ $((RANDOM % 100)) -eq 0 ]; then
        if ! is_time_allowed; then
            log_message "Time window ended (4:30 AM reached). Stopping process..."
            # Kill the python process
            pkill -f "$PYTHON_SCRIPT"
            break
        fi
    fi
done &

PYTHON_PID=$!

log_message "Python process started with PID: $PYTHON_PID"

# Monitor the process and stop it at 4:30 AM
while kill -0 $PYTHON_PID 2>/dev/null; do
    if ! is_time_allowed; then
        log_message "Time window ended (4:30 AM reached). Stopping process..."
        # Kill the Python script specifically
        pkill -SIGINT -f "$PYTHON_SCRIPT"
        sleep 5
        
        # Force kill if still running
        if pgrep -f "$PYTHON_SCRIPT" > /dev/null; then
            log_message "Process didn't stop gracefully. Force killing..."
            pkill -9 -f "$PYTHON_SCRIPT"
        fi
        
        log_message "Process stopped successfully"
        break
    fi
    
    sleep 60  # Check every minute
done

# Wait for the process to finish
wait $PYTHON_PID 2>/dev/null
EXIT_CODE=$?

log_message "Main script finished with exit code: $EXIT_CODE"

# Deactivate virtual environment
deactivate

log_message "Batch run complete"
exit $EXIT_CODE

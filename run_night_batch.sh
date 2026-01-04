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
    end_time=270
    
    if [ $current_time -ge $start_time ] && [ $current_time -le $end_time ]; then
        return 0  # true
    else
        return 1  # false
    fi
}

# Check if we're in the allowed time window
if ! is_time_allowed; then
    log_message "Not in allowed time window (12:30 AM - 4:30 AM). Exiting."
    exit 0
fi

log_message "Starting WikiMapper batch run..."

# Create virtual environment if it doesn't exist
if [ ! -d "$VENV_DIR" ]; then
    log_message "Virtual environment not found. Creating..."
    python3 -m venv "$VENV_DIR"
    
    if [ $? -ne 0 ]; then
        log_message "ERROR: Failed to create virtual environment"
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

# Run the script in the background and capture its PID
python "$PYTHON_SCRIPT" >> "$LOG_FILE" 2>&1 &
PYTHON_PID=$!

log_message "Python process started with PID: $PYTHON_PID"

# Monitor the process and stop it at 4:30 AM
while kill -0 $PYTHON_PID 2>/dev/null; do
    if ! is_time_allowed; then
        log_message "Time window ended (4:30 AM reached). Stopping process..."
        kill -SIGINT $PYTHON_PID
        sleep 5
        
        # Force kill if still running
        if kill -0 $PYTHON_PID 2>/dev/null; then
            log_message "Process didn't stop gracefully. Force killing..."
            kill -9 $PYTHON_PID
        fi
        
        log_message "Process stopped successfully"
        break
    fi
    
    sleep 60  # Check every minute
done

# Wait for the process to finish
wait $PYTHON_PID
EXIT_CODE=$?

log_message "Main script finished with exit code: $EXIT_CODE"

# Deactivate virtual environment
deactivate

log_message "Batch run complete"
exit $EXIT_CODE

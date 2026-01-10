#!/bin/bash

# WikiMapper Night Batch Runner
# Runs between 12:30 AM and 4:30 AM
# Supports both single-machine and multi-machine modes

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

VENV_DIR="venv"
REQUIREMENTS_FILE="requirements.txt"
PYTHON_SCRIPT="main.py"
LOG_FILE="batch_run.log"

# Multi-machine support (optional)
# Set these environment variables or pass as arguments:
# MACHINE_ID - ID of this machine (0-indexed)
# TOTAL_MACHINES - Total number of machines in cluster
MACHINE_ID="${MACHINE_ID:-}"
TOTAL_MACHINES="${TOTAL_MACHINES:-}"

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --machine-id)
            MACHINE_ID="$2"
            shift 2
            ;;
        --total-machines)
            TOTAL_MACHINES="$2"
            shift 2
            ;;
        --multi-machine)
            PYTHON_SCRIPT="main_multi_machine.py"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            echo "Usage: $0 [--machine-id N] [--total-machines N] [--multi-machine]"
            exit 1
            ;;
    esac
done

# If both machine ID and total machines are set, use multi-machine script
if [ ! -z "$MACHINE_ID" ] && [ ! -z "$TOTAL_MACHINES" ]; then
    PYTHON_SCRIPT="main_multi_machine.py"
    LOG_FILE="batch_run_machine_${MACHINE_ID}.log"
fi

# Function to log messages
log_message() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log_message "Starting WikiMapper batch run..."

# Log multi-machine configuration if applicable
if [ ! -z "$MACHINE_ID" ] && [ ! -z "$TOTAL_MACHINES" ]; then
    log_message "Multi-machine mode enabled:"
    log_message "  Machine ID: $MACHINE_ID"
    log_message "  Total machines: $TOTAL_MACHINES"
    log_message "  Script: $PYTHON_SCRIPT"
fi

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

# Run the main script
log_message "Starting $PYTHON_SCRIPT..."
log_message "Running continuously (24/7 mode)..."

# Build command with multi-machine arguments if applicable
CMD="python $PYTHON_SCRIPT"
if [ ! -z "$MACHINE_ID" ] && [ ! -z "$TOTAL_MACHINES" ]; then
    CMD="$CMD --machine-id $MACHINE_ID --total-machines $TOTAL_MACHINES"
fi

log_message "Running command: $CMD"

# Run the script and tee output to both console and log file
$CMD 2>&1 | tee -a "$LOG_FILE"

EXIT_CODE=$?

log_message "Main script finished with exit code: $EXIT_CODE"

# Deactivate virtual environment
deactivate

log_message "Batch run complete"
exit $EXIT_CODE

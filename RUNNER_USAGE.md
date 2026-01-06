# Night Batch Runner Usage Guide

The runner scripts have been updated to support both single-machine and multi-machine modes.

## Single-Machine Mode (Original)

### PowerShell (Windows)
```powershell
.\run_night_batch.ps1
```

### Bash (Linux/Mac)
```bash
./run_night_batch.sh
```

## Multi-Machine Mode

### PowerShell (Windows)

**Machine 1:**
```powershell
.\run_night_batch.ps1 -MachineId 0 -TotalMachines 3
```

**Machine 2:**
```powershell
.\run_night_batch.ps1 -MachineId 1 -TotalMachines 3
```

**Machine 3:**
```powershell
.\run_night_batch.ps1 -MachineId 2 -TotalMachines 3
```

### Bash (Linux/Mac)

**Machine 1:**
```bash
./run_night_batch.sh --machine-id 0 --total-machines 3
```

**Machine 2:**
```bash
./run_night_batch.sh --machine-id 1 --total-machines 3
```

**Machine 3:**
```bash
./run_night_batch.sh --machine-id 2 --total-machines 3
```

Or using environment variables:
```bash
export MACHINE_ID=0
export TOTAL_MACHINES=3
./run_night_batch.sh
```

## Features

### Time Window
Both scripts run only between **12:30 AM and 4:30 AM**:
- **Bash**: Waits until 12:30 AM if started early
- **PowerShell**: Exits if not in time window (schedule with Task Scheduler)

### Automatic Configuration
When using multi-machine mode:
- Automatically uses `main_multi_machine.py`
- Creates separate log files per machine: `batch_run_machine_0.log`, etc.
- Each machine processes its own partition of articles

### Virtual Environment
Both scripts automatically:
- Create a Python virtual environment if needed
- Install dependencies from `requirements.txt`
- Activate/deactivate the environment

## Scheduling

### Windows Task Scheduler (PowerShell)

**For single machine:**
```
Program: powershell.exe
Arguments: -ExecutionPolicy Bypass -File "C:\path\to\run_night_batch.ps1"
Start time: 12:30 AM
```

**For multi-machine (Machine 0):**
```
Program: powershell.exe
Arguments: -ExecutionPolicy Bypass -File "C:\path\to\run_night_batch.ps1" -MachineId 0 -TotalMachines 3
Start time: 12:30 AM
```

### Linux Cron (Bash)

**For single machine:**
```cron
30 0 * * * cd /path/to/wiki_mapper && ./run_night_batch.sh >> cron.log 2>&1
```

**For multi-machine (Machine 0):**
```cron
30 0 * * * cd /path/to/wiki_mapper && ./run_night_batch.sh --machine-id 0 --total-machines 3 >> cron.log 2>&1
```

### Using screen/tmux (Linux)

Start a persistent session that waits for the time window:

```bash
# Start a screen session
screen -S wikimapper

# Inside screen, run the script
./run_night_batch.sh --machine-id 0 --total-machines 3

# Detach with Ctrl+A, D
# Reattach later with: screen -r wikimapper
```

## Log Files

### Single-Machine Mode
- Log file: `batch_run.log`

### Multi-Machine Mode
- Machine 0: `batch_run_machine_0.log`
- Machine 1: `batch_run_machine_1.log`
- Machine 2: `batch_run_machine_2.log`

## Stopping Gracefully

Both scripts will automatically stop at **4:30 AM**.

To stop manually:
- **PowerShell**: Press `Ctrl+C`
- **Bash**: Press `Ctrl+C` or send SIGINT

The scripts will gracefully stop the Python process and save current progress.

## Combining with Existing Database

If you already have a partially complete database from running the original `main.py`:

1. Keep it running on one machine, OR
2. Stop it and include it in the merge later:
   ```bash
   python merge_databases.py wiki_mapping.db wiki_mapping_machine_0.db wiki_mapping_machine_1.db --output wiki_mapping_final.db
   ```

## Troubleshooting

### "Multi-machine mode requires parameters"
Make sure you provide both `--machine-id` and `--total-machines`.

### "Virtual environment creation failed"
- **Windows**: Ensure Python is in PATH
- **Linux**: Install `python3-venv` package

### Process doesn't stop at 4:30 AM
Check if the time zone is correct. The scripts use system local time.

### Database locked errors
Make sure only one script instance per database file is running.

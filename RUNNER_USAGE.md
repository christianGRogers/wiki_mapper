# Night Batch Runner Usage Guide

The runner scripts have been updated to support both single-machine and multi-machine modes.

## Single-Machine Mode (Original)

Note: The Windows PowerShell runner has been removed. To run on Windows, use WSL, a Linux VM, or run the Python scripts directly. Example:

```bash
# In WSL or Linux environment
./run_night_batch.sh --machine-id 0 --total-machines 3

# Or run the Python script directly from any OS
python main_multi_machine.py --machine-id 0 --total-machines 3
```

### Bash (Linux/Mac)
```bash
./run_night_batch.sh
```

## Multi-Machine Mode

See the Bash examples above or run the Python script directly as shown earlier.

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

### Continuous Run
Scripts run continuously by default (24/7). If you want scheduled runs, use system tools like `cron` or systemd timers. The runner can also be run inside `screen`/`tmux`.

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

*(Windows Task Scheduler instructions removed — use WSL, cron, or systemd on Windows hosts.)*

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

The runner will continue until the Python process exits (completion or error) or you stop it manually.

To stop manually: press `Ctrl+C` in the running terminal (or send SIGINT). The Python process should exit gracefully and progress will be saved.

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
- Ensure Python is in PATH and `python3 -m venv`/`python -m venv` is available
- On Linux, install the `python3-venv` package if needed

### Process doesn't stop at 4:30 AM
Check if the time zone is correct. The scripts use system local time.

### Database locked errors
Make sure only one script instance per database file is running.

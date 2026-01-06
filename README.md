# wiki_mapper
My implementation of a Wikipedia mapping tool that creates a complete graph of Wikipedia article links.

## Features

- **Single-machine mode**: Run on one machine to process all Wikipedia articles
- **Multi-machine mode**: Distribute processing across multiple machines for faster completion
- **Automatic time windowing**: Runs between 12:30 AM - 4:30 AM for off-peak processing
- **Resume capability**: Stop and restart anytime without losing progress
- **Database merging**: Combine results from multiple machines into a single database

## Quick Start

### Single Machine

**Linux/Mac:**
```bash
# Make it executable (run once)
chmod +x run_night_batch.sh

# Run in screen for persistence
screen -S wiki_batch
./run_night_batch.sh
# Press Ctrl+A, then D to detach

# Check on it later
screen -r wiki_batch

# Or check the log
tail -f batch_run.log
```

**Windows (PowerShell):**
```powershell
# Run directly
.\run_night_batch.ps1

# Or schedule with Task Scheduler for automated runs
```

### Multi-Machine Mode

Run the same Wikipedia mapping job across multiple machines simultaneously. Each machine processes a unique subset of articles using hash-based partitioning.

**Linux/Mac (3 machines example):**

```bash
# Machine 1
screen -S wiki_batch
./run_night_batch.sh --machine-id 0 --total-machines 3
# Ctrl+A, D to detach

# Machine 2
screen -S wiki_batch
./run_night_batch.sh --machine-id 1 --total-machines 3
# Ctrl+A, D to detach

# Machine 3
screen -S wiki_batch
./run_night_batch.sh --machine-id 2 --total-machines 3
# Ctrl+A, D to detach
```

**Windows (PowerShell):**
```powershell
# Machine 1
.\run_night_batch.ps1 -MachineId 0 -TotalMachines 3

# Machine 2
.\run_night_batch.ps1 -MachineId 1 -TotalMachines 3

# Machine 3
.\run_night_batch.ps1 -MachineId 2 -TotalMachines 3
```

### Merging Results

After your machines finish processing (or at any point), merge the databases:

```bash
python merge_databases.py wiki_mapping_machine_0.db wiki_mapping_machine_1.db wiki_mapping_machine_2.db --output wiki_mapping_final.db
```

You can also merge your existing single-machine database:

```bash
python merge_databases.py wiki_mapping.db wiki_mapping_machine_0.db wiki_mapping_machine_1.db --output wiki_mapping_final.db
```

## Files Overview

- **`main.py`** - Original single-machine implementation
- **`main_multi_machine.py`** - Multi-machine variant with hash-based partitioning
- **`merge_databases.py`** - Database merger utility
- **`run_night_batch.sh`** - Bash runner script (Linux/Mac) with time windowing
- **`run_night_batch.ps1`** - PowerShell runner script (Windows) with time windowing
- **`MULTI_MACHINE_README.md`** - Detailed multi-machine documentation
- **`RUNNER_USAGE.md`** - Complete runner script usage guide

## Running Manually (Without Time Window)

If you want to run continuously without the 12:30 AM - 4:30 AM restriction:

**Single machine:**
```bash
python main.py
```

**Multi-machine:**
```bash
python main_multi_machine.py --machine-id 0 --total-machines 3
```

## Database Schema

All databases use the same schema (compatible for merging):

- **`articles`** - All Wikipedia article titles with processing status
- **`links`** - Relationships between articles (from → to)
- **`progress`** - Processing metadata

## Monitoring Progress

Check statistics from any database:

```python
import sqlite3
conn = sqlite3.connect('wiki_mapping_machine_0.db')
cursor = conn.cursor()

# Total articles
cursor.execute('SELECT COUNT(*) FROM articles')
print(f"Total articles: {cursor.fetchone()[0]:,}")

# Processed articles
cursor.execute('SELECT COUNT(*) FROM articles WHERE processed = TRUE')
print(f"Processed: {cursor.fetchone()[0]:,}")

# Total links
cursor.execute('SELECT COUNT(*) FROM links')
print(f"Total links: {cursor.fetchone()[0]:,}")

conn.close()
```

Or check the log files:
```bash
# Single machine
tail -f batch_run.log

# Multi-machine
tail -f batch_run_machine_0.log
tail -f batch_run_machine_1.log
tail -f batch_run_machine_2.log
```

## Scheduling

### Linux Cron

Add to crontab (`crontab -e`):

```cron
# Single machine - runs at 12:30 AM daily
30 0 * * * cd /path/to/wiki_mapper && ./run_night_batch.sh >> cron.log 2>&1

# Multi-machine example (Machine 0)
30 0 * * * cd /path/to/wiki_mapper && ./run_night_batch.sh --machine-id 0 --total-machines 3 >> cron.log 2>&1
```

### Windows Task Scheduler

Create a task that runs at 12:30 AM:

**Single machine:**
- Program: `powershell.exe`
- Arguments: `-ExecutionPolicy Bypass -File "C:\path\to\wiki_mapper\run_night_batch.ps1"`

**Multi-machine (Machine 0):**
- Program: `powershell.exe`
- Arguments: `-ExecutionPolicy Bypass -File "C:\path\to\wiki_mapper\run_night_batch.ps1" -MachineId 0 -TotalMachines 3`

## Performance Tips

1. **Reduce API delay** (if Wikipedia's API can handle it):
   ```bash
   python main_multi_machine.py --machine-id 0 --total-machines 3 --delay 0.5
   ```

2. **Increase batch size** for fewer database commits:
   ```bash
   python main_multi_machine.py --machine-id 0 --total-machines 3 --batch-size 500
   ```

3. **Use more machines** for linear scaling:
   - 1 machine ≈ X articles/hour
   - 4 machines ≈ 4X articles/hour
   - 10 machines ≈ 10X articles/hour

## Requirements

```
requests
```

Install with:
```bash
pip install -r requirements.txt
```

The runner scripts automatically create a virtual environment and install dependencies.

## Troubleshooting

**"Database is locked" error:**
- Only one process should access each database file
- Make sure you're not running multiple instances with the same machine ID

**"Virtual environment creation failed":**
- Linux: `sudo apt-get install python3-venv`
- Windows: Ensure Python is in PATH

**Script doesn't stop at 4:30 AM:**
- Check system timezone settings
- Scripts use local system time

**Machines processing same articles:**
- Verify you're using consistent `--machine-id` and `--total-machines` values
- Don't change these values mid-run

## Documentation

- **[MULTI_MACHINE_README.md](MULTI_MACHINE_README.md)** - Detailed multi-machine setup and technical details
- **[RUNNER_USAGE.md](RUNNER_USAGE.md)** - Complete runner script usage and scheduling guide

## License

See LICENSE file.
# Multi-Machine Wikipedia Mapper

This variant allows you to run the Wikipedia mapper across multiple machines simultaneously, then merge the results.

## How It Works

The multi-machine version uses **hash-based partitioning** to ensure each machine processes a unique subset of Wikipedia articles. Each article title is hashed, and the hash determines which machine should process it. This means:

- No coordination between machines needed during processing
- No duplicate work
- Each machine creates its own database
- Databases can be merged later

## Running on Multiple Machines

### Step 1: Start Processing on Each Machine

On **Machine 1** (assuming 4 total machines):
```bash
python main_multi_machine.py --machine-id 0 --total-machines 4
```

On **Machine 2**:
```bash
python main_multi_machine.py --machine-id 1 --total-machines 4
```

On **Machine 3**:
```bash
python main_multi_machine.py --machine-id 2 --total-machines 4
```

On **Machine 4**:
```bash
python main_multi_machine.py --machine-id 3 --total-machines 4
```

### Important Parameters

- `--machine-id`: Zero-indexed ID for this machine (0, 1, 2, ...)
- `--total-machines`: Total number of machines you're using
- `--db-path`: (Optional) Custom database path
- `--batch-size`: (Optional) Articles per batch (default: 100)
- `--delay`: (Optional) Delay between API requests in seconds (default: 1.0)

### Database Files

Each machine will create its own database:
- Machine 0: `wiki_mapping_machine_0.db`
- Machine 1: `wiki_mapping_machine_1.db`
- Machine 2: `wiki_mapping_machine_2.db`
- Machine 3: `wiki_mapping_machine_3.db`

## Stopping and Resuming

You can stop any machine at any time (Ctrl+C) and resume later with the same command. The database tracks which articles have been processed.

## Merging Databases

After all machines finish (or at any point), merge the databases:

```bash
python merge_databases.py wiki_mapping_machine_0.db wiki_mapping_machine_1.db wiki_mapping_machine_2.db wiki_mapping_machine_3.db --output wiki_mapping_final.db
```

This will:
- Combine all articles from all machines
- Deduplicate articles (same title only appears once)
- Preserve all links
- Mark articles as processed if they were processed on any machine
- Output final statistics

## Merging with Your Existing Database

If you already have a partially complete database (`wiki_mapping.db`) from the single-machine version, you can include it in the merge:

```bash
python merge_databases.py wiki_mapping.db wiki_mapping_machine_0.db wiki_mapping_machine_1.db --output wiki_mapping_final.db
```

The merger is smart about handling:
- Duplicate articles (keeps unique titles)
- Processed status (if processed anywhere, marks as processed)
- Links (deduplicates using UNIQUE constraint)

## Example Workflows

### Scenario 1: Starting Fresh with 3 Machines

```bash
# Machine 1
python main_multi_machine.py --machine-id 0 --total-machines 3

# Machine 2
python main_multi_machine.py --machine-id 1 --total-machines 3

# Machine 3
python main_multi_machine.py --machine-id 2 --total-machines 3

# After completion, merge on any machine:
python merge_databases.py wiki_mapping_machine_*.db --output wiki_mapping_final.db
```

### Scenario 2: You Have a Partial DB, Add 2 More Machines

Keep your existing machine running with `main.py`, and start 2 new machines:

```bash
# New Machine 1 (treating your existing machine as machine 0)
python main_multi_machine.py --machine-id 1 --total-machines 3

# New Machine 2
python main_multi_machine.py --machine-id 2 --total-machines 3

# Later, merge all three:
python merge_databases.py wiki_mapping.db wiki_mapping_machine_1.db wiki_mapping_machine_2.db --output wiki_mapping_final.db
```

**Note:** This scenario means machine 0 (your existing one) will process some articles that machines 1 and 2 might also try to process. To avoid this, you could:
1. Stop your existing process
2. Copy `wiki_mapping.db` to `wiki_mapping_machine_0.db`
3. Start all 3 machines using `main_multi_machine.py`

### Scenario 3: Scaling Mid-Run

If you've been running 2 machines and want to add a 3rd:

**Don't do this!** The hash partitioning is based on `total_machines`, so changing this value mid-run will cause machines to process different subsets than originally planned.

Instead:
1. Let the current machines finish
2. Merge their databases
3. Start a new run with the new machine count if needed

## Performance Tips

1. **Adjust delay**: If Wikipedia's API can handle it, reduce `--delay` to 0.5 or even 0.1
   ```bash
   python main_multi_machine.py --machine-id 0 --total-machines 4 --delay 0.5
   ```

2. **Batch size**: Increase `--batch-size` for fewer database transactions
   ```bash
   python main_multi_machine.py --machine-id 0 --total-machines 4 --batch-size 500
   ```

3. **Monitor progress**: Check statistics periodically
   ```python
   import sqlite3
   conn = sqlite3.connect('wiki_mapping_machine_0.db')
   cursor = conn.cursor()
   cursor.execute('SELECT COUNT(*) FROM articles WHERE processed = TRUE')
   print(f"Processed: {cursor.fetchone()[0]}")
   conn.close()
   ```

## Troubleshooting

### Database Locked Errors
If you get "database is locked" errors, make sure only one instance of the script is accessing each database file.

### Machines Processing Same Articles
This shouldn't happen if you use consistent `--machine-id` and `--total-machines` values. Double-check your command-line arguments.

### Merge Taking Too Long
The merge processes databases sequentially. For very large databases, this can take time. It commits every 1000 articles to show progress.

## Technical Details

- **Partitioning**: Uses MD5 hash of article title, then modulo by `total_machines`
- **Database Schema**: Identical to single-machine version (no changes needed)
- **Collision Handling**: `INSERT OR IGNORE` and `UNIQUE` constraints prevent duplicates
- **State**: Each machine maintains its own complete state in its database

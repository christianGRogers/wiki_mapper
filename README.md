# wiki_mapper
My implementation of a Wikipedia mapping tool

Usage:

# Make it executable (run this once on your Linux server)
chmod +x run_night_batch.sh

# Run it in screen
screen -S wiki_batch
./run_night_batch.sh
# Press Ctrl+A, then D to detach

# To check on it later
screen -r wiki_batch

# Or check the log
tail -f batch_run.log
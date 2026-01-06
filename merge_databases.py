import sqlite3
import argparse
import logging
import os

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class DatabaseMerger:
    def __init__(self, output_db='wiki_mapping_merged.db'):
        """Initialize the database merger."""
        self.output_db = output_db
        self.init_output_database()
    
    def init_output_database(self):
        """Initialize the output database with required tables."""
        conn = sqlite3.connect(self.output_db)
        cursor = conn.cursor()
        
        # Articles table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS articles (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                title TEXT UNIQUE NOT NULL,
                processed BOOLEAN DEFAULT FALSE,
                last_updated TIMESTAMP DEFAULT CURRENT_TIMESTAMP
            )
        ''')
        
        # Links table for connections between articles
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS links (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                from_article_id INTEGER,
                to_article_title TEXT,
                FOREIGN KEY (from_article_id) REFERENCES articles (id),
                UNIQUE(from_article_id, to_article_title)
            )
        ''')
        
        # Progress tracking table
        cursor.execute('''
            CREATE TABLE IF NOT EXISTS progress (
                key TEXT PRIMARY KEY,
                value TEXT
            )
        ''')
        
        conn.commit()
        conn.close()
        logger.info(f"Initialized output database: {self.output_db}")
    
    def merge_database(self, input_db):
        """Merge a single database into the output database."""
        if not os.path.exists(input_db):
            logger.error(f"Database file not found: {input_db}")
            return False
        
        logger.info(f"Merging database: {input_db}")
        
        # Connect to both databases
        input_conn = sqlite3.connect(input_db)
        output_conn = sqlite3.connect(self.output_db)
        
        input_cursor = input_conn.cursor()
        output_cursor = output_conn.cursor()
        
        try:
            # Get articles from input database
            input_cursor.execute('SELECT title, processed FROM articles')
            articles = input_cursor.fetchall()
            
            article_count = 0
            link_count = 0
            
            for title, processed in articles:
                # Insert article into output database
                output_cursor.execute('''
                    INSERT OR IGNORE INTO articles (title, processed) 
                    VALUES (?, ?)
                ''', (title, processed))
                
                # If article was already in output DB and is now processed, update it
                if processed:
                    output_cursor.execute('''
                        UPDATE articles 
                        SET processed = TRUE 
                        WHERE title = ? AND processed = FALSE
                    ''', (title,))
                
                # Get article IDs in both databases
                input_cursor.execute('SELECT id FROM articles WHERE title = ?', (title,))
                input_article_id = input_cursor.fetchone()[0]
                
                output_cursor.execute('SELECT id FROM articles WHERE title = ?', (title,))
                output_article_id = output_cursor.fetchone()[0]
                
                # Copy links
                input_cursor.execute('''
                    SELECT to_article_title FROM links 
                    WHERE from_article_id = ?
                ''', (input_article_id,))
                
                links = input_cursor.fetchall()
                for (to_title,) in links:
                    output_cursor.execute('''
                        INSERT OR IGNORE INTO links (from_article_id, to_article_title)
                        VALUES (?, ?)
                    ''', (output_article_id, to_title))
                    link_count += 1
                
                article_count += 1
                
                if article_count % 1000 == 0:
                    output_conn.commit()
                    logger.info(f"Merged {article_count} articles and {link_count} links...")
            
            output_conn.commit()
            logger.info(f"Successfully merged {article_count} articles and {link_count} links from {input_db}")
            
            return True
            
        except Exception as e:
            logger.error(f"Error merging database {input_db}: {e}")
            output_conn.rollback()
            return False
            
        finally:
            input_conn.close()
            output_conn.close()
    
    def merge_multiple_databases(self, input_databases):
        """Merge multiple databases into the output database."""
        logger.info(f"Starting merge of {len(input_databases)} databases...")
        
        success_count = 0
        for db in input_databases:
            if self.merge_database(db):
                success_count += 1
        
        logger.info(f"Merge complete! Successfully merged {success_count}/{len(input_databases)} databases")
        
        # Print final statistics
        self.print_stats()
    
    def print_stats(self):
        """Print statistics about the merged database."""
        conn = sqlite3.connect(self.output_db)
        cursor = conn.cursor()
        
        cursor.execute('SELECT COUNT(*) FROM articles')
        total_articles = cursor.fetchone()[0]
        
        cursor.execute('SELECT COUNT(*) FROM articles WHERE processed = TRUE')
        processed_articles = cursor.fetchone()[0]
        
        cursor.execute('SELECT COUNT(*) FROM links')
        total_links = cursor.fetchone()[0]
        
        conn.close()
        
        logger.info("=" * 50)
        logger.info("MERGED DATABASE STATISTICS")
        logger.info("=" * 50)
        logger.info(f"Total articles: {total_articles:,}")
        logger.info(f"Processed articles: {processed_articles:,}")
        logger.info(f"Remaining articles: {(total_articles - processed_articles):,}")
        logger.info(f"Total links: {total_links:,}")
        logger.info(f"Average links per processed article: {total_links / max(processed_articles, 1):.2f}")
        logger.info("=" * 50)

def main():
    parser = argparse.ArgumentParser(description='Merge multiple Wikipedia Mapper databases')
    parser.add_argument('databases', nargs='+',
                       help='List of database files to merge')
    parser.add_argument('--output', '-o', type=str, default='wiki_mapping_merged.db',
                       help='Output database file name')
    
    args = parser.parse_args()
    
    merger = DatabaseMerger(output_db=args.output)
    merger.merge_multiple_databases(args.databases)

if __name__ == "__main__":
    main()

import sqlite3
import requests
import gzip
import time
import re
from urllib.parse import quote
import logging
import argparse
import hashlib

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class WikiMapperMultiMachine:
    def __init__(self, db_path='wiki_mapping.db', machine_id=0, total_machines=1):
        """
        Initialize WikiMapper for multi-machine processing.
        
        Args:
            db_path: Path to the SQLite database
            machine_id: ID of this machine (0-indexed)
            total_machines: Total number of machines in the cluster
        """
        self.db_path = db_path
        self.machine_id = machine_id
        self.total_machines = total_machines
        self.session = requests.Session()
        self.session.headers.update({'User-Agent': 'WikiMapper/1.0'})
        self.init_database()
        
        logger.info(f"Initialized machine {machine_id} of {total_machines}")
    
    def init_database(self):
        """Initialize the SQLite database with required tables."""
        conn = sqlite3.connect(self.db_path)
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
    
    def get_article_hash(self, title):
        """Get a consistent hash for an article title."""
        return int(hashlib.md5(title.encode('utf-8')).hexdigest(), 16)
    
    def should_process_article(self, title):
        """Determine if this machine should process this article based on hash partitioning."""
        article_hash = self.get_article_hash(title)
        return (article_hash % self.total_machines) == self.machine_id
    
    def get_article_links(self, title):
        """Get all links from a Wikipedia article."""
        url = "https://en.wikipedia.org/api/rest_v1/page/html/" + quote(title)
        
        try:
            response = self.session.get(url, timeout=30)
            response.raise_for_status()
            
            # Extract links using regex (REST API uses relative links with ./)
            # This looks for Wikipedia article links in the HTML
            link_pattern = r'href="\./([^":#]+)"'
            links = re.findall(link_pattern, response.text)
            
            # Clean and filter links
            clean_links = []
            for link in links:
                # Decode URL encoding and filter out special pages
                decoded = requests.utils.unquote(link)
                if not any(prefix in decoded for prefix in ['File:', 'Category:', 'Template:', 'Help:', 'Special:', 'Wikipedia:']):
                    clean_links.append(decoded.replace('_', ' '))
            
            return list(set(clean_links))  # Remove duplicates
            
        except Exception as e:
            logger.error(f"Error fetching links for {title}: {e}")
            return []
    
    def save_article_links(self, article_title, links):
        """Save article and its links to the database."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        try:
            # Insert or get article ID
            cursor.execute('INSERT OR IGNORE INTO articles (title) VALUES (?)', (article_title,))
            cursor.execute('SELECT id FROM articles WHERE title = ?', (article_title,))
            article_id = cursor.fetchone()[0]
            
            # Insert links
            for link in links:
                cursor.execute('''
                    INSERT OR IGNORE INTO links (from_article_id, to_article_title) 
                    VALUES (?, ?)
                ''', (article_id, link))
            
            # Mark article as processed
            cursor.execute('UPDATE articles SET processed = TRUE WHERE id = ?', (article_id,))
            
            conn.commit()
            logger.info(f"Saved {len(links)} links for article: {article_title}")
            
        except Exception as e:
            logger.error(f"Error saving links for {article_title}: {e}")
            conn.rollback()
        finally:
            conn.close()
    
    def get_all_titles(self):
        """Download and parse Wikipedia all-titles dump."""
        dump_url = "https://dumps.wikimedia.org/enwiki/latest/enwiki-latest-all-titles-in-ns0.gz"
        
        logger.info("Downloading Wikipedia titles dump...")
        response = self.session.get(dump_url, stream=True)
        response.raise_for_status()
        
        titles = []
        with gzip.open(response.raw, 'rt', encoding='utf-8') as f:
            for line in f:
                title = line.strip()
                if title and not title.startswith('#'):
                    titles.append(title.replace('_', ' '))
        
        logger.info(f"Downloaded {len(titles)} article titles")
        return titles
    
    def populate_articles_table(self):
        """Populate the articles table with titles assigned to this machine."""
        all_titles = self.get_all_titles()
        
        # Filter titles for this machine based on hash partitioning
        my_titles = [title for title in all_titles if self.should_process_article(title)]
        
        logger.info(f"Machine {self.machine_id}: Processing {len(my_titles)} of {len(all_titles)} total titles")
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.executemany('INSERT OR IGNORE INTO articles (title) VALUES (?)', 
                          [(title,) for title in my_titles])
        conn.commit()
        conn.close()
        
        logger.info(f"Populated articles table with {len(my_titles)} titles for machine {self.machine_id}")
    
    def get_next_unprocessed_articles(self, batch_size=100):
        """Get next batch of unprocessed articles."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('''
            SELECT title FROM articles 
            WHERE processed = FALSE 
            ORDER BY id 
            LIMIT ?
        ''', (batch_size,))
        
        articles = [row[0] for row in cursor.fetchall()]
        conn.close()
        
        return articles
    
    def initial_run(self):
        """Initial run - populate articles table and start processing."""
        logger.info(f"Starting initial run on machine {self.machine_id}...")
        
        # Populate articles table from Wikipedia dump (only this machine's partition)
        self.populate_articles_table()
        
        # Start batch processing
        self.batch_run()
    
    def batch_run(self, batch_size=100, delay=1):
        """Continue processing unprocessed articles."""
        logger.info(f"Starting batch run on machine {self.machine_id}...")
        
        while True:
            articles = self.get_next_unprocessed_articles(batch_size)
            
            if not articles:
                logger.info("No more articles to process. Complete!")
                break
            
            logger.info(f"Processing batch of {len(articles)} articles...")
            
            for article in articles:
                try:
                    links = self.get_article_links(article)
                    self.save_article_links(article, links)
                    time.sleep(delay)  # Rate limiting
                    
                except Exception as e:
                    logger.error(f"Error processing article {article}: {e}")
                    continue
    
    def get_stats(self):
        """Get current processing statistics."""
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.execute('SELECT COUNT(*) FROM articles')
        total_articles = cursor.fetchone()[0]
        
        cursor.execute('SELECT COUNT(*) FROM articles WHERE processed = TRUE')
        processed_articles = cursor.fetchone()[0]
        
        cursor.execute('SELECT COUNT(*) FROM links')
        total_links = cursor.fetchone()[0]
        
        conn.close()
        
        return {
            'machine_id': self.machine_id,
            'total_machines': self.total_machines,
            'total_articles': total_articles,
            'processed_articles': processed_articles,
            'remaining_articles': total_articles - processed_articles,
            'total_links': total_links
        }

def main():
    parser = argparse.ArgumentParser(description='Wikipedia Mapper - Multi-Machine Edition')
    parser.add_argument('--machine-id', type=int, required=True,
                       help='ID of this machine (0-indexed, e.g., 0, 1, 2, ...)')
    parser.add_argument('--total-machines', type=int, required=True,
                       help='Total number of machines in the cluster')
    parser.add_argument('--db-path', type=str, default='wiki_mapping.db',
                       help='Path to the SQLite database file')
    parser.add_argument('--batch-size', type=int, default=100,
                       help='Number of articles to process per batch')
    parser.add_argument('--delay', type=float, default=1.0,
                       help='Delay in seconds between API requests')
    
    args = parser.parse_args()
    
    # Validate machine ID
    if args.machine_id < 0 or args.machine_id >= args.total_machines:
        logger.error(f"Machine ID must be between 0 and {args.total_machines - 1}")
        return
    
    # Use machine-specific database name
    db_path = f"wiki_mapping_machine_{args.machine_id}.db"
    if args.db_path != 'wiki_mapping.db':
        db_path = args.db_path
    
    mapper = WikiMapperMultiMachine(
        db_path=db_path,
        machine_id=args.machine_id,
        total_machines=args.total_machines
    )
    
    # Check if this is initial run or continuation
    stats = mapper.get_stats()
    
    if stats['total_articles'] == 0:
        logger.info("No articles found. Starting initial run...")
        mapper.initial_run()
    else:
        logger.info(f"Found existing data: {stats}")
        logger.info("Continuing batch processing...")
        mapper.batch_run(batch_size=args.batch_size, delay=args.delay)

if __name__ == "__main__":
    main()

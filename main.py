import sqlite3
import requests
import gzip
import time
import re
from urllib.parse import quote
import logging

# Set up logging
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')
logger = logging.getLogger(__name__)

class WikiMapper:
    def __init__(self, db_path='wiki_mapping.db'):
        self.db_path = db_path
        self.session = requests.Session()
        self.session.headers.update({'User-Agent': 'WikiMapper/1.0'})
        self.init_database()
    
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
        """Populate the articles table with all Wikipedia titles."""
        titles = self.get_all_titles()
        
        conn = sqlite3.connect(self.db_path)
        cursor = conn.cursor()
        
        cursor.executemany('INSERT OR IGNORE INTO articles (title) VALUES (?)', 
                          [(title,) for title in titles])
        conn.commit()
        conn.close()
        
        logger.info(f"Populated articles table with {len(titles)} titles")
    
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
        logger.info("Starting initial run...")
        
        # Populate articles table from Wikipedia dump
        self.populate_articles_table()
        
        # Start batch processing
        self.batch_run()
    
    def batch_run(self, batch_size=100, delay=1):
        """Continue processing unprocessed articles."""
        logger.info("Starting batch run...")
        
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
            'total_articles': total_articles,
            'processed_articles': processed_articles,
            'remaining_articles': total_articles - processed_articles,
            'total_links': total_links
        }

def main():
    mapper = WikiMapper()
    
    # Check if this is initial run or continuation
    stats = mapper.get_stats()
    
    if stats['total_articles'] == 0:
        logger.info("No articles found. Starting initial run...")
        mapper.initial_run()
    else:
        logger.info(f"Found existing data: {stats}")
        logger.info("Continuing batch processing...")
        mapper.batch_run()

if __name__ == "__main__":
    main()
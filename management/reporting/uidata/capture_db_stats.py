import datetime
from .DictCache import DictCache

#
# because of the table scan (select_2 below), cache stats for 5
# minutes
#
last_stats = DictCache(datetime.timedelta(minutes=5))

def clear_cache():
    last_stats.reset()
    

def capture_db_stats(conn):

    stats = last_stats.get()
    if stats:
        return stats
    
    select_1 = 'SELECT min(`min`) AS `min`, max(`max`) AS `max`, sum(`count`) AS `count` FROM (SELECT min(connect_time) AS `min`, max(connect_time) AS `max`, count(*) AS `count` FROM mta_connection  UNION  SELECT min(connect_time) AS `min`, max(connect_time) AS `max`, count(*) AS `count` FROM imap_connection)'

    # table scan
    select_2 = 'SELECT disposition, sum(count) as `count` FROM (SELECT disposition, count(*) AS `count` FROM mta_connection GROUP BY disposition  UNION  SELECT disposition, count(*) AS `count` FROM imap_connection GROUP BY disposition) GROUP BY disposition'
    
    c = conn.cursor()
    stats = {
        # all times are in this format: "YYYY-MM-DD HH:MM:SS" (utc)
        'date_parse_format': '%Y-%m-%d %H:%M:%S'
    }
    try:
        row = c.execute(select_1).fetchone()
        stats['db_stats'] = {
            'connect_time': {
                'min': row['min'],
                'max': row['max'], # YYYY-MM-DD HH:MM:SS (utc)
            },
            'count': row['count'],
            'disposition': {}
        }

        for row in c.execute(select_2):
            stats['db_stats']['disposition'][row['disposition']] =  {
                'count': row['count']
            }
        
    finally:
        c.close()

    last_stats.set(stats)
    return stats

-- pie chart for "connections by disposition"
--
-- returns a table of disposition along with it's count

SELECT disposition, sum(count) AS `count`
FROM (
  SELECT disposition, count(*) AS `count`
  FROM mta_connection
  WHERE connect_time>=:start_date AND connect_time<:end_date
  GROUP by disposition
  
  UNION
 
  SELECT disposition, count(*) AS `count`
  FROM imap_connection
  WHERE connect_time>=:start_date AND connect_time<:end_date
  GROUP BY disposition
)
GROUP BY disposition

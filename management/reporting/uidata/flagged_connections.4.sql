--
-- top 10 servers getting rejected by category
--
SELECT CASE WHEN remote_host='unknown' THEN remote_ip ELSE remote_host END AS `remote_host`, mta_accept.failure_category AS `category`, count(*) AS `count` 
FROM mta_connection
JOIN mta_accept ON mta_accept.mta_conn_id = mta_connection.mta_conn_id
WHERE
  mta_connection.service='smtpd' AND
  accept_status = 'reject' AND
  connect_time >= :start_date AND
  connect_time < :end_date
GROUP BY CASE WHEN remote_host='unknown' THEN remote_ip ELSE remote_host END, mta_accept.failure_category
ORDER BY count(*) DESC
LIMIT 10

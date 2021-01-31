--
-- top 10 remote servers/domains (remote hosts) by average spam score
--
SELECT CASE WHEN remote_host='unknown' THEN remote_ip ELSE remote_host END AS `remote_host`, avg(spam_score) AS avg_spam_score FROM mta_connection
JOIN mta_accept ON mta_accept.mta_conn_id = mta_connection.mta_conn_id
JOIN mta_delivery ON mta_accept.mta_accept_id = mta_delivery.mta_accept_id
WHERE mta_connection.service='smtpd' AND
  spam_score IS NOT NULL AND
  connect_time >= :start_date AND
  connect_time < :end_date
GROUP BY CASE WHEN remote_host='unknown' THEN remote_ip ELSE remote_host END
ORDER BY avg(spam_score) DESC
LIMIT 10

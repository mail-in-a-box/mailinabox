--
-- top 10 senders by message count
--
SELECT count(mta_accept_id) AS count, sasl_username AS username
FROM mta_connection
JOIN mta_accept ON mta_accept.mta_conn_id = mta_connection.mta_conn_id
WHERE mta_connection.service = "submission" AND
  queue_time IS NOT NULL AND
  connect_time >= :start_date AND
  connect_time < :end_date
GROUP BY sasl_username
ORDER BY count(mta_accept_id) DESC
LIMIT 10

--
-- top 10 senders by message size
--
SELECT sum(message_size) AS message_size_total, sasl_username AS username
FROM mta_connection
JOIN mta_accept ON mta_accept.mta_conn_id = mta_connection.mta_conn_id
WHERE mta_connection.service = "submission" AND
  connect_time >= :start_date AND
  connect_time < :end_date
GROUP BY sasl_username
ORDER BY sum(message_size) DESC
LIMIT 10

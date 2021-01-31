--
-- top 10 users receiving the most spam
--
SELECT rcpt_to, count(*) AS count FROM mta_delivery
JOIN mta_accept ON mta_accept.mta_accept_id = mta_delivery.mta_accept_id
JOIN mta_connection ON mta_accept.mta_conn_id = mta_connection.mta_conn_id
WHERE spam_result='spam' AND
  connect_time >= :start_date AND
  connect_time < :end_date
GROUP BY rcpt_to
ORDER BY count(*) DESC
LIMIT 10

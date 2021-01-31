--
-- top 10 senders (envelope_from) by message size
--
SELECT sum(message_size) AS `size`, envelope_from AS `email`
FROM mta_connection
JOIN mta_accept on mta_accept.mta_conn_id = mta_connection.mta_conn_id
WHERE mta_connection.service = "smtpd" AND
  connect_time >= :start_date AND
  connect_time < :end_date
GROUP BY envelope_from
ORDER BY sum(message_size) DESC
LIMIT 10

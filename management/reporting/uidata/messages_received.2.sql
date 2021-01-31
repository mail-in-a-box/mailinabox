--
-- top 10 senders (envelope_from) by message count
--
SELECT count(mta_accept_id) AS `count`, envelope_from AS `email`
FROM mta_connection
JOIN mta_accept on mta_accept.mta_conn_id = mta_connection.mta_conn_id
WHERE
  mta_connection.service = "smtpd" AND
  accept_status != 'reject' AND
  connect_time >= :start_date AND
  connect_time < :end_date
GROUP BY envelope_from
ORDER BY count(mta_accept_id) DESC
LIMIT 10

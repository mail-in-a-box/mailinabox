--
-- returns count of messages received by smtpd in each 'bin', which is
-- the connection time rounded (as defined by {timefmt})
--
SELECT
  strftime('{timefmt}',connect_time) AS `bin`,
  count(*) AS `count`
FROM mta_accept
JOIN mta_connection ON mta_connection.mta_conn_id = mta_accept.mta_conn_id
WHERE
  mta_connection.service = 'smtpd' AND
  connect_time >= :start_date AND
  connect_time < :end_date
GROUP BY strftime('{timefmt}',connect_time)
ORDER BY connect_time

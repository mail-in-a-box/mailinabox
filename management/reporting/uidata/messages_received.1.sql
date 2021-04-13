--
-- returns count of messages received by smtpd in each 'bin', which is
-- the connection time rounded (as defined by {timefmt})
--
SELECT
  strftime('{timefmt}',
    :start_unixepoch + cast((strftime('%s',connect_time) - :start_unixepoch) / (60 * :binsize) as int) * (60 * :binsize),
    'unixepoch'
  ) AS `bin`,
  count(*) AS `count`
FROM mta_accept
JOIN mta_connection ON mta_connection.mta_conn_id = mta_accept.mta_conn_id
WHERE
  mta_connection.service = 'smtpd' AND
  connect_time >= :start_date AND
  connect_time < :end_date
GROUP BY bin
ORDER BY connect_time

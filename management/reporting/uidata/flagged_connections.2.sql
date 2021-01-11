--
-- returns count of suspected_scanner in each 'bin', which is the
-- connection time rounded (as defined by {timefmt})
--
SELECT
  strftime('{timefmt}',connect_time) AS `bin`,
  count(*) AS `count`
FROM mta_connection
WHERE
  disposition='suspected_scanner' AND
  connect_time >= :start_date AND
  connect_time < :end_date
GROUP BY strftime('{timefmt}',connect_time)
ORDER BY connect_time

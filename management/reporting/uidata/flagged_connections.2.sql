--
-- returns count of suspected_scanner in each 'bin', which is the
-- connection time rounded (as defined by {timefmt})
--
SELECT bin, sum(count) AS `count`
FROM (
  SELECT
    strftime('{timefmt}',
      :start_unixepoch + cast((strftime('%s',connect_time) - :start_unixepoch) / (60 * :binsize) as int) * (60 * :binsize),
      'unixepoch'
    ) AS `bin`,
    count(*) AS `count`
  FROM mta_connection
  WHERE
    disposition='suspected_scanner' AND
    connect_time >= :start_date AND
    connect_time < :end_date
  GROUP BY strftime('{timefmt}',connect_time)

  UNION

  SELECT
    strftime('{timefmt}',
      :start_unixepoch + cast((strftime('%s',connect_time) - :start_unixepoch) / (60 * :binsize) as int) * (60 * :binsize),
      'unixepoch'
    ) AS `bin`,
    count(*) AS `count`
  FROM imap_connection
  WHERE
    disposition='suspected_scanner' AND
    connect_time >= :start_date AND
    connect_time < :end_date
  GROUP BY strftime('{timefmt}',connect_time)
)
GROUP BY bin
ORDER BY bin

--
-- returns count of failed_login_attempt in each 'bin', which is the
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
    disposition='failed_login_attempt' AND
    connect_time >= :start_date AND
    connect_time < :end_date
    GROUP BY bin

  UNION
  
  SELECT
    strftime('{timefmt}',
      :start_unixepoch + cast((strftime('%s',connect_time) - :start_unixepoch) / (60 * :binsize) as int) * (60 * :binsize),
      'unixepoch'
    ) AS `bin`,
    count(*) AS `count`
  FROM imap_connection
  WHERE
    disposition='failed_login_attempt' AND
    connect_time >= :start_date AND
    connect_time < :end_date
  GROUP BY bin
)
GROUP BY bin
ORDER BY bin

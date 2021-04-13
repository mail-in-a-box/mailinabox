--
-- imap connection summary
--
SELECT
  count(*) as `count`,
  disposition,
  CASE WHEN remote_host='unknown' THEN remote_ip ELSE remote_host END AS `remote_host`,
  sum(in_bytes) as `in_bytes`,
  sum(out_bytes) as `out_bytes`,
  min(connect_time) as `first_connection_time`,
  max(connect_time) as `last_connection_time`
FROM
  imap_connection
WHERE
  sasl_username = :user_id AND
  connect_time >= :start_date AND
  connect_time < :end_date
GROUP BY
  disposition,
  CASE WHEN remote_host='unknown' THEN remote_ip ELSE remote_host END
ORDER BY
  `count` DESC, disposition

--
-- details on user imap connections
--
SELECT
  connect_time,
  CASE WHEN remote_host='unknown' THEN remote_ip ELSE remote_host END AS `remote_host`,
  sasl_method,
  disconnect_reason,
  connection_security,
  disposition,
  in_bytes,
  out_bytes
FROM
  imap_connection
WHERE
  sasl_username = :user_id AND
  connect_time >= :start_date AND
  connect_time < :end_date
ORDER BY
  connect_time

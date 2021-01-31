--
-- details on remote sender host
-- query: remote_host or remote_ip
--
SELECT
-- mta_connection
connect_time, disposition,
-- mta_accept
mta_accept.mta_accept_id AS mta_accept_id, spf_result, dkim_result, dkim_reason, dmarc_result, dmarc_reason, accept_status, failure_info, mta_accept.failure_category AS `category`, envelope_from,
-- mta_delivery
rcpt_to, postgrey_result, postgrey_reason, postgrey_delay, spam_score, spam_result, message_size
FROM mta_connection
LEFT JOIN mta_accept ON mta_accept.mta_conn_id = mta_connection.mta_conn_id
LEFT JOIN mta_delivery ON mta_accept.mta_accept_id = mta_delivery.mta_accept_id
WHERE
  (remote_host = :remote_host OR remote_ip = :remote_host) AND
  mta_connection.service = 'smtpd' AND
  connect_time >= :start_date AND
  connect_time < :end_date
ORDER BY connect_time

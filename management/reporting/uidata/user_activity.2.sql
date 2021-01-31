--
-- details on user received mail
--
SELECT
-- mta_connection
connect_time, mta_connection.service AS service, sasl_username, disposition,
-- mta_accept
envelope_from, spf_result, dkim_result, dkim_reason, dmarc_result, dmarc_reason,
-- mta_delivery
postgrey_result, postgrey_reason, postgrey_delay, spam_score, spam_result, message_size, orig_to
FROM mta_accept
JOIN mta_connection ON mta_accept.mta_conn_id = mta_connection.mta_conn_id
JOIN mta_delivery ON mta_accept.mta_accept_id = mta_delivery.mta_accept_id
WHERE rcpt_to = :user_id AND
  connect_time >= :start_date AND
  connect_time < :end_date
ORDER BY connect_time

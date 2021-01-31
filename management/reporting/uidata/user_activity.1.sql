--
-- details on user sent mail
--
SELECT
-- mta_connection
connect_time, sasl_method,
-- mta_accept
mta_accept.mta_accept_id AS mta_accept_id, envelope_from,
-- mta_delivery
mta_delivery.service AS service, rcpt_to, spam_score, spam_result, message_size, status, relay, delivery_info, delivery_connection, delivery_connection_info
FROM mta_accept
JOIN mta_connection ON mta_accept.mta_conn_id = mta_connection.mta_conn_id
JOIN mta_delivery ON mta_accept.mta_accept_id = mta_delivery.mta_accept_id
WHERE sasl_username = :user_id AND
  connect_time >= :start_date AND
  connect_time < :end_date
ORDER BY connect_time, mta_accept.mta_accept_id

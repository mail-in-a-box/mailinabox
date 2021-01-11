--
-- outbound mail using an insecure connection (low grade encryption)
--
SELECT mta_delivery.service AS `service`, sasl_username, envelope_from, rcpt_to, count(*) AS `count`
FROM mta_connection
LEFT JOIN mta_accept ON mta_accept.mta_conn_id = mta_connection.mta_conn_id
LEFT JOIN mta_delivery ON mta_delivery.mta_accept_id = mta_accept.mta_accept_id
WHERE 
  delivery_connection = 'untrusted' AND
  connect_time >= :start_date AND
  connect_time < :end_date
GROUP BY mta_connection.service, sasl_username, envelope_from, rcpt_to

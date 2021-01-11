--
-- returns count of sent messages delivered in each 'bin'/delivery
-- service combination. the bin is the connection time rounded (as
-- defined by {timefmt})
--
SELECT
  strftime('{timefmt}',connect_time) AS `bin`,
  mta_delivery.service AS `delivery_service`,
  count(*) AS `delivery_count`
FROM mta_accept
JOIN mta_connection ON mta_connection.mta_conn_id = mta_accept.mta_conn_id
JOIN mta_delivery ON mta_delivery.mta_accept_id = mta_accept.mta_accept_id
WHERE
  (mta_connection.service = 'submission' OR mta_connection.service = 'pickup') AND
  connect_time >= :start_date AND
  connect_time < :end_date
GROUP BY strftime('{timefmt}',connect_time), mta_delivery.service
ORDER BY connect_time

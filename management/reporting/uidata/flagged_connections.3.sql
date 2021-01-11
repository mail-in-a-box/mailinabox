SELECT failure_category, count(*) AS `count`
FROM mta_connection
JOIN mta_accept ON mta_accept.mta_conn_id = mta_connection.mta_conn_id
WHERE
   disposition='reject' AND
   connect_time >=:start_date AND
   connect_time <:end_date
GROUP BY failure_category

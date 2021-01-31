--
-- top 10 senders by message count
--
select count(mta_accept_id) as count, sasl_username as username
from mta_connection
join mta_accept on mta_accept.mta_conn_id = mta_connection.mta_conn_id
where mta_connection.service = "submission" AND
  connect_time >= :start_date AND
  connect_time < :end_date
group by sasl_username
order by count(mta_accept_id) DESC
limit 10

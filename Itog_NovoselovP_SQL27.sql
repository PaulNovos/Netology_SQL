/* 1) � ����� ������� ������ ������ ���������? */
select city as �����, count(airport_code) as ����������_����������
from airports
group by city 
having count(airport_code) > 1
order by 2 desc;

/* 2) � ����� ���������� ���� �����, ����������� ��������� � ������������ ���������� ��������? */
select airport_name||', '||city as ��������
from airports inner join (select distinct departure_airport
							 from flights
							 where aircraft_code in (
										select aircraft_code 
										from aircrafts
										where "range" = (select max(range) from aircrafts)
										)
							) query on airports.airport_code = query.departure_airport;
					
/* 3) ������� 10 ������ � ������������ �������� �������� ������ */						
select flight_no as �����_�����, status as ������, actual_departure - scheduled_departure as ��������
from flights
where status in ('Departed', 'Arrived')
order by �������� desc limit 10;

/* 4) ���� �� �����, �� ������� �� ���� �������� ���������� ������? */
select book_ref as �����_�����, passenger_name as ��������, flight_no as �����_�����, status as ������, boarding_no as �����_�����������_������
from tickets t left join boarding_passes bp on t.ticket_no = bp.ticket_no 
				left join flights f2 on bp.flight_id = f2.flight_id
where status in ('Departed', 'Arrived') and boarding_no is null;

/* 5) ������� ��������� ����� ��� ������� �����, �� % ��������� � ������ ���������� ���� � ��������.
�������� ������� � ������������� ������ - ��������� ���������� ���������� ���������� ���������� �� ������� ��������� �� ������ ����. 
�.�. � ���� ������� ������ ���������� ������������� ����� - ������� ������� ��� �������� �� ������� ��������� �� ���� ��� ����� ������ ������ �� ����.
 */
select flight_no as �����_�����, airport_name||', '||city as ��������_������, scheduled_departure as �����_������,
	   total_seats as �����_����_�_��������, real_seats as ����_������, (total_seats - real_seats) as ����_��������,
	   (round(((total_seats - real_seats)::numeric/total_seats::numeric), 2)*100)::integer||'%' as �������_���������_����,
	   sum(real_seats) over (partition by departure_airport, date_trunc('day', scheduled_departure) order by scheduled_departure) as ����������_�����_��_����
from (
	  select flight_id, count(seat_no) as real_seats
	  from boarding_passes bp
	  group by flight_id) rs
inner join 
	  flights f 
	  on rs.flight_id = f.flight_id 
inner join
	  (select aircraft_code, count(seat_no) as total_seats
	   from seats s 
	   group by aircraft_code
	  ) ts
	  on f.aircraft_code = ts.aircraft_code
inner join airports a2 
	  on f.departure_airport = a2.airport_code 
order by departure_airport, scheduled_departure desc;

/* 6) ������� ���������� ����������� ��������� �� ����� ��������� �� ������ ���������� */
select distinct model as �������,
	   count(flight_id) over (partition by f.aircraft_code) as ��������_��������,
	   count(flight_id) over() as ���������_�����,
	   (round((count(flight_id) over (partition by f.aircraft_code)::numeric/count(flight_id) over()::numeric), 2)*100)::integer||'%' as �������_���������
from flights f right join aircrafts a 
			   on f.aircraft_code = a.aircraft_code
group by model, flight_id;

/* 7) ���� �� ������, � ������� �����  ��������� ������ - ������� �������, ��� ������-������� � ������ ��������? */
with cte_business as (
					  select flight_id, fare_conditions, amount as business_amount
					  from ticket_flights
					  where fare_conditions = 'Business'
					 ),
	 cte_economy as (
					  select flight_id, fare_conditions, amount as economy_amount
					  from ticket_flights
					  where fare_conditions = 'Economy'
					 )
select flight_no as �����_�����, city as �����,
	   cte_business.fare_conditions as ������_�����, business_amount as ���������_�������, 
	   cte_economy.fare_conditions as ������_�����, economy_amount as ���������_�������
from flights inner join cte_business on flights.flight_id = cte_business.flight_id
			 inner join cte_economy on flights.flight_id = cte_economy.flight_id
			 inner join airports on flights.arrival_airport = airports.airport_code 
where business_amount < economy_amount
group by flight_no, city, cte_business.fare_conditions, business_amount, cte_economy.fare_conditions, economy_amount;

/* 8) ����� ������ �������� ��� ������ ������? */
create view departure as (
						 select distinct city as departure_city
						 from flights inner join airports
						 	          on flights.departure_airport = airports.airport_code
						 );
create view arrival as (
						 select distinct city as arrival_city
						 from flights inner join airports
						 	          on flights.arrival_airport = airports.airport_code
						);	
					
select departure_city as �����_�����������, arrival_city as �����_��������
from departure d, arrival a
where departure_city <> arrival_city
except 
select departure_city, arrival_city
from flights_v fv
order by 1, 2;

/* 9) ��������� ���������� ����� �����������, ���������� ������� �������, �������� � ���������� ������������ ���������� ���������  � ���������, ������������� ��� �����
 ���������� ���������� ����� ����� ������� A � B �� ������ ����������� (���� ������� �� �� �����) ������������ ������������:
d = arccos {sin(latitude_a)�sin(latitude_b) + cos(latitude_a)�cos(latitude_b)�cos(longitude_a - longitude_b)}, ��� latitude_a � latitude_b � ������, longitude_a, longitude_b � ������� ������ �������,
d � ���������� ����� �������� ���������� � �������� ������ ���� �������� ����� ������� ����.
���������� ����� ��������, ���������� � ����������, ������������ �� �������:
L = d�R, ��� R = 6371 �� � ������� ������ ������� ����.
 */
with cte_departure as (
					   select airport_code, airport_name||', '||city as ��������_������, latitude as departure_latitude, longitude as departure_longitude
					   from airports
					  ),
	 cte_arrival as (
					   select airport_code, airport_name||', '||city as ��������_�������, latitude as arrival_latitude, longitude as arrival_longitude
					   from airports
					  ),
	 cte_dep_ar as (
					   select f.departure_airport, ctd.��������_������, cta.��������_�������, f.arrival_airport, f.aircraft_code,
					   round((6371 * (acos(sind(departure_latitude)*sind(arrival_latitude) + cosd(departure_latitude)*cosd(arrival_latitude)*cosd(departure_longitude - arrival_longitude))))) as ����������
					    from flights f inner join cte_departure ctd
					    			   on f.departure_airport = ctd.airport_code
					    			   inner join cte_arrival cta
					    			   on f.arrival_airport = cta.airport_code
					  )					  					    			  
select ��������_������, ��������_�������, model as �������, "range" as ���������_������, ����������
from cte_dep_ar inner join aircrafts 
			    on cte_dep_ar.aircraft_code = aircrafts.aircraft_code
group by 1, 2, 3, 4, 5
order by 1, 2, 5 desc;



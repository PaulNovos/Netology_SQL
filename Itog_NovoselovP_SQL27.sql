/* 1) В каких городах больше одного аэропорта? */
select city as Город, count(airport_code) as Количество_аэропортов
from airports
group by city 
having count(airport_code) > 1
order by 2 desc;

/* 2) В каких аэропортах есть рейсы, выполняемые самолетом с максимальной дальностью перелета? */
select airport_name||', '||city as Аэропорт
from airports inner join (select distinct departure_airport
							 from flights
							 where aircraft_code in (
										select aircraft_code 
										from aircrafts
										where "range" = (select max(range) from aircrafts)
										)
							) query on airports.airport_code = query.departure_airport;
					
/* 3) Вывести 10 рейсов с максимальным временем задержки вылета */						
select flight_no as Номер_рейса, status as Статус, actual_departure - scheduled_departure as Задержка
from flights
where status in ('Departed', 'Arrived')
order by Задержка desc limit 10;

/* 4) Были ли брони, по которым не были получены посадочные талоны? */
select book_ref as Номер_брони, passenger_name as Пассажир, flight_no as Номер_рейса, status as Статус, boarding_no as Номер_посадочного_талона
from tickets t left join boarding_passes bp on t.ticket_no = bp.ticket_no 
				left join flights f2 on bp.flight_id = f2.flight_id
where status in ('Departed', 'Arrived') and boarding_no is null;

/* 5) Найдите свободные места для каждого рейса, их % отношение к общему количеству мест в самолете.
Добавьте столбец с накопительным итогом - суммарное накопление количества вывезенных пассажиров из каждого аэропорта на каждый день. 
Т.е. в этом столбце должна отражаться накопительная сумма - сколько человек уже вылетело из данного аэропорта на этом или более ранних рейсах за день.
 */
select flight_no as Номер_рейса, airport_name||', '||city as Аэропорт_вылета, scheduled_departure as Время_вылета,
	   total_seats as Всего_мест_в_самолете, real_seats as Мест_занято, (total_seats - real_seats) as Мест_свободно,
	   (round(((total_seats - real_seats)::numeric/total_seats::numeric), 2)*100)::integer||'%' as Процент_свободных_мест,
	   sum(real_seats) over (partition by departure_airport, date_trunc('day', scheduled_departure) order by scheduled_departure) as Перевезено_людей_за_день
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

/* 6) Найдите процентное соотношение перелетов по типам самолетов от общего количества */
select distinct model as Самолет,
	   count(flight_id) over (partition by f.aircraft_code) as Перелеты_самолета,
	   count(flight_id) over() as Перелетов_всего,
	   (round((count(flight_id) over (partition by f.aircraft_code)::numeric/count(flight_id) over()::numeric), 2)*100)::integer||'%' as Процент_перелетов
from flights f right join aircrafts a 
			   on f.aircraft_code = a.aircraft_code
group by model, flight_id;

/* 7) Были ли города, в которые можно  добраться бизнес - классом дешевле, чем эконом-классом в рамках перелета? */
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
select flight_no as Номер_рейса, city as Город,
	   cte_business.fare_conditions as Бизнес_класс, business_amount as Стоимость_бизнеса, 
	   cte_economy.fare_conditions as Эконом_класс, economy_amount as Стоимость_эконома
from flights inner join cte_business on flights.flight_id = cte_business.flight_id
			 inner join cte_economy on flights.flight_id = cte_economy.flight_id
			 inner join airports on flights.arrival_airport = airports.airport_code 
where business_amount < economy_amount
group by flight_no, city, cte_business.fare_conditions, business_amount, cte_economy.fare_conditions, economy_amount;

/* 8) Между какими городами нет прямых рейсов? */
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
					
select departure_city as Город_отправления, arrival_city as Город_прибытия
from departure d, arrival a
where departure_city <> arrival_city
except 
select departure_city, arrival_city
from flights_v fv
order by 1, 2;

/* 9) Вычислите расстояние между аэропортами, связанными прямыми рейсами, сравните с допустимой максимальной дальностью перелетов  в самолетах, обслуживающих эти рейсы
 Кратчайшее расстояние между двумя точками A и B на земной поверхности (если принять ее за сферу) определяется зависимостью:
d = arccos {sin(latitude_a)·sin(latitude_b) + cos(latitude_a)·cos(latitude_b)·cos(longitude_a - longitude_b)}, где latitude_a и latitude_b — широты, longitude_a, longitude_b — долготы данных пунктов,
d — расстояние между пунктами измеряется в радианах длиной дуги большого круга земного шара.
Расстояние между пунктами, измеряемое в километрах, определяется по формуле:
L = d·R, где R = 6371 км — средний радиус земного шара.
 */
with cte_departure as (
					   select airport_code, airport_name||', '||city as Аэропорт_вылета, latitude as departure_latitude, longitude as departure_longitude
					   from airports
					  ),
	 cte_arrival as (
					   select airport_code, airport_name||', '||city as Аэропорт_прилета, latitude as arrival_latitude, longitude as arrival_longitude
					   from airports
					  ),
	 cte_dep_ar as (
					   select f.departure_airport, ctd.Аэропорт_вылета, cta.Аэропорт_прилета, f.arrival_airport, f.aircraft_code,
					   round((6371 * (acos(sind(departure_latitude)*sind(arrival_latitude) + cosd(departure_latitude)*cosd(arrival_latitude)*cosd(departure_longitude - arrival_longitude))))) as Расстояние
					    from flights f inner join cte_departure ctd
					    			   on f.departure_airport = ctd.airport_code
					    			   inner join cte_arrival cta
					    			   on f.arrival_airport = cta.airport_code
					  )					  					    			  
select Аэропорт_вылета, Аэропорт_прилета, model as Самолет, "range" as Дальность_полета, Расстояние
from cte_dep_ar inner join aircrafts 
			    on cte_dep_ar.aircraft_code = aircrafts.aircraft_code
group by 1, 2, 3, 4, 5
order by 1, 2, 5 desc;



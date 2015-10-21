-- tables 
drop table if exists users;
create table users(id serial primary key, name text);

drop table if exists logins;
create table logins(id serial primary key, user_id int references users(id), login_time timestamptz);

-- dummy data
insert into users(name) values('joao'),('paulo')

insert into logins(user_id, login_time) 
values(
  1, 
  timestamptz '2015-10-01 00:00:00' + random() * (timestamp '2015-10-30 00:00:00' - timestamp '2015-10-01 00:00:00')
)

select * from logins;
select * from users;

-- select aggregate data + info about the user

-- approach 1: direct subquery
select id, name, num_logins, avg_hour
from users 
inner join
(
  select user_id, count(user_id) as num_logins, avg(date_part('hour', login_time)) as avg_hour
  from logins
  group by user_id
) as statistics
on statistics.user_id = users.id

-- approach 1: using a cte
with statistics as (
  select user_id, count(user_id) as num_logins, avg(date_part('hour', login_time)) as avg_hour
  from logins
  group by user_id
)
select id, name, num_logins, avg_hour
from users 
outer join statistics
on statistics.user_id = users.id

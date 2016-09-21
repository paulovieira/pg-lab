/*
this example is based on this screencast:
https://www.pgcasts.com/episodes/1/generating-json-from-sql/
*/

-- prepare data

create table users(
    id int primary key,
    email text unique not null,
    name text,
    pw text not null
);

insert into users values
    (1, 'john@example.com', 'John', '123'),
    (2, 'jane@example.com', 'Jane', '456');

-- retrieve as json using row_to_json

select row_to_json(users)
from users

-- we can exclude some fields in the json with the row constructor

select row_to_json(row(id, name, email))
from users

-- but this will remove the names of the columns in the properties names
-- to get it back we can use a subquery and call row_to_json with the subquery

select row_to_json(t)
from (
    select id, name, email
    from users
) t;


-- better yet: simply use json_build_object!

select json_build_object('id', id, 'name', name, 'email', email)
from users;


-- now let's introduce a second table to obtain nested json data:

create table bookmarks(
    id serial primary key,
    user_id integer not null references users,
    name text,
    url text
);

insert into bookmarks(user_id, name, url) values
    (1, 'Twitter', 'twitter.com'),
    (1, 'PG Docs', 'postgresql.org/docs/current/static/index.html'),
    (2, 'Google', 'google.com'),
    (2, 'Stack Overflow', 'stackoverflow.com'),
    (2, 'YouTube', 'youtube.com');



-- using the row_to_json + subquery

select row_to_json(t1)
from (
    select 
        u.id as id, 
        u.name as name, 
        u.email as email,
        (
            select json_agg(row_to_json(t2)) 
            from (
                select b.name, b.url
                from bookmarks b
                where b.user_id = u.id
            ) t2

        ) as bm

    from users u
) t1


-- using json_build_object

select json_build_object('id', id, 'name', name, 'email', email, 'bm', bm)
from (
    select 
        u.id as id, 
        u.name as name, 
        u.email as email,
        (
            select json_agg(json_build_object('name', b.name, 'url', b.url))
            from bookmarks b
            where b.user_id = u.id
        ) as bm
    from users u
) t

-- in previous case we still have to make a subquery and alias as t, but the subquery is not used;
-- when using postgres with in nodejs, the result set is retrieved as an array of objects where
-- each object corresponds to a row in the set; so it makes more sense use just the subquery

-- using the row_to_json + subquery

select 
    u.id as id, 
    u.name as name, 
    u.email as email,
    (
        select json_agg(row_to_json(t2)) 
        from (
            select b.name, b.url
            from bookmarks b
            where b.user_id = u.id
        ) t2

    ) as bm
from users u


-- using json_build_object

select 
    u.id as id, 
    u.name as name, 
    u.email as email,
    (
        select json_agg(json_build_object('name', b.name, 'url', b.url))
        from bookmarks b
        where b.user_id = u.id
    ) as bm
from users u


-- alternatively, using an inner join

select
    u.id as id, 
    u.name as name, 
    u.email as email, 
    json_agg(json_build_object('name', b.name, 'url', b.url)) as bm
from users u
join bookmarks b
on u.id = b.user_id
group by u.id


-- or yet in another way, first creating a cte with the 2 columns: the user id
-- and the corresponding aggregated data (this is essentialy the previous query,
-- but removing the name and email columns); then creating the main query;
-- the advantage is that we extract the complexity into a separate "component"
with bm_cte as (
    select 
        u.id as user_id,
        json_agg(json_build_object('name', b.name, 'url', b.url)) as bm
    from users u
    join bookmarks b
    on u.id = b.user_id
    group by u.id
)
select
    u.id as id, 
    u.name as name,
    u.email as email,
    bm_cte.bm
from users u
join bm_cte
on u.id = bm_cte.user_id


-- to be done: what if the user doesn't have any bookmarks?
-- see: https://github.com/paulovieira/pg-lab/blob/master/150326_retrieve_json.sql
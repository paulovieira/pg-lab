DROP TABLE IF EXISTS users CASCADE;
DROP TABLE IF EXISTS posts;

CREATE TABLE users(id serial primary key, name text, email text);
CREATE TABLE posts(id serial, title text, created_at timestamptz, author_id int references users(id));

insert into users(id, name, email) values
	(10, 'paulo', 'paulo@gmail.com'),
	(12, 'ana',   'ana@gmail.com'), 
	(19, 'joão',  'joao@gmail.com');

insert into posts(title, created_at, author_id) values
	('my title 1', '2015-01-01 04:05:06', 10),
	('my title 2', '2015-01-02 04:05:06', 10),
	('my title 3', '2015-01-03 04:05:06', 12),
	('my title 4', '2015-01-04 04:05:06', 12);




select * from users;
select * from posts;


/***

OBJECTIVE:

We want to show a query with 2 columns: the user id and the posts associated with that user; the posts
should be given in an aggregated form using a json array of object; that is, the data for each post will 
be in a json object, and the complete set of posts (for a given user) will given as an array of objects;
if the user doesn't have any posts, an empty array should be returned;

***/


-- 1) basic join; the column with the associated data has only 1 field (the post title)

select 
	u.id as user_id, 
	p.title AS post_title 
from users u 
left join posts p
on u.id = p.author_id


-- 2) similar to the previous, but give all fields for the associated data in an aggregated form (using a subselect)
-- NOTE: we could also have created a composite type and do a type cast

select 
	u.id as user_id,
	(SELECT _dummy_ FROM
		(SELECT p.*) as _dummy_
	) as posts_data
from users u 
left join posts p
on u.id = p.author_id


-- 3) similar to the previous, but give only some fields for the associated data

select 
	u.id as user_id,
	(SELECT _dummy_ FROM
		(SELECT p.title, p.created_at) as _dummy_
	) as posts_data
from users u 
left join posts p
on u.id = p.author_id



-- 4) similar to 2, but give the associated data as a json array of objects

-- Return as array of JSON objects in SQL (Postgres)
-- http://stackoverflow.com/questions/26486784/return-as-array-of-json-objects-in-sql-postgres

select 
	u.id as user_id, 
	json_agg(p.*) as posts_data
from users u 
left join posts p
on u.id = p.author_id
group by u.id




-- 5) similar to example 3, but give the associated data as a json array of objects
-- NOTE: see example 6 for the same query writen in a simpler way

-- taken from: "Return as array of JSON objects in SQL (Postgres)"
-- http://stackoverflow.com/questions/26486784/return-as-array-of-json-objects-in-sql-postgres

select 
	u.id as user_id,
	json_agg(
		(SELECT _dummy_ FROM
			(SELECT p.title, p.created_at) as _dummy_(title, created_at)  -- <- these will be the keys of the object
		) 
	) as posts_data
from users u 
left join posts p
on u.id = p.author_id
group by u.id


-- 6) equal to the previous, but with a simpler query (using json_build_object - available in pg9.4);

select 
	u.id as user_id, 
	json_agg(json_build_object('title', p.title, 'created_at', p.created_at)) as posts_data
from users u 
left join posts p
on u.id = p.author_id
group by u.id



-- 5) equal to example 4, but return a json empty array if the user doesn't have any posts (instead of returning [null])

-- taken from "Postgresql LEFT JOIN json_agg() ignore/remove NULL"
-- http://stackoverflow.com/questions/24155190/postgresql-left-join-json-agg-ignore-remove-null

select u.id as user_id, 
	(CASE 
		WHEN count(p) = 0 THEN '[]'::json 
		ELSE json_agg(p.*) 
	END) as posts_data
from users u 
left join posts p
on u.id = p.author_id
group by u.id


-- 6) equal to example 6, but using the check introduced in 5) (return json empty array in the user doesn't have any posts)

select 
	u.id as user_id, 
	(CASE 
		WHEN count(p) = 0 THEN '[]'::json 
		ELSE json_agg(json_build_object('title', p.title, 'created_at', p.created_at))
	END) as posts_data
from users u 
left join posts p
on u.id = p.author_id
group by u.id








/***

OBJECTIVE

Now we want to make the "inverse" query: show the post id and the data of the associated author of that post;
since we have a 1-to-many association from users to posts (the foreign key is in the posts table, so one post 
is always associated with one user, however one user can be associated with many posts), then the associated data 
for the user should be given as a simple object (instead of an array of objects, as was done above)

***/

-- 1) basic join

select 
	p.id as post_id, 
	u.name AS name
from posts p
left join users u 
on p.author_id = u.id



-- 2) 

select 
	p.id as post_id, 
	(select row_to_json(_dummy_) from (select u.*) as _dummy_) AS author_data
from posts p
left join users u 
on p.author_id = u.id


-- 3)

select 
	p.id as post_id, 
	(select row_to_json(_dummy_) from (select u.name, u.email) as _dummy_) AS author_data
from posts p
left join users u 
on p.author_id = u.id




/*

Other references:


PostgreSQL 9.2 row_to_json() with nested joins
http://stackoverflow.com/questions/13227142/postgresql-9-2-row-to-json-with-nested-joins

Faster JSON Generation with PostgreSQL
http://hashrocket.com/blog/posts/faster-json-generation-with-postgresql

*/

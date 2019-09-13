--
-- directors 
--

create table t_directors(
    id int primary key,
    name text
);

insert into t_directors(id, name) values 
	(1, 'Stanley Kubrick'),
	(2, 'Pedro Almodóvar'),
	(3, 'Martin Scorsese'),
	(4, 'Tim Burton');    -- not present in t_films

--
-- companies
--

create table t_companies(
    id int primary key,
    name text
);

insert into t_companies(id, name) values 
	(11, 'Grove Street Pictures'),
	(12, 'El Deseo'),
	(13, 'Sony Pictures Classics'),  -- not present in t_films
	(14, 'Stanley Kubrick Productions');

--
-- films
--

create table t_films(
    id int primary key,
    director_id int references t_directors(id),
    company_id int references t_companies(id),
    title jsonb default '{}',
    year int
);

insert into t_films(id, director_id, company_id, title, year) values 
	(101, 3, 11, '{ "en-gb": "George Harrison: Living in the Material World" }', 2011), -- not present in t_roles
	(102, 1, 14, '{ "en-gb": "The Shining" }', 1980),
	(103, 1, 14, '{ "en-gb": "2001: A Space Odyssey" }', 1968),
	(104, 2, null, '{ "es-es": "Volver" }', 2005),
	(105, 2, 12, '{ "es-es": "Dolor y gloria" }', 2019);

--
-- actors
--

create table t_actors(
    id int primary key,
    name text  -- name of the actor in real life
);

insert into t_actors(id, name) values 
	(1001, 'Malcolm McDowell'),  -- not present in t_roles
	(1002, 'Jack Nicholson'),
	(1003, 'Shelley Duvall'),
	(1004, 'Keir Dullea'),
	(1005, 'Penélope Cruz'),
	(1006, 'Lola Dueñas'),
	(1007, 'Antonio Banderas');

--
-- roles
--
-- note that there is no constraint in (film_id, actor_id), so that we can
-- handle the cases where the same actor plays 2 different roles (in the
-- same movie)

create table t_roles(
    id serial primary key,
    film_id int references t_films(id),
    actor_id int references t_actors(id),
    name text  -- name of the role
);

insert into t_roles(id, film_id, actor_id, name) values 
	(10001, 102, 1002, 'Jack Torrance'),
	(10002, 102, 1003, 'Wendy Torrance'),
	(10003, 103, 1004, 'Dr. David Bowman'),
	(10004, 104, 1005, 'Raimunda'),
	(10005, 104, 1006, 'Sole'),
	(10006, 105, 1005, 'Jacinta Mallo'),
	(10007, 105, 1007, 'Salvador Mallo'),
	(10008, 105, 1007, 'Salvador Mallo 2 (twin brother)');


/*
1) t_films has a reference to t_directors

http://localhost:3001/t_films?select=id,title,year,director:director_id(id,name)
*/

/*
2) t_films also has a reference to t_companies;

http://localhost:3001/t_films?select=id,title,year,director:director_id(id,name),company:company_id(id,name)

*/

/*
3) same as 1) but since t_roles (link table) has a reference to t_films, we can also ask
"for a given film, the list of associated stuff (in this case, actors and respective role name)"

http://localhost:3001/t_films?select=id,title,year,director:director_id(id,name),roles:t_roles(id,actor_id,name)

*/

/*
4) same as 3) but include nested data in roles (for actors)

http://localhost:3001/t_films?select=id,title,year,director:director_id(id,name),roles:t_roles(id,actor:actor_id(id,name),roleName:name)

*/

/*
5) t_actors doesn't have any forward reference, but t_roles (link table) has a reference
to t_actors, so that we can ask
 "for a given actor, the list of associated stuff (in this case, roles)"

http://localhost:3001/t_actors?select=id,name,roles:t_roles(roleName:name,film_id)
*/


/*
6) same as 5), but include nested data in roles (for films)

http://localhost:3001/t_actors?select=id,name,roles:t_roles(roleName:name,film:film_id(title,year))
*/




/*

other questions to ask, which can be obtain in a indirect manner:

- for a given actor, the list of associated directors 
- for a given director, the list of associated actors 
- for a given director, the list of associated roles
- the list of actors that don't have any associated role
- the list of films that don't have any associated role (from which we can conclude that it might be a documentary)

*/

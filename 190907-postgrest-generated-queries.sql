-- CASE A1) the table (t_users) has a forward relation to other table (t_regions); 
-- that is t_users as a foreign key to t_regions ("one user might have one municipality");
-- we make the subquery using "LEFT JOIN LATERAL (...) ON TRUE", and pass the result to "row_to_json"

-- t_users?&select=id,email,municipality:municipality_id(id,name)

SELECT 
	t_users.id, 
	t_users.email, 
	row_to_json("t_regions_municipality".*) AS municipality 
FROM t_users  

LEFT JOIN LATERAL( 
	SELECT 
		t_regions.id, 
		t_regions.name 
	FROM t_regions  
	WHERE t_regions.id = t_users.municipality_id   
) AS "t_regions_municipality" ON TRUE

ORDER BY t_users.id

-- CASE A2) same as A1, but considering 2 forward relations; in this case, besides municipality_id, 
-- t_user also has a foreign key to itself;
-- we duplicate the "LEFT JOIN LATERAL (...) ON TRUE" subquery

-- /t_users?&select=id,email,municipality:municipality_id(id,name),creator:creator_id(id,email)

SELECT 
	t_users.id, 
	t_users.email, 
	row_to_json("t_regions_municipality".*) AS municipality, 
	row_to_json("t_users_creator".*) AS creator 
FROM t_users  

LEFT JOIN LATERAL( 
	SELECT 
		t_regions.id, 
		t_regions.name 
	FROM t_regions  
	WHERE t_regions.id = t_users.municipality_id   
) AS "t_regions_municipality" ON TRUE 

LEFT JOIN LATERAL( 
	SELECT 
		t_users_1.id, 
		t_users_1.email 
	FROM t_users AS t_users_1  
	WHERE t_users_1.id = t_users.creator_id   
) AS "t_users_creator" ON TRUE

ORDER BY t_users.id


-- CASE A3) same as A1, but considering a nested forward relation; that is, we fetch data for a foreign key
-- present in the table (t_regions) referenced by the original foreign key (municipality_id); 
-- in this case the nested foreign key (parent_nuts3_id) is a reference to itself, that is, 
-- t_regions has a reference to itself

-- we use a nested LEFT JOIN LATERAL + row_to_json

-- /t_users?&select=id,email,municipality:municipality_id(id,name,nuts3:parent_nuts3_id(id,code))



SELECT 
	t_users.id, 
	t_users.email, 
	row_to_json("t_regions_municipality".*) AS municipality 
FROM t_users  

LEFT JOIN LATERAL( 
	SELECT 
		t_regions.id, 
		t_regions.name, 
		row_to_json("t_regions_nuts3".*) AS nuts3 
	FROM t_regions  

	LEFT JOIN LATERAL( 
		SELECT 
			t_regions_2.id, 
			t_regions_2.code 
		FROM t_regions AS t_regions_2  
		WHERE t_regions_2.id = t_regions.parent_nuts3_id   
	) AS "t_regions_nuts3" ON TRUE  
	
	WHERE t_regions.id = t_users.municipality_id   
) AS "t_regions_municipality" ON TRUE

ORDER BY t_users.id


-- CASE B1) the table (t_users) has a 1-to-many relation to other table (t_files);
-- that is, t_files has a foreign key to t_users ("one user might have many files")

-- t_users?&select=id,email,imagesList:t_files(id,seqOrder:seq_order)


-- OLD VERSION (using json_agg inside of a subquery); this is how it's done, as of version 6.0.2

SELECT 
    t_users.id, 
    t_users.email, 
    COALESCE(
        (
            SELECT json_agg(t_files.*) 
            FROM (
                SELECT 
                    t_files.id, 
                    t_files.seq_order AS seqOrder 
                FROM t_files  
                WHERE t_files.user_id = t_users.id  
            ) t_files
        ), 
        '[]'
    ) AS imagesList
FROM t_users

ORDER BY t_users.id



-- NEW VERSION (using LEFT JOIN LATERAL, as done for the forward relation); this will eventually be the new 
-- version; see the references below:
-- https://github.com/PostgREST/postgrest/issues/1075
-- https://gist.github.com/steve-chavez/f79b5c3e777a435d024d44cebb8ac8f4

SELECT 
    t_users.id, 
    t_users.email,
    coalesce(nullif(json_agg("t_files_imagesList")::text, '[null]'), '[]')::json AS imagesList
FROM t_users    

LEFT JOIN LATERAL (
    SELECT 
        t_files.id, 
        t_files.seq_order AS seqOrder 
    FROM t_files  
    WHERE t_files.user_id = t_users.id  
) as "t_files_imagesList" ON TRUE

GROUP BY t_users.email
ORDER BY t_users.id


-- CASE B2) same as before, but as in A3 we consider a nested forward relation; that is, for each file, 
-- also fetch the associated data relative to one of the foreign keys in t_files (in this case we 
-- consider "good_practice_id";

-- we have to focus in the inner query (inside of the first "LEFT JOIN LATERAL"), and reproduce
-- what was done in A1, that is, use a nested LEFT JOIN LATERAL + row_to_json;

SELECT 
    t_users.id, 
    t_users.email,
    coalesce(nullif(json_agg("t_files_imagesList")::text, '[null]'), '[]')::json AS imagesList
FROM t_users    

LEFT JOIN LATERAL (
    SELECT 
        t_files.id, 
        t_files.seq_order AS seqOrder,
        row_to_json("t_good_practices_goodPractice".*) AS goodPractice 
    FROM t_files  

    LEFT JOIN LATERAL (
        SELECT *
        FROM t_good_practices
        WHERE t_good_practices.id = t_files.good_practice_id
    ) AS "t_good_practices_goodPractice" ON TRUE
    WHERE t_files.user_id = t_users.id  
) as "t_files_imagesList" ON TRUE

GROUP BY t_users.email
ORDER BY t_users.id


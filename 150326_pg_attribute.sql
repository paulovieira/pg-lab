-- we can retrieve the complete query as an array of json
create table temp(data json)
insert into temp(data) values('{"a": 1}'), ('{"b": 2}')
SELECT * from temp
SELECT json_agg(temp) FROM temp


-- reference: PostgreSQL return result set as JSON array?
-- http://stackoverflow.com/questions/24006291/postgresql-return-result-set-as-json-array





SELECT a.attname::text as "column name", a.atttypid::regtype::text as "data type"
FROM   pg_attribute a
WHERE  a.attrelid = 'geo.pref'::regclass
AND    a.attnum > 0
AND    NOT a.attisdropped
ORDER  BY a.attnum;




SELECT 
	(SELECT row_to_json(_dummy_) from 
		(select a.attname::text, a.atttypid::regtype::text) as _dummy_("column_name", "data_type")
		) as x

FROM   pg_attribute a
WHERE  a.attrelid = 'geo.pref'::regclass
AND    a.attnum > 0
AND    NOT a.attisdropped
ORDER  BY a.attnum;


--select json_build_array('{"a": 1}'::json, '{"b": 2}'::json)


SELECT json_agg(column_data) as "column_data" FROM
(
SELECT 
	(SELECT row_to_json(_dummy_) from 
		(select a.attname::text, a.atttypid::regtype::text) as _dummy_("column_name", "data_type")
		) as "column_data"

FROM   pg_attribute a
WHERE  a.attrelid = 'geo.pref'::regclass
AND    a.attnum > 0
AND    NOT a.attisdropped
ORDER  BY a.attnum
) as _dummy2_

--select json_build_array('{"a": 1}'::json, '{"b": 2}'::json)



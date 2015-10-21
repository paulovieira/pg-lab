DO $$
DECLARE
	arr JSONB = '["a", "b"]'::jsonb;
	elem1 TEXT;
	elem2 TEXT;
	elem3 TEXT;
	elem4 TEXT;
BEGIN

SELECT arr || '["c"]'::jsonb INTO arr;
SELECT arr - -1 INTO arr;

--SELECT arr || '["d"]'::jsonb INTO arr;

SELECT arr->0 INTO elem1;
SELECT arr->1 INTO elem2;
SELECT arr->2 INTO elem3;
SELECT arr->3 INTO elem4;
RAISE NOTICE '% % % %', elem1, elem2, elem3, elem4;
END
$$


--select '{"a": 1, "b": 2}'::jsonb || '{"a": 3, "d": 4}'::jsonb
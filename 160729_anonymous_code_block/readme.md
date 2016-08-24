## anonymous code block

Main reference: https://www.postgresql.org/docs/9.0/static/sql-do.html

The general structure is very simple:
```sql
DO 
$$

/* the actual code code is here */

$$ 
LANGUAGE lang_name;
```

So for plpgsql the structure would be:
```sql
DO
$$

DECLARE
/* ... */

BEGIN
/* ... */

END;

$$ 
LANGUAGE plpgsql;
```

If the 'lang_name' parameter is ommited, the default will be 'plpgsql'.

"The code block is treated as though it were the body of a normal postgres function with no parameters, returning void. It is parsed and executed a single time."

Example using plpgsql:
```sql
DO 
$$

DECLARE
i int := 0;
message text;

BEGIN

if i > 0 then
    message := 'greater than zero';
else
    message := 'less or equal to zero';
end if;
raise notice 'message: %', message;

END;

$$ 
LANGUAGE plpgsql;
```


Same example in plpython:

```sql
CREATE EXTENSION IF NOT EXISTS plpythonu;

DO 
$$

i = 0
if i > 0:
    message = 'greater than zero';
else:
    message = 'less or equal to zero';

plpy.notice(message);

$$ 
LANGUAGE plpythonu;
```


Anonymous code blocks can be useful in situations where we have to make changes the tables, types, etc and need to catch errors. For instance, to add a new column to a table there is no 'IF NOT EXISTS' for postgres <= 9.5. But we could handle the error easily inside a code block:
```sql
DO 
$$ 
BEGIN
        BEGIN
            alter table <table_name> add column <column_name> <column_type>;
        EXCEPTION
            WHEN duplicate_column THEN 
                RAISE NOTICE 'column <column_name> already exists in <table_name>.';
/*
            WHEN other_condition_name THEN 
                RAISE NOTICE 'message';
*/
        END;
END;
$$
LANGUAGE plpgsql;
```

More details: "Trapping Errors"
https://www.postgresql.org/docs/current/static/plpgsql-control-structures.html#PLPGSQL-ERROR-TRAPPING
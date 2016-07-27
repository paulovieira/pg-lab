## Recurring patterns when using pl/pgsql 

Main reference: https://www.postgresql.org/docs/current/static/plpgsql.html

Consider a prototype table `users`

```sql
create table t_users(
    id serial primary key,
    name text,
    is_admin bool not null,
    updated_at timestamptz default now());

insert into t_users(name, is_admin) values
    ('paulo', true),
    ('ana', false),
    ('joão', false)
```

Instead of using direct queries to interact with the data, everything will be contained in postgres functions written using pl/pgsql.

The basic structure of a pl/pgsql function is
```sql
CREATE OR REPLACE FUNCTION  fn_name(input json)
RETURNS SETOF t_users AS

$BODY$

DECLARE
    
var_1 int;
var_2 text;

-- variables for input data
_input_var_1 text;
_input_var_2 int;

BEGIN

raise notice 'hello world! the time is %', now();

/* the actual function code is here */

END;

$BODY$
LANGUAGE plpgsql;
```



This function would return a set of rows from t_users.
If the function doesn't return anything, replace the line
```sql
RETURNS SETOF t_users AS
```
with 
```sql
RETURNS void AS
```

If we want the function to return some custom recordset, use instead something like this:
```sql
RETURNS TABLE(
    field_1 int,
    field_2 text,
    field_3 boolean
) AS
```

The arguments are always passed as a json data: either a single json object whose properties are assigned to proper variables in the code (usually using `COALESCE` to make sure some default value is used), or an array of objects.

This way, passing data from the web application to the postgres function is a direct step.

We consider diferent cases
- static query vs dynamic query
- input can be only 1 row vs many row (for insert/update/delete functions)


## 1. Get data (select)

## 2. Create data (insert)

The data to be created is passed to the funcion as an array of objects (json format), where each object should have the same fields as the table.

```sql
select * from users_create('[
    { "name": "x", "is_admin": true }, 
    { "name": "y" }
]')
```

### 2.1 - static query, insert 1 row

The input is a single json object

```sql
CREATE OR REPLACE FUNCTION users_create_1(input jsonb)
RETURNS SETOF t_users AS
$BODY$

DECLARE
new_row t_users%rowtype;

BEGIN

new_row := jsonb_populate_record(null::t_users, input);

-- consider default values if necessary
new_row.is_admin := COALESCE(new_row.is_admin, false);

-- reuse the new_row variable to assign the output of the insert query
insert into t_users(name, is_admin)
values (new_row.name, new_row.is_admin)
returning * 
into strict new_row;

return next new_row;
return;

END;
$BODY$
LANGUAGE plpgsql;
```

Execute the function with:
```sql
select * from users_create_1('{ 
    "name": "x", 
    "is_admin": true 
}')
```

Since we are taking into account default values, if the value of some column is missing in the input object, the default value defined in the function will be used:
```sql
select * from users_create_1('{ 
    "name": "x"
}')
```

Note that properties in the input object whose keys are unknown (that is, not the name of a column for the table in question) are simply ignored:
```sql
select * from users_create_1('{ 
    "name": "x",
    "abc": 123
}')
```





### 2.2 - dynamic query, insert 1 row

The input is a single json object. The dynamic query can be constructed with the aid of the `format` function. 
https://www.postgresql.org/docs/current/static/functions-string.html#FUNCTIONS-STRING-FORMAT

`format` accepts the 3 types of specifiers:
- %s: formats the argument value as a simple string. A null value is treated as an empty string.
- %I: treats the argument value as an SQL identifier (tables names, column names, etc), double-quoting it if necessary. It is an error for the value to be null (equivalent to quote_ident).
- %L: quotes the argument value as an SQL literal. A null value is displayed as the string NULL, without quotes (equivalent to quote_nullable).


```sql
CREATE OR REPLACE FUNCTION users_create_2(input jsonb)
RETURNS SETOF t_users AS
$BODY$

DECLARE
new_row t_users%rowtype;
command text;

-- variables for input data
_table_name text;

BEGIN

new_row := jsonb_populate_record(null::t_users, input);
_table_name := input->>'table_name';

-- assign input data, consider default values if necessary
new_row.is_admin := COALESCE(new_row.is_admin, false);

command = format('
    insert into %I(name, is_admin)
    values ($1, $2)
    returning *;
',
_table_name
);

raise notice 'command: %', command;

-- execute the query contained in the command variable;
-- reuse the new_row variable to assign the output of the insert query
execute command
into strict new_row
using new_row.name, new_row.is_admin;

return next new_row;
return;

END;

$BODY$
LANGUAGE plpgsql;
```

Execute the function with:
```sql
select * from users_create_2('{ 
    "table_name": "t_users", 
    "name": "x", 
    "is_admin": true 
}');
```

The main differences are:
1) The dynamic command is constructed using `format` and stored in the 'command' variable (text). 
We should still use the 'returning *' clause in the dynamic command, but not 'into strict new_record'

2) The command is executed with the 'execute' statement. The output result of the command will be assigned to the variable given in the 'into' clause (as before):
```sql
execute command
into strict new_row
using ..., ...;
```

3) The command string can use parameter values passed in the USING clause. These values are referenced in the command as $1, $2, etc. 
This method is often preferable to inserting data values into the command string as plain text (using `format`) because it avoids run-time overhead of converting the values to text and back, and it is much less prone to SQL-injection attacks since there is no need for quoting or escaping. 

### 2.3 static query, insert many rows

This is similar to example 2.1. The argument should now be an array of objects (where each object will be a new record in the table).  

We loop over a recordset which is created automatically with the `json_populate_recordset` function. The esential part of 2.1 is now executed inside this loop.

This function is a generalization of 2.1 because the argument can still be just 1 object (internally it will be converted to a json array with just 1 object).


```sql
CREATE OR REPLACE FUNCTION users_create_3(input jsonb)
RETURNS SETOF t_users AS
$BODY$

DECLARE
new_row t_users%rowtype;

BEGIN

IF  jsonb_typeof(input) = 'object' THEN
    input := jsonb_build_array(input);
END IF;

for new_row in (select * from json_populate_recordset(null::t_users, input)) loop
    -- consider default values if necessary
    new_row.is_admin := COALESCE(new_row.is_admin, false);

    -- reuse the new_row variable to assign the output of the insert query
    insert into t_users(name, is_admin)
    values (new_row.name, new_row.is_admin)
    returning * 
    into strict new_row;

    -- append the record to the output recordset
    return next new_row;
end loop;

return;

END;
$BODY$
LANGUAGE plpgsql;
```

Usage example:
```sql
select * from users_create_3('[
{ 
    "name": "aaa", 
    "is_admin": true 
},
{ 
    "name": "bbb", "xxx": true
}
]')
```

### 2.4 dynamic query, insert many rows

TO BE DONE

## 3. Create or update data (insert ... on conflict)


### 3.1 - static query, create or update 1 row

The code will become more complicated but we will have a function that can handle both inserting new data and updating existing data.

If the input data doesn't have the 'id' property, we assume it is new data to be inserted.

If the input data has the 'id' property, we assume it is existing data that should be updated.

```sql
CREATE OR REPLACE FUNCTION users_upsert_1(input jsonb)
RETURNS SETOF t_users AS
$BODY$

DECLARE
new_row     t_users%rowtype;
current_row t_users%rowtype;
n int;

BEGIN

new_row := jsonb_populate_record(null::t_users, input);

-- if the id was not given in the input, this is a new row
if new_row.id is null then
    new_row.id := nextval(pg_get_serial_sequence('t_users', 'id'));
else
    -- else, this is an existing row; make sure the row actually exists;
    -- see http://www.postgresql.org/docs/9.5/static/plpgsql-statements.html
    SELECT * FROM t_users where id = new_row.id FOR UPDATE INTO current_row;
    GET DIAGNOSTICS n := ROW_COUNT;

    -- if the row does not exist, throw an exception (because if the user 
    -- wants to create a new record, the id can't be given)
    IF n = 0 THEN
        RAISE EXCEPTION USING 
        ERRCODE = 'no_data_found',
        MESSAGE = 'row with id ' || new_row.id ||' does not exist';
    END IF;
end if;

-- consider default values if necessary
new_row.name     := COALESCE(new_row.name,     current_row.name);
new_row.is_admin := COALESCE(new_row.is_admin, current_row.is_admin, false);

-- the rest of the code is similar to 2.1; we just add the on conflict clause;
-- reuse the new_row variable to assign the output of the insert query
insert into t_users(
  id,
  name, 
  is_admin
)
values (
  new_row.id,
  new_row.name, 
  new_row.is_admin
)
-- this part is executed only if the id was given; the fields given in the input object
-- will be used to do the update; if some fields were not given, the current data in
-- those fields will be used (see the usage of coalesce above)
on conflict (id) do update set
  name     = excluded.name,
  is_admin = excluded.is_admin
returning * 
into strict new_row;

return next new_row;
return;

END;
$BODY$
LANGUAGE plpgsql;
```

Execute the function with:
```sql
select * from users_upsert_1('{ 
    "name": "x",
    "is_admin": true
}');

select * from users_upsert_1('{ 
    "id": 1,
    "name": "yyy",
    "is_admin": true
}');

select * from users_upsert_1('{ 
    "id": 1,
    "name": "yyy"
}');
```

Note that if the id is given (which means we are updating existing data) and if some column is missing in the properties of the input object, then the current value of that row will remain untouched.

However if the id is now given (which means we are creating new data) and if some column is missing in the input object, then the default value for that property (as defined in the coalesce function) will be used. If there is no default value, null will be used. 

### 3.2 - dynamic query, create or update 1 row

### 3.3 - static query, create or update many rows

### 3.4 - dynamic query, create or update many rows


## 4. Delete data


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

## 1. Get data (select)

## 2. Create data (insert)

The data to be created is passed to the funcion as an array of objects (json format), where each object should have the same fields as the table.

```sql
select * from users_create('[
    { "name": "x", "is_admin": true }, 
    { "name": "y" }
]')
```

### 2.1 - static query, create 1 row

The input is a single json object

```sql
CREATE OR REPLACE FUNCTION users_create_1(input json)
RETURNS SETOF t_users AS
$BODY$

DECLARE
new_row t_users%rowtype;

-- variables for input data
_name text;
_is_admin bool;

BEGIN

-- assign input data, consider default values if necessary
_name := input->>'name';
_is_admin := COALESCE((input->>'is_admin')::bool, false);

insert into t_users(name, is_admin)
values (_name, _is_admin)
returning * into strict new_row;

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




### 2.2 - dynamic query, create 1 row

The input is a single json object. The dynamic query can be constructed with the `format` function. 
https://www.postgresql.org/docs/current/static/functions-string.html#FUNCTIONS-STRING-FORMAT

It accepts the 3 types of specifiers:
- %s: formats the argument value as a simple string. A null value is treated as an empty string.
- %I: treats the argument value as an SQL identifier (tables names, column names, etc), double-quoting it if necessary. It is an error for the value to be null (equivalent to quote_ident).
- %L: quotes the argument value as an SQL literal. A null value is displayed as the string NULL, without quotes (equivalent to quote_nullable).


```sql
CREATE OR REPLACE FUNCTION users_create_2(input json)
RETURNS SETOF t_users AS
$BODY$

DECLARE
new_row t_users%rowtype;
command text;

-- variables for input data
_table_name text;
_name text;
_is_admin bool;

BEGIN

-- assign input data, consider default values if necessary
_table_name := input->>'table_name';
_name := input->>'name';
_is_admin := COALESCE((input->>'is_admin')::bool, false);

command = format('
insert into %I(name, is_admin)
values ($1, $2)
returning *;
',
_table_name
);

raise notice 'command: %', command;

execute command
into strict new_row
using _name, _is_admin;

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
1) The dynamic command is constructed using `format` and stored in the 'command' variable (text). We should still use the 'returning *' in the dynamic command, but not 'into strict new_record'

2) The command is executed with the 'execute' statement. The output result of the command will be assigned to the variable given in the 'into' clause (as before):
```sql
execute command
into strict new_row
using _name, _is_admin;
```

3) The command string can use parameter values in the USING clause. These values are referenced in the command as $1, $2, etc. This method is often preferable to inserting data values into the command string as text (using `format`) because it avoids run-time overhead of converting the values to text and back, and it is much less prone to SQL-injection attacks since there is no need for quoting or escaping. 


## 3. Create or update data (insert ... on conflict)


### 3.1 - static query, create or update 1 row

The code will become more complicated, but the advantage is that we will have a function that handles both inserting new data and updating existing data.

```sql
CREATE OR REPLACE FUNCTION users_upsert_1(input json)
RETURNS SETOF t_users AS
$BODY$

DECLARE
new_row t_users%rowtype;
current_row t_users%rowtype;
n int;

-- variables for input data
_id int;
_name text;
_is_admin bool;

BEGIN

-- if the id was not given in the input, this is a new row
_id := input->>'id';

if _id is null then
    _id := nextval(pg_get_serial_sequence('t_users', 'id'));
else
    -- else, this is an existing row; make sure the row actually exists;
    -- see http://www.postgresql.org/docs/9.5/static/plpgsql-statements.html
    SELECT * FROM t_users where id = _id FOR UPDATE INTO current_row;
    GET DIAGNOSTICS n := ROW_COUNT;

    -- if the row does not exist, throw an exception (because if the user 
    -- wants to create a new record, the id can't be given)
    IF n = 0 THEN
        RAISE EXCEPTION USING 
        ERRCODE = 'no_data_found',
        MESSAGE = 'row with id ' || _id ||' does not exist';
    END IF;
end if;

-- assign input data, consider default values if necessary
_name     := COALESCE((input->>'name')::text,     current_row.name);
_is_admin := COALESCE((input->>'is_admin')::bool, current_row.is_admin, false);

-- the rest of the code is similar to 2.1; we just add the on conflict clause 
insert into t_users(
  id,
  name, 
  is_admin
)
values (
  _id,
  _name, 
  _is_admin
)
-- this part is used only if the id was given; the fields given in the input object
-- will be used to do the update; if some fields were not given, the current data in
-- those fields will be used (because we used coalesce above)
on conflict (id) do update set
  name = excluded.name,
  is_admin = excluded.is_admin
returning * into strict new_row;

return next new_row;
return;

END;
$BODY$
LANGUAGE plpgsql;
```

Execute the function with:
```sql
select * from users_upsert_1('{ 
    "name": "x"
    "is_admin": true
}');

select * from users_upsert_1('{ 
    "id": 1,
    "name": "yyy",
    "is_admin": true
}');
```
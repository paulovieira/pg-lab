## Recurring patterns when using pl/pgsql 

Main reference: https://www.postgresql.org/docs/current/static/plpgsql.html

Consider a prototype table `users`

```sql
create table t_users(
    id serial,
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

## get

## create data

The data to be created is passed to the funcion as an array of objects (json format), where each object should have the same fields as the table.

```sql
select * from users_create('[
    { "name": "x", "is_admin": true }, 
    { "name": "y" }
]')
```

### Example 1 - static query, create 1 row

The input is a single object

```sql
CREATE OR REPLACE FUNCTION users_create(input json)
RETURNS SETOF t_users AS
$BODY$

DECLARE
rec record;
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
select * from users_create('{ "name": "x", "is_admin": true }')
```





## creating or update

## delete
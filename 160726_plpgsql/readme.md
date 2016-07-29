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

Instead of using direct queries to interact with the data, all queries will be contained in postgres functions written using pl/pgsql. This provides several advantages.

The basic structure of a pl/pgsql function is
```sql
CREATE OR REPLACE FUNCTION  fn_name(input json)
RETURNS SETOF t_users 
AS $$
/* begin of the main block */

/* declarations section (optional) */
DECLARE
    
var_1 int;
var_2 text;

-- variables for input data
_input_var_1 text;
_input_var_2 int;

BEGIN

/* the actual function code is here */
raise notice 'hello world! the time is %', now();



END;
/* end of the main block */
$$
LANGUAGE plpgsql;
```

This function would return a set of rows from t_users.
If the function doesn't return anything, replace the line
```sql
RETURNS SETOF t_users
```
with 
```sql
RETURNS void
```

If we want the function to return some custom recordset, use instead something like this:
```sql
RETURNS TABLE(
    field_1 int,
    field_2 text,
    field_3 boolean
)
```

The arguments are always passed as a json data: either a single json object or an array of objects. Inside the function the properties of the objects are assigned to a record variable using `jsonb_populate_record` (or `jsonb_populate_recordset`).

For some properties it might also make sense to assure that some default value is used case that property is missing in the input object. This can be achieved easily with `COALESCE`.

This way, passing data from the nodejs web application to the postgres function is a direct step. The code should be something simple like

```js
Db.query('select * from my_function($1)', data)
    .then(...)
```

We consider diferent versions of the functions taking into account the following criteria:
- data can be inserted only vs can be inserted or updated (if an id is given)
- static query (hard-coded) vs dynamic query
- input can be only 1 row vs many rows (for upsert/delete functions)


## 1. Get data (select)

## 2. Create data (simple 'insert')

The data to be created is passed to the funcion in json format as a single object or as an array of objects. The objects should have the same fields as the table.

```sql
select * from users_create('{ "name": "x", "is_admin": true }')

select * from users_create('[
    { "name": "x", "is_admin": true }, 
    { "name": "y" }
]')
```

### 2.1 - static query, insert 1 row

- data can be created only
- query is static (hard-coded)
- accepts 1 object only 

The input is a single json object which contains the values for the new record.

```sql
CREATE OR REPLACE FUNCTION users_create_1(input jsonb)
RETURNS SETOF t_users 
AS $$

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
$$
LANGUAGE plpgsql;
```

Example:
```sql
select * from users_create_1('{ 
    "name": "x", 
    "is_admin": true 
}')
```

1) We use `jsonb_populate_record` to convert the input json object into a record. This way we have the values converted to proper postgres data types (typestamptz, double, etc)

2) We use `coalesce` to assign any necessary default values (if they are missing in the input object)

3) The query is execute. We use the 'returning' and 'into' clauses to assign the output to the 'new_row' record (that is, we are reusing the same record - first it was used to stored the input given to the function, now it used to store the output from the query)

4) Finally, the output record is added to the output of the function with 'return next'

Since we are taking into account default values, if the value of some column is missing in the input object, the default value defined in 'coalesce' will be used.

Example:
```sql
select * from users_create_1('{ 
    "name": "x"
}')
```
('is_admin' will be false because that's the default value used in 'coalesce')

Note that properties in the input object whose keys are unknown are simply ignored by `jsonb_populate_record`. That is, if the key is not the name of some column (for the table in question), that property will be ignored.
```sql
select * from users_create_1('{ 
    "name": "x",
    "abc": 123
}')
```
(the property "abc":123 will be ignored in the record created by `jsonb_populate_record`).


### 2.2 static query, insert many rows

- data can be created only
- query is static (hard-coded)
- accepts an array of objects

This is similar to example 2.1, but here the input can be an array of objects (each object will be a new record in the table).  

Instead of creating one record with `jsonb_populate_record` we now create a record set with `jsonb_populate_recordset`. We loop over the record set and copy-paste the code from 2.1 inside the loop.

This function is a generalization of 2.1 because the argument can still be just 1 object (internally it will be converted to a json array with just 1 object).


```sql
CREATE OR REPLACE FUNCTION users_create_2(input jsonb)
RETURNS SETOF t_users 
AS $$

DECLARE
new_row t_users%rowtype;

BEGIN

IF  jsonb_typeof(input) = 'object' THEN
    input := jsonb_build_array(input);
END IF;

for new_row in (select * from jsonb_populate_recordset(null::t_users, input)) loop
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
$$
LANGUAGE plpgsql;
```

Example (inserting 2 records):
```sql
select * from users_create_2('[
{ 
    "name": "aaa", 
    "is_admin": true 
},
{ 
    "name": "bbb", "xxx": true
}
]')
```


### 2.3 - dynamic query, insert 1 row

- data can be created only
- query is dynamic
- accepts 1 object only 

A dynamic query is a query whose text is defined at runtime. 

For instance, suppose we have now many tables with the same definition as t_users: t_users_0001, t_users_0002, etc (like a hand-made partitioning strategy).

In this case the function takes 2 parameters: the first is an object with the data to be inserted, the second is an object with options necessary to construct the dynamic query (namely, "table_name" - the table where the data is to be inserted).

```sql
CREATE OR REPLACE FUNCTION users_create_3(input jsonb, options jsonb)
RETURNS SETOF t_users 
AS $$

DECLARE
new_row t_users%rowtype;
command text;

BEGIN

new_row := jsonb_populate_record(null::t_users, input);

-- assign input data, consider default values if necessary
new_row.is_admin := COALESCE(new_row.is_admin, false);

command := format('
    insert into %I(name, is_admin)
    values ($1, $2)
    returning *;
', options->>'table_name');
-- raise notice 'command: %', command;

-- execute the query contained in the command variable;
-- reuse the new_row variable to assign the output of the insert query
execute command
    into strict new_row
    using 
        new_row.name, 
        new_row.is_admin;

return next new_row;
return;

END;

$$
LANGUAGE plpgsql;
```

Example:
```sql
select * from users_create_3('
{ 
    "name": "x 0001", 
    "is_admin": true 
}'
,
'{ "table_name": "t_users_0001" }'
);

select * from users_create_3('
{ 
    "name": "x 0002", 
    "is_admin": true 
}'
,
'{ "table_name": "t_users_0002" }'
);
```

The dynamic query can be constructed with the aid of the `format` function. 
https://www.postgresql.org/docs/current/static/functions-string.html#FUNCTIONS-STRING-FORMAT

`format` accepts the 3 types of specifiers:
- %s: formats the argument value as a simple string. A null value is treated as an empty string.
- %I: treats the argument value as an SQL identifier (tables names, column names, etc), double-quoting it if necessary. It is an error for the value to be null (equivalent to quote_ident).
- %L: quotes the argument value as an SQL literal. A null value is displayed as the string NULL, without quotes (equivalent to quote_nullable).

The main differences in relation to 2.1 are:

1) The dynamic command is constructed using `format` and stored in the 'command' variable (text). 
We should still use the 'returning *' clause in the dynamic command to return the output of the query, but not 'into strict new_record'

2) The command is executed with the 'execute' statement. The output of the query will be assigned to the record variable given in the 'into' clause (as before):
```sql
execute command
into strict new_row
using ..., ...;
```

3) When executing the dynamic command we can pass parameter values in the 'USING' clause. These values are referenced in the command as $1, $2, etc. 
This method is often preferable to inserting data values directly into the dynamic command string (as plain text, using either `format` or direct concatenation):
- it avoids the run-time overhead of converting the values to text and back, 
- it is much less prone to SQL-injection attacks since there is no need for quoting or escaping. 


### 2.4 dynamic query, insert many rows

- data can be created only
- query is dynamic
- accepts an array of objects

Similar to 2.3, but the input can be an array of objects (as in 2.2).

The evolution from 2.3 to 2.4 is similar to the one from 2.1 to 2.2: we loop over the record set and copy-paste the code from 2.3 inside the loop.

This is the more general version of all functions in section 2.

```sql
CREATE OR REPLACE FUNCTION users_create_4(input jsonb, options jsonb)
RETURNS SETOF t_users 
AS $$

DECLARE
new_row t_users%rowtype;
command text;

BEGIN

IF  jsonb_typeof(input) = 'object' THEN
    input := jsonb_build_array(input);
END IF;

for new_row in (select * from jsonb_populate_recordset(null::t_users, input)) loop

    -- assign input data, consider default values if necessary
    new_row.is_admin := COALESCE(new_row.is_admin, false);

    command := format('
        insert into %I(name, is_admin)
        values ($1, $2)
        returning *;
    ', options->>'table_name');

     --raise notice 'command: %', command;

    -- execute the query contained in the command variable;
    -- reuse the new_row variable to assign the output of the insert query
    execute command
        into strict new_row
        using 
            new_row.name, 
            new_row.is_admin;

    return next new_row;

end loop;

return;

END;

$$
LANGUAGE plpgsql;
```

Example:

```sql
select * from users_create_4('[
{ 
    "name": "x 0001", 
    "is_admin": true 
},
{ 
    "name": "x 0002", 
    "is_admin": true 
}
]'
, 
'{ "table_name": "t_users_0001" }'
);

select * from users_create_4('
{ 
    "name": "x 0002", 
    "is_admin": true 
}'
, 
'{ "table_name": "t_users_0002" }'
);

```

## 3. Create or update data ('insert ... on conflict do')

The code will become a bit more complicated but we will have a function that can handle both inserting new data and updating existing data. So these functions are a generalization of the respective functions in section 2 and they should bethe first choice (unless we are sure the data is never going to be updated).

- if the input object doesn't have the 'id' property, we assume it is new data to be inserted (behaves like the functions in section 2)
- if the input object has the 'id' property, we assume it is existing data that should be updated.

So we don't allow the user to create a new record and give an explicit id at the same time (the user could call 'nextval' on the sequence). In other words: if the user wants to create a new record, the id can't be given.

If the input object has the 'id' property but that record doesn't exist (it might have been deleted meanwhile), an error is thrown.

### 3.1 - static query, create or update 1 row

This is general case for 2.1:
- data can be created OR updated
- query is static
- accepts 1 object only 


```sql
CREATE OR REPLACE FUNCTION users_upsert_1(input jsonb)
RETURNS SETOF t_users 
AS $$

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

    -- if the row does not exist, throw an exception (the row might have
    -- been deleted before this function is executed)
    IF n = 0 THEN
        PERFORM raise_exception_no_data_found('t_users', new_row.id::text);
    END IF;
end if;

-- consider default values; we now have to do this for all columns
-- to handle the case where data is to be updated
new_row.name     := COALESCE(new_row.name,     current_row.name);
new_row.is_admin := COALESCE(new_row.is_admin, current_row.is_admin, false);

-- the rest of the code is similar to 2.1; we just add the on conflict clause;
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
/*  
this part is executed only if the id was given and corresponds to an 
existing record; if some fields were not given in the input object, the
current data for those fields will be used (see the usage of coalesce) 
*/

on conflict (id) do update set
  name     = excluded.name,
  is_admin = excluded.is_admin

returning * 
into strict new_row;

return next new_row;
return;

END;
$$
LANGUAGE plpgsql;

-- auxiliary function used to throw an exception when the row doesn't exist
CREATE OR REPLACE FUNCTION  raise_exception_no_data_found(table_name text, pk_value text)
RETURNS void 
AS $$

BEGIN

RAISE EXCEPTION USING 
    ERRCODE = 'no_data_found',
    MESSAGE = format('row with id %s does not exist in table %s', pk_value, table_name),
    TABLE = table_name;
END;

$$
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

Some notes about missing properties in the input object:

If the id is given (which means we are updating existing data) and if some column is missing in the properties of the input object (for instance, "name"), then the current value of that row will remain untouched (because in `coalesce` we use 'current_row.column_name' as the 2nd argument).

However if the id is not given (which means we are creating new data) and if some column is missing in the input object, then the default value for that property will be used (as defined in the 3rd argument to `coalesce`). If there is no default value, null will be used. If the table has default values in its definition, they are not applied because we explicitely listing all the columns in 'insert'. This means we might have to use explicitely 3 arguments to `coalesce` (the 3rd being the default value from the table definition).

### 3.2 - static query, create or update many rows

This is the general case for 2.2. 
- data can be created OR updated
- query is static
- accepts an array of objects
 
The input object can be an array of objects of data to be created or updated. The presence of ids can be mixed (some objects might be data to be created, others might be data to be updated).

The code is the same as 3.1. We just do a copy-paste inside the loop.

This is also a generalization of 3.1 because the argument can still be just 1 object.

```sql
CREATE OR REPLACE FUNCTION users_upsert_2(input jsonb)
RETURNS SETOF t_users 
AS $$

DECLARE
new_row     t_users%rowtype;
current_row t_users%rowtype;
n int;

BEGIN

IF  jsonb_typeof(input) = 'object' THEN
    input := jsonb_build_array(input);
END IF;

for new_row in (select * from jsonb_populate_recordset(null::t_users, input)) loop

    -- if the id was not given in the input, this is a new row
    if new_row.id is null then
        new_row.id := nextval(pg_get_serial_sequence('t_users', 'id'));
    else
        -- else, this is an existing row; make sure the row actually exists;
        -- see http://www.postgresql.org/docs/9.5/static/plpgsql-statements.html
        SELECT * FROM t_users where id = new_row.id FOR UPDATE INTO current_row;
        GET DIAGNOSTICS n := ROW_COUNT;

        -- if the row does not exist, throw an exception (the row might have
        -- been deleted before this function is executed)
        IF n = 0 THEN
            PERFORM raise_exception_no_data_found('t_users', new_row.id::text);
        END IF;
    end if;

    -- consider default values; we now have to do this for all columns
    -- to handle the case where data is to be updated
    new_row.name     := COALESCE(new_row.name,     current_row.name);
    new_row.is_admin := COALESCE(new_row.is_admin, current_row.is_admin, false);

    -- the rest of the code is similar to 2.1; we just add the on conflict clause;
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
    /*  
    this part is executed only if the id was given and corresponds to an 
    existing record; if some fields were not given in the input object, the
    current data for those fields will be used (see the usage of coalesce) 
    */

    on conflict (id) do update set
      name     = excluded.name,
      is_admin = excluded.is_admin

    returning * 
    into strict new_row;

    return next new_row;

end loop;

return;

END;
$$
LANGUAGE plpgsql;
```

Example:
```sql
select * from users_upsert_2('[
{ 
    "name": "aaa edit2", 
    "is_admin": true ,
    "id": 61
},
{ 
    "name": "ccc edit", 
    "xxx": true
}
]');
-- the "xxx" property will be ignored
```

NOTE: the whole execution of the function is done as a transaction: if we give many records in the input and one of them has an invalid id (a row that has been deleted meanwhile), the error will be thrown and the whole operation will be reverted (even though each 'insert' is done done separately for each input object).

### 3.3 - dynamic query, create or update 1 row

This is a general case of 2.3.
- data can be created OR updated
- query is dynamic
- accepts 1 object only

```sql
CREATE OR REPLACE FUNCTION users_upsert_3(input jsonb, options jsonb)
RETURNS SETOF t_users 
AS $$

DECLARE
new_row     t_users%rowtype;
current_row t_users%rowtype;
command text;
n int;

BEGIN

new_row := jsonb_populate_record(null::t_users, input);

-- if the id was not given in the input, this is a new row; we have to 
-- pass table_name to get the sequence of the correct table
if new_row.id is null then
    new_row.id := nextval(pg_get_serial_sequence(options->>'table_name', 'id'));
else
    -- else, this is an existing row; make sure the row actually exists;
    -- see http://www.postgresql.org/docs/9.5/static/plpgsql-statements.html
    command := format('SELECT * FROM %I where id = $1 FOR UPDATE;', options->>'table_name');
    --raise notice 'command: %', command;

    EXECUTE command
        INTO current_row
        USING new_row.id;

    GET DIAGNOSTICS n := ROW_COUNT;

    -- if the row does not exist, throw an exception (it was deleted meanwhile)
    IF n = 0 THEN
        PERFORM raise_exception_no_data_found(options->>'table_name', new_row.id::text);
    END IF;
end if;

-- consider default values; we now have to do this for all columns
-- to handle the case where data is to be updated
new_row.name     := COALESCE(new_row.name,     current_row.name);
new_row.is_admin := COALESCE(new_row.is_admin, current_row.is_admin, false);

-- the rest of the code is similar to 2.2; we just add the on conflict clause;
command := format('
    insert into %I(id, name, is_admin)
    values ($1, $2, $3)
    on conflict (id) do update set
        name     = excluded.name,
        is_admin = excluded.is_admin
    returning *; 
',
options->>'table_name'
);

raise notice 'command: %', command;

execute command
into strict new_row
using 
    new_row.id,
    new_row.name, 
    new_row.is_admin;

return next new_row;
return;

END;
$$
LANGUAGE plpgsql;

-- auxiliary function used to throw an exception when the row doesn't exist
CREATE OR REPLACE FUNCTION  raise_exception_no_data_found(table_name text, pk_value text)
-- (same as defined in 2.3)
LANGUAGE plpgsql;
```

Example:

```sql
select * from users_upsert_3('
{ 
    "name": "xxxx 0001", 
    "is_admin": true,
    "id": 51
}'
,
'{ "table_name": "t_users_0001" }'
);

select * from users_upsert_3('
{ 
    "name": "x 0002", 
    "is_admin": false
}'
,
'{ "table_name": "t_users_0002" }'
);
```

### 3.4 - dynamic query, create or update many rows

This is a general case of 2.4:
- data can be created OR updated
- query is dynamic
- accepts an array of objects

This is the most general version of all the functions in sections 2 and 3.

```sql
CREATE OR REPLACE FUNCTION users_upsert_4(input jsonb, options jsonb)
RETURNS SETOF t_users 
AS $$

DECLARE
new_row     t_users%rowtype;
current_row t_users%rowtype;
command text;
n int;

BEGIN

IF  jsonb_typeof(input) = 'object' THEN
    input := jsonb_build_array(input);
END IF;

for new_row in (select * from jsonb_populate_recordset(null::t_users, input)) loop

    -- if the id was not given in the input, this is a new row; we have to 
    -- pass table_name to get the sequence of the correct table
    if new_row.id is null then
        new_row.id := nextval(pg_get_serial_sequence(options->>'table_name', 'id'));
    else
        -- else, this is an existing row; make sure the row actually exists;
        -- see http://www.postgresql.org/docs/9.5/static/plpgsql-statements.html
        command := format('SELECT * FROM %I where id = $1 FOR UPDATE;', options->>'table_name');
        --raise notice 'command: %', command;

        EXECUTE command
            INTO current_row
            USING new_row.id;

        GET DIAGNOSTICS n := ROW_COUNT;

        -- if the row does not exist, throw an exception (it was deleted meanwhile)
        IF n = 0 THEN
            PERFORM raise_exception_no_data_found(options->>'table_name', new_row.id::text);
        END IF;
    end if;

    -- consider default values; we now have to do this for all columns
    -- to handle the case where data is to be updated
    new_row.name     := COALESCE(new_row.name,     current_row.name);
    new_row.is_admin := COALESCE(new_row.is_admin, current_row.is_admin, false);

    -- the rest of the code is similar to 2.2; we just add the on conflict clause;
    command := format('
        insert into %I(id, name, is_admin)
        values ($1, $2, $3)
        on conflict (id) do update set
            name     = excluded.name,
            is_admin = excluded.is_admin
        returning *; 
    ',
    options->>'table_name'
    );

    raise notice 'command: %', command;

    execute command
    into strict new_row
    using 
        new_row.id,
        new_row.name, 
        new_row.is_admin;

    return next new_row;

end loop;
return;

END;
$$
LANGUAGE plpgsql;
```

```sql
select * from users_upsert_4('[
{ 
    "name": "x 0002w", 
    "is_admin": false
},
{ 
    "name": "x 0002u", 
    "is_admin": true
}
]'
,
'{ "table_name": "t_users_0002" }'
);
```


## 4. Delete data


### 4.1 - static query, delete 1 row

- query is static (hard-coded)
- accepts 1 object only 

Similar to 2.1. The input is a single json object which contains the id of the record to be deleted.

```sql
CREATE OR REPLACE FUNCTION users_delete_1(input jsonb)
RETURNS SETOF t_users 
AS $$

DECLARE
row_to_delete t_users%rowtype;

BEGIN

row_to_delete := jsonb_populate_record(null::t_users, input);

delete from t_users
where id = row_to_delete.id
returning * 
into strict row_to_delete;

return next row_to_delete;
return;

END;
$$
LANGUAGE plpgsql;
```

Example:
```sql
select * from users_delete_1('{ "id": 64 }')
```

### 4.2 - static query, delete many row

- query is static (hard-coded)
- accepts an array of objects

Similar to 2.2. The input can be an array of objects where each object contains the id of the record to be deleted.

```sql
CREATE OR REPLACE FUNCTION users_delete_2(input jsonb)
RETURNS SETOF t_users 
AS $$

DECLARE
row_to_delete t_users%rowtype;

BEGIN

IF  jsonb_typeof(input) = 'object' THEN
    input := jsonb_build_array(input);
END IF;

for row_to_delete in (select * from jsonb_populate_recordset(null::t_users, input)) loop

    delete from t_users
    where id = row_to_delete.id
    returning * 
    into strict row_to_delete;

    -- append the record to the output recordset
    return next row_to_delete;
    
end loop;

return;

END;
$$
LANGUAGE plpgsql;
```

Example:
```sql
select * from users_delete_2('{ "id": 64 }')
select * from users_delete_2('[{ "id": 63 }, { "id": 64 }]')
```

NOTE: the whole execution of the function is done as a transaction: if we give many records in the input and one of them has an invalid id (a row that has been deleted meanwhile), an error will be thrown (because we are using 'into strict') and the whole operation will be reverted (even though each 'delete' is done done separately for each input object).

### 4.3 - dynamic query, delete one row

- query is dynamic
- accepts 1 object only 
 
Similar to 2.3.

```sql
CREATE OR REPLACE FUNCTION users_delete_3(input jsonb, options jsonb)
RETURNS SETOF t_users 
AS $$

DECLARE
row_to_delete t_users%rowtype;
command text;

BEGIN

row_to_delete := jsonb_populate_record(null::t_users, input);

command := format('
    delete from %I
    where id = $1
    returning * ;
', options->>'table_name');

-- raise notice 'command: %', command;

execute command
    into strict row_to_delete
    using row_to_delete.id;

return next row_to_delete;
return;

END;

$$
LANGUAGE plpgsql;
```

Example:
```sql
select * from users_delete_3('
{ "id": 3 }'
, 
'{"table_name": "t_users_0001" }'
)
```

### 4.4 - dynamic query, delete many row

- query is dynamic
- accepts an array of objects

```sql
CREATE OR REPLACE FUNCTION users_delete_4(input jsonb, options jsonb)
RETURNS SETOF t_users 
AS $$

DECLARE
row_to_delete t_users%rowtype;
command text;

BEGIN

IF  jsonb_typeof(input) = 'object' THEN
    input := jsonb_build_array(input);
END IF;

for row_to_delete in (select * from jsonb_populate_recordset(null::t_users, input)) loop

    command := format('
        delete from %I
        where id = $1
        returning * ;
    ', options->>'table_name');

    -- raise notice 'command: %', command;

    execute command
        into strict row_to_delete
        using row_to_delete.id;

    return next row_to_delete;

end loop;
return;

END;

$$
LANGUAGE plpgsql;
```

Example:

```sql
select * from users_delete_4('
{ "id": 5 }'
, 
'{"table_name": "t_users_0001" }'
)

select * from users_delete_4('[
{ "id": 4 }, 
{ "id": 7 }
]'
, 
'{"table_name": "t_users_0001" }'
)
```



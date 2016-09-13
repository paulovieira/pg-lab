## enum vs reference table vs domains

Suppose we have a column "states" that will store a well known text (from a limited set of valid possibilities). The valid values are these: "system", "connectivity", "gpio".and "cloud".

With time it is natural that we need to change the valid values (add, change or remove).

### 1 - Using enums

Create the enum and add some values:
```sql
create type state as enum ('system', 'connectivity', 'gpio', 'cloud');

create table t_log_states(
    state_id state, 
    data jsonb
);

insert into t_log_states values('gpio', '{ "foo": 123 }');
insert into t_log_states values('system', '{ "bar": 456 }');

insert into t_log_states values('xyz', '{ "bar": 789 }');
-- ERROR:  invalid input value for enum state: "xyz"
```

Add a new valid state to the enum. This will add to the end of the list, but we can specify the position.
```sql
alter type state add value if not exists 'xyz';

insert into t_log_states values('xyz', '{}');
```

To change one of the current valid states we have to use the 'pg_enum' system table directly:
```sql
DO 
$$ 
DECLARE
    new_state text := 'xyz2';
    old_state text := 'xyz';
    output text;
BEGIN
        UPDATE pg_catalog.pg_enum
            SET enumlabel = new_state
            WHERE enumlabel = old_state AND enumtypid = 'public.state'::regtype::oid
            RETURNING enumlabel INTO output;
        
        IF output IS NULL THEN
            raise notice 'state % does not exist in the "state" enum, skipping', old_state;
        END IF;
END;
$$
```

NOTE: about editing enum values:
"If you need to modify the values used or want to know what the integer is, use a lookup table instead. Enums are the wrong abstraction for you."
https://www.postgresql.org/message-id/44E296D8.2060505@tomd.cc

Check that the label has been changed in the system tables:
```sql
select * from pg_catalog.pg_enum
where enumtypid = 'public.state'::regtype::oid
```
or
```sql
select enum_range(null::state)
```

Check that the state value is updated in the table and that we can't use the old state anymore:
```sql
select * from t_log_states;

insert into t_log_states values('xyz', '{}');
-- ERROR:  invalid input value for enum state: "xyz"
```

As for deleting a state: this doesn't make much sense because if the data in this table requires a state (by nature), if that state doesn't exist anymore then the data associated with the state should be deleted as well. 

If the data must be maintained for historical reasons, we might also rename to state to something like 'DEPRECATED_xyz'.(or simply 'DEPRECATED').


### 2 - Using a separate reference table

Instead of creating an enum 'state', we might as well use a separate reference table 'state' with a primary key 'state_id text'. 

In the main table 't_log_states2', instead of the enum we now use a text field with a foreign key to state(state_id) (which is now a reference table, not an enum).

Create the reference table and add some values:
```sql
create table state(id text primary key);
insert into state(id) values ('system'), ('connectivity'), ('gpio'), ('cloud');

create table t_log_states2(
    state_id text references state(id) on update cascade, 
    data jsonb
);

-- inserting values works the same way as with the enum
insert into t_log_states2 values('gpio', '{ "foo": 123 }');
insert into t_log_states2 values('system', '{ "bar": 456 }');

insert into t_log_states2 values('xyz', '{ "bar": 789 }');
-- ERROR:  insert or update on table "t_log_states2" violates foreign key constraint "t_log_states2_state_id_fkey"
```

To add a new valid state we simply add a new row to the reference table. 
If the management of states is to be done by the end users, this will greatly simplify the process. For instance, it's easy to update the ordering of the states (with a 2nd auxiliary column in the reference table)
```sql
DO 
$$ 
BEGIN
    insert into state(id) values('xyz');
    exception
        when unique_violation then
    raise notice 'value xyz already exists in state, skipping';

END;
$$

insert into t_log_states2 values('xyz', '{}');
```

To change one of the current valid states we simply update the state directly in the reference table:
```sql
DO 
$$ 
DECLARE
    new_state text := 'xyz2';
    old_state text := 'xyz';
    output text;
BEGIN
    update state 
    set id = new_state where id = old_state
    returning id INTO output;

    IF output IS NULL THEN
        raise notice 'state % does not exist in "state" reference table, skipping', old_state;
    END IF;
END;
$$
```

Check that the state value is updated in the table and that we can't use the old state anymore:
```sql
select * from t_log_states2;

insert into t_log_states2 values('xyz', '{}');
-- ERROR:  insert or update on table "t_log_states2" violates foreign key constraint "t_log_states2_state_id_fkey"
```

One advantage of this more traditional approach is that later we can add columns to the reference table. Example: an smallint column to control the ordering of the states, or a jsonb column with the designation of the state in different languages.



### 3 - Using domains

```sql
create domain state as text
constraint valid_states check (
    value in ('system', 'connectivity', 'gpio', 'cloud')
);

create table t_log_states3(
    state_id state, 
    data jsonb
);

-- inserting values works the same way as with the enum
insert into t_log_states3 values('gpio', '{ "foo": 123 }');
insert into t_log_states3 values('system', '{ "bar": 456 }');

insert into t_log_states3 values('xyz', '{ "bar": 789 }');
-- ERROR:  value for domain state violates check constraint "valid_states"
```

To add a new valid state to the domain we simply replace the current constraint with a new one:
```sql
DO 
$$ 
BEGIN
    -- table should be locked for writing
    alter domain state
    drop constraint if exists valid_states;

    alter domain state
    add constraint valid_states check (
        value in ('system', 'connectivity', 'gpio', 'cloud', 'xyz')
    );
END;
$$

insert into t_log_states3 values('xyz', '{}');
```

To change one of the current valid states we do the same. But we also have to rewrite all the entries for the state that is being changed:
```sql
DO 
$$ 
DECLARE
    new_state text := 'xyz2';
    old_state text := 'xyz';
    output text;
BEGIN
    -- table should be locked for writing
    alter domain state
    drop constraint valid_states;

    update t_log_states3 set state_id = new_state where state_id = old_state;

    alter domain state
    add constraint valid_states check (
        value in ('system', 'connectivity', 'gpio', 'cloud', 'xyz2')
    );
END;
$$
```


Check that the state value is updated in the table and that we can't use the old state anymore:
```sql
select * from t_log_states3;

insert into t_log_states3 values('xyz', '{}');
-- ERROR:  value for domain state violates check constraint "valid_states"
```


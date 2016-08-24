main idea: instead of creating an enum 'states', might as well use a separate table 't_states' with a primary key 'state_id text'. 

In the table 't_log_state' where the enum was going to be used, use instead a text field with  a foreign key for t_states 

state text references t_states(state_id)

In pratical terms nothing changes
```sql
-- with enum
insert into t_log_state(state, data) values('gpio', '{ "value": 0 }')
```


```sql
-- with reference table
insert into t_log_state(state, data) values('gpio', '{ "value": 0 }')
```















-- 1 using enums
create type state as enum 
('gpio', 'online', 'cloud_available');

create table t_log_state(state_id state, data jsonb);
insert into t_log_state values('gpio', '{}')

-- 1.1 add a new state to the enum
alter type state add value if not exists 'xyz';
insert into t_log_state values('xyz', '{}')

-- 1.2 change designation of a current state
DO 
$$ 
DECLARE
    new_enumlabel text := 'xyz2';
    old_enumlabel text := 'xyz';
    output text;
BEGIN
        BEGIN
        UPDATE pg_catalog.pg_enum
            SET enumlabel = new_enumlabel
            WHERE enumlabel = old_enumlabel AND enumtypid = 'public.state'::regtype::oid
            RETURNING enumlabel INTO output;
        
        IF output IS NULL THEN
            raise notice 'enumlabel % does not exist in enum state, skipping', old_enumlabel;
        END IF;
        END;
END;
$$

NOTE: about editing enum values:
"If you need to modify
the values used or want to know what the integer is, use a lookup table
instead. Enums are the wrong abstraction for you."
https://www.postgresql.org/message-id/44E296D8.2060505@tomd.cc


-- check that the label has been changed
select enum_range(null::state)

-- check that the label has been changed
select * from t_log_state;




-- 2 using reference table
create table t_state(id text primary key);
insert into t_state(id) values('gpio'),('online'),('cloud_available');


create table t_log_state2(
    state_id text references t_state on update cascade, 
    data jsonb);

insert into t_log_state2 values('gpio', '{}')

-- 2.1 add a new state to the reference table
DO 
$$ 
BEGIN
        BEGIN
            insert into t_state(id) values('xyz');
        EXCEPTION
            when unique_violation then
        raise notice 'value xyz already exists in t_state, skipping';
        END;
END;
$$

insert into t_log_state2 values('xyzw', '{}');

-- 2.2 change designation of a current state
select * from t_log_state2;
update t_state set id = 'xyz2' where id = 'xyz';
select * from t_log_state2;




todo: create domain jsonb_obj

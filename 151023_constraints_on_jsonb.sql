/*
We can use a jsonb column and make sure the data conforms to a given structure (that is, we can assure that a given key or nested key is defined). Here we simply check that the keys are defined. We could also make sure the respective values are int or string.
*/

drop table if exists temp;

create table temp(
  id serial primary key, 
  data jsonb NOT NULL,

  -- validation constrainst for the json data (a bit like specifying the kind of data that goes here)
  CONSTRAINT json_must_be_object     CHECK (jsonb_typeof(data) = 'object'),
  CONSTRAINT key_x_must_be_defined   CHECK (data#>>'{x}' IS NOT NULL),
  CONSTRAINT key_a_b_must_be_defined CHECK (data#>>'{a,b}' IS NOT NULL)
 );

-- these inserts will fail because of the constraints
insert into temp values(default);
insert into temp values(default, '[]'::jsonb);
insert into temp values(default, '{}'::jsonb);
insert into temp values(default, '{"x": "xyz"}'::jsonb);
insert into temp values(default, '{"x": "xyz", "a": {"b": null}}'::jsonb);

insert into temp values(default, '{"x": "xyz", "a": {"b": 123}}'::jsonb);
insert into temp values(default, '{"x": "xyz", "a": {"b": 456}, "z": 111}'::jsonb);
insert into temp values(default, '{"x": "xyz", "a": {"b": 456}, "z": null}'::jsonb);
insert into temp values(default, '{"x": "xyz", "a": {"b": 789, "c": "abc"}, "z": 222}'::jsonb)

select * from temp
update temp set data='{"x": 123, "a": {"b": 456}}'::jsonb where id = ...


-- add a constraint at a later time for the top-level field z (we didn't say anything about it)

-- it's not possible because:  ERROR:  check constraint "key_z_must_be_defined" is violated by some row
ALTER TABLE temp ADD CONSTRAINT key_z_must_be_defined CHECK (data#>>'{z}' IS NOT NULL);

-- update all rows: make sure z has a default not null value (but only if it isn't defined already)
select * from temp;
DO $$
DECLARE
  r temp%rowtype;
  temp_data jsonb;
BEGIN
  FOR r IN select * from temp
  LOOP

    select r.data#>>'{z}' into temp_data;
    if temp_data IS NULL then
      -- default value is 0
      select jsonb_set(r.data, '{z}', '0') into r.data;
      update temp set data = r.data where id = r.id;
    end if;

  END LOOP;
END
$$

-- now we can add the constraint above
ALTER TABLE temp ADD CONSTRAINT key_z_must_be_defined CHECK (data#>>'{z}' IS NOT NULL);

-- and this can't be done anymore
insert into temp values(default, '{"x": "xyz", "a": {"b": 123}}'::jsonb)

insert into temp values(default, '{"x": "xyz", "a": {"b": 456}, "z": 333}'::jsonb);

-- TODO: add a constraint at a later time for nested keys 


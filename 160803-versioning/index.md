template for changes with pg-versioning


```sql
DO $$

DECLARE
patch_is_registered int := _v.register_patch('160803-11');

BEGIN

if patch_is_registered then
    return;
end if;

/* the actual code to change to the database goes here */

END;
$$ 
```


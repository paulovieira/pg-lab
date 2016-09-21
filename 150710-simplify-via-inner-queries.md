The queries in the `*_read*` functions can be made much simpler by using `json_agg` and a subquery (inner query) in the SELECT clause. 

Currently we are defining CTE and using INNER/LEFT JOIN in the main SELECT. The CTE itself is also using LEFT JOIN, so the code is a little hard to read. The subquery will eliminate one of th joins.

### Example 1

Original query:

```sql
WITH users_texts_cte AS (
    SELECT
        u.id AS user_id,
        json_agg(t.*) AS user_texts
    FROM users u
    LEFT JOIN texts t
        ON t.author_id = u.id
    GROUP BY u.id
)
SELECT 
    u.*, 
    ut.user_texts
FROM users u
INNER JOIN users_texts_cte ut
    ON u.id = ut.user_id
```


New query (equivalent)

```sql
SELECT
    u.* ,
    (SELECT json_agg(t.*) FROM (
        SELECT t.*
        FROM texts t
        WHERE t.author_id = u.id  -- u.id is outside
        ORDER BY t.id DESC
    ) t) AS ut
FROM
    users u
```

NOTE: in both cases we should take into account NULL values by substituting
```sql
json_agg(t.*)
```
by
```sql
CASE WHEN COUNT(t) = 0 THEN '[]'::json  ELSE json_agg(t.*) END
```
This will give an empty json array instead of null values

Some advantages of the new version:

  - it's much easier to manipulate the data in the subquery; for instance, we can apply ORDER BY (which can't be done in the original version).

### Example 2

This  example involves the link table `users_groups` (many-to-many relation).

Original query

```sql
WITH groups_users_cte AS (
    SELECT
        g.id as group_id,
        g.code as group_code,
        json_agg(u.*) AS group_users
    FROM groups g
    LEFT JOIN users_groups ug
        ON ug.group_code = g.code
    LEFT JOIN users u
        ON u.id = ug.user_id
    GROUP BY g.id
) 
SELECT 
    g.*, 
    gu.group_users
FROM groups g
INNER JOIN groups_users_cte gu
    ON g.id = gu.group_id
```


New query (almost half loc)

```sql
select 
    g.*,
    (SELECT json_agg(u.*) FROM (
        select u.*
        from users u
        left join users_groups ug
        on u.id = ug.user_id
        where ug.group_code = g.code  -- g.code is outside
    ) u) AS xyz
from 
    groups g
```


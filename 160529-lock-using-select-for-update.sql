-- prepare example

DROP TABLE IF EXISTS test_lock;
CREATE TABLE test_lock(id INT UNIQUE, value TEXT);
INSERT INTO test_lock VALUES(1, 'hello');
INSERT INTO test_lock VALUES(2, 'hello');


-- run in client 1

BEGIN;

    SELECT * FROM test_lock where id = 1 FOR UPDATE;
    
    SELECT pg_sleep(10);
    
    UPDATE test_lock
    SET value = 'hello from client a @ ' || now()
    WHERE id = 2;

COMMIT;


-- run in client 2 (copy paste both update's at the same time)

UPDATE test_lock
SET value = 'hello from client b @ ' || now()
WHERE id = 1;

UPDATE test_lock
SET value = 'hello from client b @ ' || now()
WHERE id = 2;


/*
Result: the second update will be executed only after the transaction in client 1 has 
finished; 

We can verify that by looking at the timestamp value. If there is no lock, the difference
is insignificant. With the lock, it might be of several seconds.
*/
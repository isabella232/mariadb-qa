USE test;
CREATE TABLE t(c INT DEFAULT (1 LIKE (NOW() BETWEEN '' AND '')));
INSERT DELAYED INTO t VALUES(1);

SET SQL_MODE='';
CREATE TABLE t (a INT AS (b + 1), b INT, row_start BIGINT UNSIGNED AS ROW START INVISIBLE, row_end BIGINT UNSIGNED AS ROW END INVISIBLE, PERIOD FOR system_time (row_start, row_end)) WITH SYSTEM VERSIONING;
INSERT INTO test.t (a) VALUES (poINT (1,1));
SELECT * FROM t FOR system_time FROM '0-0-0' TO CURRENT_TIMESTAMP(6);

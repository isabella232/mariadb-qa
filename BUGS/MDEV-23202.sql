CREATE TABLE t (a INT);
CREATE VIEW v AS SELECT 1 FROM t;
SET big_tables= 1; # Not needed for 10.5+
CREATE PROCEDURE p() SELECT 2 FROM v;
CREATE TEMPORARY TABLE v SELECT 3 AS b;
CALL p();
SET PSEUDO_THREAD_ID= 111;
CALL p();

CREATE TABLE t (a INT);
CREATE VIEW v AS SELECT 1 FROM t;
CREATE PROCEDURE p() SELECT 2 FROM v;
CREATE TEMPORARY TABLE v SELECT 3 AS b;
CALL p();
ALTER TABLE v RENAME TO vv;
CALL p();

CREATE PROCEDURE p() SELECT * FROM (SELECT 1 FROM mysql.user) AS a;
SET SESSION optimizer_switch="derived_merge=OFF";
CALL p();
SET SESSION optimizer_switch="derived_merge=ON";
CALL p();

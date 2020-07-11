USE test;
CREATE TABLE t (i INT, j INT, KEY(i)) ENGINE=InnoDB;
SELECT FIRST_VALUE(j) OVER (ORDER BY 0 + (SELECT FIRST_VALUE(upper.j) OVER (ORDER BY upper.j) FROM t LIMIT 1)) FROM t AS upper;

USE test;
CREATE TABLE t (i INT, j INT);
SELECT LAST_VALUE(j) OVER (ORDER BY 0 + (SELECT FIRST_VALUE(upper.j) OVER (ORDER BY upper.j) FROM t LIMIT 1)) FROM t AS upper;

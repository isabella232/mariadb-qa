USE test;
CREATE TABLE t (a BINARY) ENGINE=InnoDB;
INSERT INTO t VALUES (1);
ALTER TABLE t CHANGE COLUMN a a CHAR(10);
ALTER TABLE t CHANGE COLUMN a a CHAR(100) BINARY;
SELECT a FROM t;

USE test;
SET SQL_MODE='STRICT_TRANS_TABLES';
CREATE TABLE t (a DOUBLE PRIMARY KEY AUTO_INCREMENT);
INSERT INTO t VALUES (18446744073709551601);

USE test;
CREATE TABLE t (a DOUBLE PRIMARY KEY AUTO_INCREMENT);
INSERT INTO t VALUES (18446744073709551601);
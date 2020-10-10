SET SQL_MODE='';
CREATE TABLE t (c INT) ENGINE=InnoDB PARTITION BY HASH (c) PARTITIONS 2;
LOCK TABLES t WRITE;
ANALYZE TABLE t PERSISTENT FOR COLUMNS (b) INDEXES (i);

CREATE TABLE t (a INT) PARTITION BY HASH (a) PARTITIONS 2;
LOCK TABLES t WRITE;
ANALYZE TABLE t PERSISTENT FOR COLUMNS (nonexisting) INDEXES (nonexisting);

SET SQL_MODE='';
CREATE TABLE t (a INT PRIMARY KEY) PARTITION BY HASH (a) PARTITIONS 2;
INSERT INTO t VALUES (1);
LOCK TABLES t WRITE;
ANALYZE TABLE t PERSISTENT FOR COLUMNS (nonexisting) INDEXES (nonexisting);
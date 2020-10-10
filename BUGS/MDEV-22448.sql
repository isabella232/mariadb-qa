USE test;
CREATE TABLE t1(a INT);
CREATE TABLE t2(b INT);
LOCK TABLES t2 AS a2 WRITE;
BACKUP LOCK t1;
UNLOCK TABLES;
INSERT INTO t1 VALUES(0);

USE test;
CREATE TABLE t1(a INT);
CREATE TABLE t2(b INT);
LOCK TABLES t2 AS a2 WRITE;
BACKUP LOCK t1;
UNLOCK TABLES;
INSERT INTO t1 VALUES(0);

# MDEV-20945
CREATE TABLE t1(a INT);
BACKUP LOCK t1;
FLUSH TABLE t1 WITH READ LOCK; # FOR EXPORT crashes as well
UNLOCK TABLES;
BACKUP UNLOCK;
DROP TABLE t1;

# MDEV-20945
USE test;
CREATE TABLE t (c INT);
BACKUP LOCK not_existing.t;
LOCK TABLES t WRITE;
UNLOCK TABLES;
# Shutdown server; crash happens on shutdown

# MDEV-20945
USE test;
BACKUP LOCK t1;
CREATE TABLE t2(c1 TIME,c2 TIME,c3 DATE,KEY (c1,c2));
LOCK TABLE t2 READ;
# Shutdown server; crash happens on shutdown

USE test;
BACKUP LOCK t;
CREATE VIEW v AS SELECT 1;
LOCK TABLES v READ;
START TRANSACTION READ ONLY;
BACKUP LOCK t;

USE test;
SET SQL_MODE='';
SET STATEMENT max_statement_time=180 FOR BACKUP LOCK test.u;
CREATE TABLE t (a INT) ENGINE=Aria;
CREATE TEMPORARY TABLE IF NOT EXISTS s (c INT) ENGINE=Aria;
LOCK TABLES s AS a READ LOCAL,t AS b WRITE;
DROP TABLE t;
SELECT * FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE;
SET STATEMENT max_statement_time=180 FOR BACKUP LOCK test.u;

# mysqld options required for replay: --log-bin --sql_mode=ONLY_FULL_GROUP_BY 
USE test;
SET STATEMENT max_statement_time=180 FOR BACKUP LOCK test.t1;
select t2.id from t2,t1;
CREATE TABLE t2 (a INT,b CHAR (1)) ENGINE=InnoDB;
CREATE TEMPORARY TABLE IF NOT EXISTS t3 (c1 NUMERIC(1) ZEROFILL,c2 POINT,c3 TIMESTAMP(1)) ENGINE=Aria;
LOCK TABLES t3 AS a1 READ LOCAL,t2 AS a0 WRITE;
DROP TABLE t2;
SELECT TABLE_NAME,COLUMN_NAME,REFERENCED_TABLE_NAME,REFERENCED_COLUMN_NAME FROM INFORMATION_SCHEMA.KEY_COLUMN_USAGE;

USE test;
SET STATEMENT max_statement_time=180 FOR BACKUP LOCK test.t1;
CREATE TABLE t1 (id INT AUTO_INCREMENT PRIMARY KEY)ENGINE=Aria;
RENAME TABLE t1 TO t2;
FLUSH LOCAL TABLES t2 WITH READ LOCK;

DROP DATABASE test;
CREATE DATABASE test;
USE test;
BACKUP LOCK t;
CREATE TABLE t2 (a INT DEFAULT 0, b INT PRIMARY KEY) ENGINE=InnoDB;
FLUSH TABLES t2 FOR EXPORT;

BACKUP LOCK test.t;
CREATE TABLE t (c INT) ENGINE=InnoDB;
LOCK TABLES t AS a READ;
BEGIN;
SET STATEMENT max_statement_time=180 FOR BACKUP UNLOCK;

# Repeat 30+ times, sporadic
DROP DATABASE test;
CREATE DATABASE test;
USE test;
BACKUP LOCK t;
CREATE TABLE t (id INT NOT NULL AUTO_INCREMENT PRIMARY KEY) ENGINE=InnoDB;
LOCK TABLES t AS a READ LOCAL, t AS b LOW_PRIORITY WRITE;

# Highly sporadic, or may require pquery, ref bug report for details
# mysqld options required for replay: --maximum-join_buffer_size=1M --maximum-read_buffer_size=1M --maximum-read_rnd_buffer_size=1M --maximum-sort_buffer_size=1M --maximum-transaction_prealloc_size=1M
BACKUP LOCK t;
INSERT INTO mysql.ndb_replication VALUES ("europenorth", "fr_nce", 1, NULL, "NDB$A ()");
CREATE TABLE t (a TINYTEXT COLUMN_FORMAT COMPRESSED) ROW_FORMAT = REDUNDANT;
DROP PROCEDURE getNums;
CREATE TABLE t2 (id INT(11) NOT NULL AUTO_INCREMENT, PRIMARY KEY(id));
DROP TABLE datetypes;
LOCK TABLES t2 AS a1 READ LOCAL, t2 AS a6 LOW_PRIORITY WRITE;

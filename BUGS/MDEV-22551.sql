CREATE TABLE t1 (id INT, f TEXT UNIQUE, d DATE, PRIMARY KEY (id)) ENGINE=InnoDB;
INSERT INTO t1 VALUES (1,NULL,'2001-11-16'),(2,NULL,'2007-07-01'),(3,NULL,'2020-02-03'), (4,NULL,'1971-05-24'),(5,NULL,'1971-05-24'),(6,NULL,'1985-02-07'); 
ANALYZE TABLE t1 PERSISTENT FOR ALL;
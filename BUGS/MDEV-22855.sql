USE test;
CREATE TABLE t(c CHAR(255) CHARACTER SET UTF32, KEY k1(c)) ENGINE=MyISAM;
INSERT INTO t VALUES(100000);
ALTER TABLE t ENGINE=InnoDB;

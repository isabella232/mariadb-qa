USE test;
CREATE TABLE t(a INT) PARTITION BY RANGE(a) SUBPARTITION BY HASH(a) (PARTITION p VALUES LESS THAN (5) (SUBPARTITION sp, SUBPARTITION sp1), PARTITION p1 VALUES LESS THAN MAXVALUE (SUBPARTITION sp2, SUBPARTITION sp3));
ALTER TABLE t DROP PARTITION p;

USE test;
CREATE TABLE t (c1 MEDIUMINT,name VARCHAR(30), purchased DATE) PARTITION BY RANGE(YEAR(purchased)) SUBPARTITION BY HASH(TO_DAYS(purchased)) (PARTITION p0 VALUES LESS THAN (1990) (SUBPARTITION s0, SUBPARTITION s1), PARTITION p1 VALUES LESS THAN (2000) (SUBPARTITION s2, SUBPARTITION s3), PARTITION p2 VALUES LESS THAN MAXVALUE (SUBPARTITION s4, SUBPARTITION s5));
ALTER TABLE t drop partition p2;

USE test;
CREATE TABLE t (c INT, d DATE) PARTITION BY RANGE(YEAR(d)) SUBPARTITION BY HASH(TO_DAYS(d)) (PARTITION p0 VALUES LESS THAN (1990) (SUBPARTITION s0, SUBPARTITION s1), PARTITION p1 VALUES LESS THAN MAXVALUE (SUBPARTITION s4, SUBPARTITION s5));
ALTER TABLE t DROP PARTITION p2;  # Error 1507

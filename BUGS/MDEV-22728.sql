USE test;
SET SESSION OPTIMIZER_SWITCH="index_merge_sort_intersection=ON";
SET SESSION sort_buffer_size=2048;
CREATE TABLE t1(c1 VARCHAR(2049) BINARY PRIMARY KEY,c2 INT,c3 INT,INDEX(c2),UNIQUE (c1));
SELECT * FROM t1 WHERE c1>=69 AND c1<'' AND c2='';

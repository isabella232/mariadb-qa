CREATE OR REPLACE TABLE t1 (a INT);
ALTER TABLE t1 ADD row_start TIMESTAMP(6) AS ROW START, ADD row_end TIMESTAMP(6) AS ROW END, ADD PERIOD FOR SYSTEM_TIME(row_start,row_end), WITH SYSTEM VERSIONING, MODIFY row_end VARCHAR(8);

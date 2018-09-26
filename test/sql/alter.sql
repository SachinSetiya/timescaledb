-- DROP a table's column before making it a hypertable
CREATE TABLE alter_before(id serial, time timestamp, temp float, colorid integer, notes text, notes_2 text);
ALTER TABLE alter_before DROP COLUMN id;
ALTER TABLE alter_before ALTER COLUMN temp SET (n_distinct = 10);
ALTER TABLE alter_before ALTER COLUMN colorid SET (n_distinct = 11);
ALTER TABLE alter_before ALTER COLUMN colorid RESET (n_distinct);
ALTER TABLE alter_before ALTER COLUMN temp SET STATISTICS 100;
ALTER TABLE alter_before ALTER COLUMN notes SET STORAGE EXTERNAL;

SELECT create_hypertable('alter_before', 'time', chunk_time_interval => 2628000000000);

INSERT INTO alter_before VALUES ('2017-03-22T09:18:22', 23.5, 1);

SELECT * FROM alter_before;

-- Show that deleted column is marked as dropped and that attnums are
-- now different for the root table and the chunk
SELECT c.relname, a.attname, a.attnum, a.attoptions, a.attstattarget, a.attstorage FROM pg_attribute a, pg_class c
WHERE a.attrelid = c.oid
AND (c.relname LIKE '_hyper_1%_chunk' OR c.relname = 'alter_before')
AND a.attnum > 0
ORDER BY c.relname, a.attnum;

-- DROP a table's column after making it a hypertable and having data
CREATE TABLE alter_after(id serial, time timestamp, temp float, colorid integer, notes text, notes_2 text);
SELECT create_hypertable('alter_after', 'time', chunk_time_interval => 2628000000000);

-- Create first chunk
INSERT INTO alter_after (time, temp, colorid) VALUES ('2017-03-22T09:18:22', 23.5, 1);

ALTER TABLE alter_after DROP COLUMN id;
ALTER TABLE alter_after ALTER COLUMN temp SET (n_distinct = 10);
ALTER TABLE alter_after ALTER COLUMN colorid SET (n_distinct = 11);
ALTER TABLE alter_after ALTER COLUMN colorid RESET (n_distinct);
ALTER TABLE alter_after ALTER COLUMN colorid SET STATISTICS 101;
ALTER TABLE alter_after ALTER COLUMN notes_2 SET STORAGE EXTERNAL;

-- Creating new chunks after dropping a column should work just fine
INSERT INTO alter_after VALUES ('2017-03-22T09:18:23', 21.5, 1),
                               ('2017-05-22T09:18:22', 36.2, 2),
                               ('2017-05-22T09:18:23', 15.2, 2);

-- Make sure tuple conversion also works with COPY
\COPY alter_after FROM 'data/alter.tsv' NULL AS '';

-- Data should look OK
SELECT * FROM alter_after;

-- Show that attnums are different for chunks created after DROP
-- column
SELECT c.relname, a.attname, a.attnum FROM pg_attribute a, pg_class c
WHERE a.attrelid = c.oid
AND (c.relname LIKE '_hyper_2%_chunk' OR c.relname = 'alter_after')
AND a.attnum > 0
ORDER BY c.relname, a.attnum;

-- Add an ID column again
ALTER TABLE alter_after ADD COLUMN id serial;

INSERT INTO alter_after (time, temp, colorid) VALUES ('2017-08-22T09:19:14', 12.5, 3);

--test thing that we are allowed to do on chunks
ALTER TABLE  _timescaledb_internal._hyper_2_3_chunk ALTER COLUMN temp RESET (n_distinct);
ALTER TABLE  _timescaledb_internal._hyper_2_4_chunk ALTER COLUMN temp SET (n_distinct = 20);
ALTER TABLE  _timescaledb_internal._hyper_2_4_chunk ALTER COLUMN temp SET STATISTICS 201;
ALTER TABLE  _timescaledb_internal._hyper_2_4_chunk ALTER COLUMN notes SET STORAGE EXTERNAL;

SELECT c.relname, a.attname, a.attnum, a.attoptions, a.attstattarget, a.attstorage FROM pg_attribute a, pg_class c
WHERE a.attrelid = c.oid
AND (c.relname LIKE '_hyper_2%_chunk' OR c.relname = 'alter_after')
AND a.attnum > 0
ORDER BY c.relname, a.attnum;

SELECT * FROM alter_after;

-- Need superuser to ALTER chunks in _timescaledb_internal schema
\c single :ROLE_SUPERUSER
SELECT * FROM _timescaledb_catalog.chunk WHERE id = 2;

-- Rename chunk
ALTER TABLE _timescaledb_internal._hyper_2_2_chunk RENAME TO new_chunk_name;
SELECT * FROM _timescaledb_catalog.chunk WHERE id = 2;

-- Set schema
ALTER TABLE _timescaledb_internal.new_chunk_name SET SCHEMA public;
SELECT * FROM _timescaledb_catalog.chunk WHERE id = 2;

-- Test that we cannot rename chunk columns
\set ON_ERROR_STOP 0
ALTER TABLE public.new_chunk_name RENAME COLUMN time TO newtime;
\set ON_ERROR_STOP 1

-- Test that we can set tablespace of a hypertable
\c single :ROLE_SUPERUSER
SET client_min_messages = ERROR;
DROP TABLESPACE IF EXISTS tablespace1;
DROP TABLESPACE IF EXISTS tablespace2;
SET client_min_messages = NOTICE;
--test hypertable with tables space
CREATE TABLESPACE tablespace1 OWNER :ROLE_DEFAULT_PERM_USER LOCATION :TEST_TABLESPACE1_PATH;
CREATE TABLESPACE tablespace2 OWNER :ROLE_DEFAULT_PERM_USER LOCATION :TEST_TABLESPACE2_PATH;
\c single :ROLE_DEFAULT_PERM_USER

-- Test that we cannot directly change chunk tablespace
\set ON_ERROR_STOP 0
ALTER TABLE public.new_chunk_name SET TABLESPACE tablespace1;
\set ON_ERROR_STOP 1

-- drop all tables to make checking the tests below easier
DROP TABLE alter_before;
DROP TABLE alter_after;
-- should return 0 rows
SELECT tablename, tablespace FROM pg_tables
WHERE tablename = 'hyper_in_space' OR tablename LIKE '\_hyper\__\__\_chunk' ORDER BY tablename;

CREATE TABLE hyper_in_space(time bigint, temp float, device int);
SELECT create_hypertable('hyper_in_space', 'time', 'device', 4, chunk_time_interval=>1);

INSERT INTO hyper_in_space(time, temp, device) VALUES (1, 20, 1);
INSERT INTO hyper_in_space(time, temp, device) VALUES (3, 21, 2);
INSERT INTO hyper_in_space(time, temp, device) VALUES (5, 23, 1);

SELECT tablename FROM pg_tables WHERE tablespace = 'tablespace1' ORDER BY tablename;

SET default_tablespace = tablespace1;

-- should be inserted in tablespace1 which is now default
INSERT INTO hyper_in_space(time, temp, device) VALUES (11, 24, 3);
SELECT tablename, tablespace FROM pg_tables
WHERE tablename = 'hyper_in_space' OR tablename LIKE '\_hyper\__\__\_chunk' ORDER BY tablename;

SET default_tablespace TO DEFAULT;

ALTER TABLE hyper_in_space SET TABLESPACE tablespace1;
SELECT tablename FROM pg_tables WHERE tablespace = 'tablespace1' ORDER BY tablename;

-- should be inserted in an existing chunk in the new tablespace,
-- no new chunks
INSERT INTO hyper_in_space(time, temp, device) VALUES (5, 27, 1);

-- the new chunk should be create in the new tablespace
INSERT INTO hyper_in_space(time, temp, device) VALUES (8, 24, 2);
SELECT tablename, tablespace FROM pg_tables
WHERE tablename = 'hyper_in_space' OR tablename LIKE '\_hyper\__\__\_chunk' ORDER BY tablename;

-- should not fail (unlike attach_tablespace)
ALTER TABLE hyper_in_space SET TABLESPACE tablespace1;

\set ON_ERROR_STOP 0
-- not an empty tablespace
DROP TABLESPACE tablespace1;
\set ON_ERROR_STOP 1

SELECT drop_chunks(20, 'hyper_in_space');
SELECT tablename, tablespace FROM pg_tables WHERE tablespace = 'tablespace1' ORDER BY tablename;

\set ON_ERROR_STOP 0
-- should not be able to drop tablespace if a hypertable depends on it
-- even when there are no chunks
DROP TABLESPACE tablespace1;
\set ON_ERROR_STOP 1

DROP TABLE hyper_in_space;

CREATE TABLE hyper_in_space(time bigint, temp float, device int) TABLESPACE tablespace1;
SELECT create_hypertable('hyper_in_space', 'time', 'device', 4, chunk_time_interval=>1);

INSERT INTO hyper_in_space(time, temp, device) VALUES (1, 20, 1);
INSERT INTO hyper_in_space(time, temp, device) VALUES (3, 21, 2);
INSERT INTO hyper_in_space(time, temp, device) VALUES (5, 23, 1);

SELECT tablename, tablespace FROM pg_tables
WHERE tablename = 'hyper_in_space' OR tablename ~ '_hyper_\d+_\d+_chunk' ORDER BY tablename;

SELECT attach_tablespace('tablespace2', 'hyper_in_space');

\set ON_ERROR_STOP 0
-- should fail as >1 tablespaces are attached
ALTER TABLE hyper_in_space SET TABLESPACE tablespace1;
\set ON_ERROR_STOP 1

SELECT detach_tablespace('tablespace2', 'hyper_in_space');

SELECT * FROM _timescaledb_catalog.tablespace;

-- make sure when using ALTER TABLE, table spaces are not accumulated
-- as in case of attach_tablespace
-- should have one result
SELECT * FROM _timescaledb_catalog.tablespace;
ALTER TABLE hyper_in_space SET TABLESPACE tablespace2;
-- should have one result
SELECT * FROM _timescaledb_catalog.tablespace;
ALTER TABLE hyper_in_space SET TABLESPACE tablespace1;
-- should have one result, (same as the first in the block)
SELECT * FROM _timescaledb_catalog.tablespace;

SELECT tablename, tablespace FROM pg_tables
WHERE tablename = 'hyper_in_space' OR tablename ~ '_hyper_\d+_\d+_chunk' ORDER BY tablename;
-- attach tb2 <-> ALTER SET tb1 <-> detach tb1 should work
SELECT detach_tablespace('tablespace1', 'hyper_in_space');
INSERT INTO hyper_in_space(time, temp, device) VALUES (5, 23, 1);
INSERT INTO hyper_in_space(time, temp, device) VALUES (7, 23, 1);

SELECT tablename, tablespace FROM pg_tables
WHERE tablename = 'hyper_in_space' OR tablename ~ '_hyper_\d+_\d+_chunk' ORDER BY tablename;
SELECT * FROM _timescaledb_catalog.tablespace;

DROP TABLE hyper_in_space;
DROP TABLESPACE tablespace1;
DROP TABLESPACE tablespace2;

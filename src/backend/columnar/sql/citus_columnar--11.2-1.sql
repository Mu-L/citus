-- complain if script is sourced in psql, rather than via CREATE EXTENSION
\echo Use "CREATE EXTENSION citus_columnar" to load this file. \quit

-- columnar--9.5-1--10.0-1.sql

CREATE SCHEMA IF NOT EXISTS columnar;
SET search_path TO columnar;


CREATE SEQUENCE IF NOT EXISTS storageid_seq MINVALUE 10000000000 NO CYCLE;

CREATE TABLE IF NOT EXISTS options (
    regclass regclass NOT NULL PRIMARY KEY,
    chunk_group_row_limit int NOT NULL,
    stripe_row_limit int NOT NULL,
    compression_level int NOT NULL,
    compression name NOT NULL
) WITH (user_catalog_table = true);

COMMENT ON TABLE options IS 'columnar table specific options, maintained by alter_columnar_table_set';

CREATE TABLE IF NOT EXISTS stripe (
    storage_id bigint NOT NULL,
    stripe_num bigint NOT NULL,
    file_offset bigint NOT NULL,
    data_length bigint NOT NULL,
    column_count int NOT NULL,
    chunk_row_count int NOT NULL,
    row_count bigint NOT NULL,
    chunk_group_count int NOT NULL,
    PRIMARY KEY (storage_id, stripe_num)
) WITH (user_catalog_table = true);

COMMENT ON TABLE stripe IS 'Columnar per stripe metadata';

CREATE TABLE IF NOT EXISTS chunk_group (
    storage_id bigint NOT NULL,
    stripe_num bigint NOT NULL,
    chunk_group_num int NOT NULL,
    row_count bigint NOT NULL,
    PRIMARY KEY (storage_id, stripe_num, chunk_group_num),
    FOREIGN KEY (storage_id, stripe_num) REFERENCES stripe(storage_id, stripe_num) ON DELETE CASCADE
);

COMMENT ON TABLE chunk_group IS 'Columnar chunk group metadata';

CREATE TABLE IF NOT EXISTS chunk (
    storage_id bigint NOT NULL,
    stripe_num bigint NOT NULL,
    attr_num int NOT NULL,
    chunk_group_num int NOT NULL,
    minimum_value bytea,
    maximum_value bytea,
    value_stream_offset bigint NOT NULL,
    value_stream_length bigint NOT NULL,
    exists_stream_offset bigint NOT NULL,
    exists_stream_length bigint NOT NULL,
    value_compression_type int NOT NULL,
    value_compression_level int NOT NULL,
    value_decompressed_length bigint NOT NULL,
    value_count bigint NOT NULL,
    PRIMARY KEY (storage_id, stripe_num, attr_num, chunk_group_num),
    FOREIGN KEY (storage_id, stripe_num, chunk_group_num) REFERENCES chunk_group(storage_id, stripe_num, chunk_group_num) ON DELETE CASCADE
) WITH (user_catalog_table = true);

COMMENT ON TABLE chunk IS 'Columnar per chunk metadata';

DO $proc$
BEGIN

-- from version 12 and up we have support for tableam's if installed on pg11 we can't
-- create the objects here. Instead we rely on citus_finish_pg_upgrade to be called by the
-- user instead to add the missing objects
IF substring(current_Setting('server_version'), '\d+')::int >= 12 THEN
  EXECUTE $$
--#include "udfs/columnar_handler/10.0-1.sql"
CREATE OR REPLACE FUNCTION columnar.columnar_handler(internal)
    RETURNS table_am_handler
    LANGUAGE C
AS 'MODULE_PATHNAME', 'columnar_handler';
COMMENT ON FUNCTION columnar.columnar_handler(internal)
    IS 'internal function returning the handler for columnar tables';

-- postgres 11.8 does not support the syntax for table am, also it is seemingly trying
-- to parse the upgrade file and erroring on unknown syntax.
-- normally this section would not execute on postgres 11 anyway. To trick it to pass on
-- 11.8 we wrap the statement in a plpgsql block together with an EXECUTE. This is valid
-- syntax on 11.8 and will execute correctly in 12
DO $create_table_am$
BEGIN
  EXECUTE 'CREATE ACCESS METHOD columnar TYPE TABLE HANDLER columnar.columnar_handler';
END $create_table_am$;

--#include "udfs/alter_columnar_table_set/10.0-1.sql"
CREATE OR REPLACE FUNCTION pg_catalog.alter_columnar_table_set(
    table_name regclass,
    chunk_group_row_limit int DEFAULT NULL,
    stripe_row_limit int DEFAULT NULL,
    compression name DEFAULT null,
    compression_level int DEFAULT NULL)
    RETURNS void
    LANGUAGE C
AS 'MODULE_PATHNAME', 'alter_columnar_table_set';

COMMENT ON FUNCTION pg_catalog.alter_columnar_table_set(
    table_name regclass,
    chunk_group_row_limit int,
    stripe_row_limit int,
    compression name,
    compression_level int)
IS 'set one or more options on a columnar table, when set to NULL no change is made';


--#include "udfs/alter_columnar_table_reset/10.0-1.sql"
CREATE OR REPLACE FUNCTION pg_catalog.alter_columnar_table_reset(
    table_name regclass,
    chunk_group_row_limit bool DEFAULT false,
    stripe_row_limit bool DEFAULT false,
    compression bool DEFAULT false,
    compression_level bool DEFAULT false)
    RETURNS void
    LANGUAGE C
AS 'MODULE_PATHNAME', 'alter_columnar_table_reset';

COMMENT ON FUNCTION pg_catalog.alter_columnar_table_reset(
    table_name regclass,
    chunk_group_row_limit bool,
    stripe_row_limit bool,
    compression bool,
    compression_level bool)
IS 'reset on or more options on a columnar table to the system defaults';

  $$;
END IF;
END$proc$;

-- add citus_internal schema
CREATE SCHEMA IF NOT EXISTS citus_internal;

-- (this function being dropped in 10.0.3)->#include "udfs/columnar_ensure_objects_exist/10.0-1.sql"

-- citus_internal.columnar_ensure_objects_exist is an internal helper function to create
-- missing objects, anything related to the table access methods.
-- Since the API for table access methods is only available in PG12 we can't create these
-- objects when Citus is installed in PG11. Once citus is installed on PG11 the user can
-- upgrade their database to PG12. Now they require the table access method objects that
-- we couldn't create before.
-- This internal function is called from `citus_finish_pg_upgrade` which the user is
-- required to call after a PG major upgrade.
-- CREATE OR REPLACE FUNCTION citus_internal.columnar_ensure_objects_exist()
--     RETURNS void
--     LANGUAGE plpgsql
--     SET search_path = pg_catalog
-- AS $ceoe$
-- BEGIN

-- when postgres is version 12 or above we need to create the tableam. If the tableam
-- exist we assume all objects have been created.
-- IF substring(current_Setting('server_version'), '\d+')::int >= 12 THEN
-- IF NOT EXISTS (SELECT 1 FROM pg_am WHERE amname = 'columnar') THEN

-- --#include "../columnar_handler/10.0-1.sql"

-- --#include "../alter_columnar_table_set/10.0-1.sql"

-- --#include "../alter_columnar_table_reset/10.0-1.sql"

--     -- add the missing objects to the extension
--     ALTER EXTENSION citus ADD FUNCTION columnar.columnar_handler(internal);
--     ALTER EXTENSION citus ADD ACCESS METHOD columnar;
--     ALTER EXTENSION citus ADD FUNCTION pg_catalog.alter_columnar_table_set(
--         table_name regclass,
--         chunk_group_row_limit int,
--         stripe_row_limit int,
--         compression name,
--         compression_level int);
--     ALTER EXTENSION citus ADD FUNCTION pg_catalog.alter_columnar_table_reset(
--         table_name regclass,
--         chunk_group_row_limit bool,
--         stripe_row_limit bool,
--         compression bool,
--         compression_level bool);

-- END IF;
-- END IF;
-- END;
-- $ceoe$;

--COMMENT ON FUNCTION citus_internal.columnar_ensure_objects_exist()
--     IS 'internal function to be called by pg_catalog.citus_finish_pg_upgrade responsible for creating the columnar objects';


RESET search_path;

-- columnar--10.0.-1 --10.0.2
GRANT USAGE ON SCHEMA columnar TO PUBLIC;
GRANT SELECT ON ALL tables IN SCHEMA columnar TO PUBLIC ;

-- columnar--10.0-3--10.1-1.sql

-- Drop foreign keys between columnar metadata tables.
-- Postgres assigns different names to those foreign keys in PG11, so act accordingly.
DO $proc$
BEGIN
IF substring(current_Setting('server_version'), '\d+')::int >= 12 THEN
  EXECUTE $$
ALTER TABLE columnar.chunk DROP CONSTRAINT IF EXISTS chunk_storage_id_stripe_num_chunk_group_num_fkey;
ALTER TABLE columnar.chunk_group DROP CONSTRAINT IF EXISTS chunk_group_storage_id_stripe_num_fkey;
  $$;
ELSE
  EXECUTE $$
ALTER TABLE columnar.chunk DROP CONSTRAINT IF EXISTS chunk_storage_id_fkey;
ALTER TABLE columnar.chunk_group DROP CONSTRAINT IF EXISTS chunk_group_storage_id_fkey;
  $$;
END IF;
END$proc$;

-- since we dropped pg11 support, we don't need to worry about missing
-- columnar objects when upgrading postgres
-- DROP FUNCTION citus_internal.columnar_ensure_objects_exist();

--10.1-1 -- 10.2-1

-- columnar--10.1-1--10.2-1.sql

-- For a proper mapping between tid & (stripe, row_num), add a new column to
-- columnar.stripe and define a BTREE index on this column.
-- Also include storage_id column for per-relation scans.
ALTER TABLE columnar.stripe ADD COLUMN first_row_number bigint;
CREATE INDEX stripe_first_row_number_idx ON columnar.stripe USING BTREE(storage_id, first_row_number);

-- Populate first_row_number column of columnar.stripe table.
--
-- For simplicity, we calculate MAX(row_count) value across all the stripes
-- of all the columanar tables and then use it to populate first_row_number
-- column. This would introduce some gaps however we are okay with that since
-- it's already the case with regular INSERT/COPY's.
DO $$
DECLARE
  max_row_count bigint;
  -- this should be equal to columnar_storage.h/COLUMNAR_FIRST_ROW_NUMBER
  COLUMNAR_FIRST_ROW_NUMBER constant bigint := 1;
BEGIN
  SELECT MAX(row_count) INTO max_row_count FROM columnar.stripe;
  UPDATE columnar.stripe SET first_row_number = COLUMNAR_FIRST_ROW_NUMBER +
                                                (stripe_num - 1) * max_row_count;
END;
$$;

--#include "udfs/upgrade_columnar_storage/10.2-1.sql"
CREATE OR REPLACE FUNCTION citus_internal.upgrade_columnar_storage(rel regclass)
  RETURNS VOID
  STRICT
  LANGUAGE c AS 'MODULE_PATHNAME', $$upgrade_columnar_storage$$;

COMMENT ON FUNCTION citus_internal.upgrade_columnar_storage(regclass)
  IS 'function to upgrade the columnar storage, if necessary';


--#include "udfs/downgrade_columnar_storage/10.2-1.sql"

CREATE OR REPLACE FUNCTION citus_internal.downgrade_columnar_storage(rel regclass)
  RETURNS VOID
  STRICT
  LANGUAGE c AS 'MODULE_PATHNAME', $$downgrade_columnar_storage$$;

COMMENT ON FUNCTION citus_internal.downgrade_columnar_storage(regclass)
  IS 'function to downgrade the columnar storage, if necessary';

-- upgrade storage for all columnar relations
SELECT citus_internal.upgrade_columnar_storage(c.oid) FROM pg_class c, pg_am a
  WHERE c.relam = a.oid AND amname = 'columnar';

-- columnar--10.2-1--10.2-2.sql

-- revoke read access for columnar.chunk from unprivileged
-- user as it contains chunk min/max values
REVOKE SELECT ON columnar.chunk FROM PUBLIC;


-- columnar--10.2-2--10.2-3.sql

-- Since stripe_first_row_number_idx is required to scan a columnar table, we
-- need to make sure that it is created before doing anything with columnar
-- tables during pg upgrades.
--
-- However, a plain btree index is not a dependency of a table, so pg_upgrade
-- cannot guarantee that stripe_first_row_number_idx gets created when
-- creating columnar.stripe, unless we make it a unique "constraint".
--
-- To do that, drop stripe_first_row_number_idx and create a unique
-- constraint with the same name to keep the code change at minimum.
DROP INDEX columnar.stripe_first_row_number_idx;
ALTER TABLE columnar.stripe ADD CONSTRAINT stripe_first_row_number_idx
UNIQUE (storage_id, first_row_number);

-- columnar--10.2-3--10.2-4.sql

CREATE OR REPLACE FUNCTION citus_internal.columnar_ensure_am_depends_catalog()
  RETURNS void
  LANGUAGE plpgsql
  SET search_path = pg_catalog
AS $func$
BEGIN
  INSERT INTO pg_depend
  SELECT -- Define a dependency edge from "columnar table access method" ..
         'pg_am'::regclass::oid as classid,
         (select oid from pg_am where amname = 'columnar') as objid,
         0 as objsubid,
         -- ... to each object that is registered to pg_class and that lives
         -- in "columnar" schema. That contains catalog tables, indexes
         -- created on them and the sequences created in "columnar" schema.
         --
         -- Given the possibility of user might have created their own objects
         -- in columnar schema, we explicitly specify list of objects that we
         -- are interested in.
         'pg_class'::regclass::oid as refclassid,
         columnar_schema_members.relname::regclass::oid as refobjid,
         0 as refobjsubid,
         'n' as deptype
  FROM (VALUES ('columnar.chunk'),
               ('columnar.chunk_group'),
               ('columnar.chunk_group_pkey'),
               ('columnar.chunk_pkey'),
               ('columnar.options'),
               ('columnar.options_pkey'),
               ('columnar.storageid_seq'),
               ('columnar.stripe'),
               ('columnar.stripe_first_row_number_idx'),
               ('columnar.stripe_pkey')
       ) columnar_schema_members(relname)
  -- Avoid inserting duplicate entries into pg_depend.
  EXCEPT TABLE pg_depend;
END;
$func$;
COMMENT ON FUNCTION citus_internal.columnar_ensure_am_depends_catalog()
  IS 'internal function responsible for creating dependencies from columnar '
     'table access method to the rel objects in columnar schema';


SELECT citus_internal.columnar_ensure_am_depends_catalog();

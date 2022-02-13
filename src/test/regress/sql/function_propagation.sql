CREATE SCHEMA function_propagation_schema;
SET search_path TO 'function_propagation_schema';

-- Check whether supported dependencies can be distributed while propagating functions

-- Check types
BEGIN;
    CREATE TYPE function_prop_type AS (a int, b int);
COMMIT;

CREATE OR REPLACE FUNCTION func_1(param_1 function_prop_type)
RETURNS int
LANGUAGE plpgsql AS
$$
BEGIN
    return 1;
END;
$$;

-- Check all dependent objects and function depends on all nodes
SELECT pg_identify_object_as_address(classid, objid, objsubid) from citus.pg_dist_object where objid = 'function_propagation_schema'::regnamespace::oid;
SELECT pg_identify_object_as_address(classid, objid, objsubid) from citus.pg_dist_object where objid = 'function_propagation_schema.function_prop_type'::regtype::oid;
SELECT pg_identify_object_as_address(classid, objid, objsubid) from citus.pg_dist_object where objid = 'function_propagation_schema.func_1'::regproc::oid;
SELECT * FROM run_command_on_workers($$SELECT pg_identify_object_as_address(classid, objid, objsubid) from citus.pg_dist_object where objid = 'function_propagation_schema'::regnamespace::oid;$$) ORDER BY 1,2;
SELECT * FROM run_command_on_workers($$SELECT pg_identify_object_as_address(classid, objid, objsubid) from citus.pg_dist_object where objid = 'function_propagation_schema.function_prop_type'::regtype::oid;$$) ORDER BY 1,2;
SELECT * FROM run_command_on_workers($$SELECT pg_identify_object_as_address(classid, objid, objsubid) from citus.pg_dist_object where objid = 'function_propagation_schema.func_1'::regproc::oid;$$) ORDER BY 1,2;

BEGIN;
    CREATE TYPE function_prop_type_2 AS (a int, b int);
COMMIT;

CREATE OR REPLACE FUNCTION func_2(param_1 int)
RETURNS function_prop_type_2
LANGUAGE plpgsql AS
$$
BEGIN
    return 1;
END;
$$;

SELECT pg_identify_object_as_address(classid, objid, objsubid) from citus.pg_dist_object where objid = 'function_propagation_schema.function_prop_type_2'::regtype::oid;
SELECT pg_identify_object_as_address(classid, objid, objsubid) from citus.pg_dist_object where objid = 'function_propagation_schema.func_2'::regproc::oid;
SELECT * FROM run_command_on_workers($$SELECT pg_identify_object_as_address(classid, objid, objsubid) from citus.pg_dist_object where objid = 'function_propagation_schema.function_prop_type_2'::regtype::oid;$$) ORDER BY 1,2;
SELECT * FROM run_command_on_workers($$SELECT pg_identify_object_as_address(classid, objid, objsubid) from citus.pg_dist_object where objid = 'function_propagation_schema.func_2'::regproc::oid;$$) ORDER BY 1,2;

BEGIN;
    CREATE TYPE function_prop_type_3 AS (a int, b int);
COMMIT;

-- Objects in the body part is not found as dependency
CREATE OR REPLACE FUNCTION func_3(param_1 int)
RETURNS int
LANGUAGE plpgsql AS
$$
DECLARE
    internal_param1 function_prop_type_3;
BEGIN
    return 1;
END;
$$;

SELECT pg_identify_object_as_address(classid, objid, objsubid) from citus.pg_dist_object where objid = 'function_propagation_schema.function_prop_type_3'::regtype::oid;
SELECT pg_identify_object_as_address(classid, objid, objsubid) from citus.pg_dist_object where objid = 'function_propagation_schema.func_3'::regproc::oid;
SELECT * FROM run_command_on_workers($$SELECT pg_identify_object_as_address(classid, objid, objsubid) from citus.pg_dist_object where objid = 'function_propagation_schema.func_3'::regproc::oid;$$) ORDER BY 1,2;

-- Check sequences
-- Note that after pg 14 creating sequence doesn't create type
-- it is expected for versions > pg14 to fail sequence tests below
CREATE SEQUENCE function_prop_seq;
CREATE OR REPLACE FUNCTION func_4(param_1 function_prop_seq)
RETURNS int
LANGUAGE plpgsql AS
$$
BEGIN
    return 1;
END;
$$;

SELECT pg_identify_object_as_address(classid, objid, objsubid) from citus.pg_dist_object where objid = 'function_propagation_schema.function_prop_seq'::regclass::oid;
SELECT pg_identify_object_as_address(classid, objid, objsubid) from citus.pg_dist_object where objid = 'function_propagation_schema.func_4'::regproc::oid;
SELECT * FROM run_command_on_workers($$SELECT pg_identify_object_as_address(classid, objid, objsubid) from citus.pg_dist_object where objid = 'function_propagation_schema.function_prop_seq'::regclass::oid;$$) ORDER BY 1,2;
SELECT * FROM run_command_on_workers($$SELECT pg_identify_object_as_address(classid, objid, objsubid) from citus.pg_dist_object where objid = 'function_propagation_schema.func_4'::regproc::oid;$$) ORDER BY 1,2;

CREATE SEQUENCE function_prop_seq_2;
CREATE OR REPLACE FUNCTION func_5(param_1 int)
RETURNS function_prop_seq_2
LANGUAGE plpgsql AS
$$
BEGIN
    return 1;
END;
$$;

SELECT pg_identify_object_as_address(classid, objid, objsubid) from citus.pg_dist_object where objid = 'function_propagation_schema.function_prop_seq_2'::regclass::oid;
SELECT pg_identify_object_as_address(classid, objid, objsubid) from citus.pg_dist_object where objid = 'function_propagation_schema.func_5'::regproc::oid;
SELECT * FROM run_command_on_workers($$SELECT pg_identify_object_as_address(classid, objid, objsubid) from citus.pg_dist_object where objid = 'function_propagation_schema.function_prop_seq_2'::regclass::oid;$$) ORDER BY 1,2;
SELECT * FROM run_command_on_workers($$SELECT pg_identify_object_as_address(classid, objid, objsubid) from citus.pg_dist_object where objid = 'function_propagation_schema.func_5'::regproc::oid;$$) ORDER BY 1,2;

-- Check table
CREATE TABLE function_prop_table(a int, b int);

-- Non-distributed table is not distributed as dependency
CREATE OR REPLACE FUNCTION func_6(param_1 function_prop_table)
RETURNS int
LANGUAGE plpgsql AS
$$
BEGIN
    return 1;
END;
$$;

CREATE OR REPLACE FUNCTION func_7(param_1 int)
RETURNS function_prop_table
LANGUAGE plpgsql AS
$$
BEGIN
    return 1;
END;
$$;

-- Functions can be created with distributed table dependency
SELECT create_distributed_table('function_prop_table', 'a');
CREATE OR REPLACE FUNCTION func_8(param_1 function_prop_table)
RETURNS int
LANGUAGE plpgsql AS
$$
BEGIN
    return 1;
END;
$$;

SELECT pg_identify_object_as_address(classid, objid, objsubid) from citus.pg_dist_object where objid = 'function_propagation_schema.func_8'::regproc::oid;
SELECT * FROM run_command_on_workers($$SELECT pg_identify_object_as_address(classid, objid, objsubid) from citus.pg_dist_object where objid = 'function_propagation_schema.func_8'::regproc::oid;$$) ORDER BY 1,2;

-- Views are not supported
CREATE VIEW function_prop_view AS SELECT * FROM function_prop_table;
CREATE OR REPLACE FUNCTION func_9(param_1 function_prop_view)
RETURNS int
LANGUAGE plpgsql AS
$$
BEGIN
    return 1;
END;
$$;

CREATE OR REPLACE FUNCTION func_10(param_1 int)
RETURNS function_prop_view
LANGUAGE plpgsql AS
$$
BEGIN
    return 1;
END;
$$;

RESET search_path;
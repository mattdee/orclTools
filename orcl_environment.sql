SET SERVEROUTPUT ON SIZE UNLIMITED
SET LINESIZE 200

-- =============================================================
-- Script: detect_environment.sql
-- Purpose: Detect whether the current session is connected
--          to an Autonomous Database (ADB) and/or a RAC cluster.
-- Author: Matt DeMarco
-- =============================================================

CREATE OR REPLACE FUNCTION is_autonomous_db
RETURN VARCHAR2
IS
    l_service   VARCHAR2(100);
    l_identity  VARCHAR2(4000);
    l_result    VARCHAR2(3) := 'No';
BEGIN
    -- 1. Check USERENV context for Autonomous Service name
    l_service := SYS_CONTEXT('USERENV', 'CLOUD_SERVICE');
    IF l_service IS NOT NULL AND UPPER(l_service) LIKE '%AUTONOMOUS%' THEN
        RETURN 'Yes';
    END IF;

    -- 2. Try dynamic SQL against V$PDBS or DBA_PDBS
    BEGIN
        BEGIN
            EXECUTE IMMEDIATE 'SELECT MAX(cloud_identity) FROM v$pdbs'
              INTO l_identity;
        EXCEPTION
            WHEN OTHERS THEN
                BEGIN
                    EXECUTE IMMEDIATE 'SELECT MAX(cloud_identity) FROM dba_pdbs'
                      INTO l_identity;
                EXCEPTION
                    WHEN OTHERS THEN
                        l_identity := NULL;
                END;
        END;

        IF l_identity IS NOT NULL THEN
            RETURN 'Yes';
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            NULL; -- not available or insufficient privilege
    END;

    -- 3. Check for DBMS_CLOUD presence (ADB-only)
    BEGIN
        DECLARE
            l_dummy VARCHAR2(10);
        BEGIN
            EXECUTE IMMEDIATE 'SELECT DBMS_CLOUD.VERSION FROM DUAL' INTO l_dummy;
            RETURN 'Yes';
        EXCEPTION
            WHEN OTHERS THEN
                NULL;
        END;
    EXCEPTION
        WHEN OTHERS THEN
            NULL;
    END;

    RETURN l_result;
END;
/
SHOW ERRORS


-- =============================================================
-- Main block: environment inspection and reporting
-- =============================================================
DECLARE
    l_status      VARCHAR2(3);
    l_cluster_val VARCHAR2(10);
BEGIN
    DBMS_OUTPUT.PUT_LINE('=============================================================');
    DBMS_OUTPUT.PUT_LINE(' Environment Detection Summary');
    DBMS_OUTPUT.PUT_LINE('=============================================================');

    -- Autonomous Database Detection
    l_status := is_autonomous_db;
    DBMS_OUTPUT.PUT_LINE('Connected to Autonomous Database? ' || l_status);

    IF l_status = 'Yes' THEN
        BEGIN
            DBMS_OUTPUT.PUT_LINE('Autonomous PDB Information:');
            FOR r IN (
                SELECT name, cloud_identity
                  FROM v$pdbs
                 WHERE cloud_identity IS NOT NULL
            )
            LOOP
                DBMS_OUTPUT.PUT_LINE('  PDB: ' || r.name || ' | Cloud Identity: ' || r.cloud_identity);
            END LOOP;
        EXCEPTION
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('  (Could not read V$PDBS)');
        END;
    ELSE
        DBMS_OUTPUT.PUT_LINE('No Autonomous Database indicators detected.');
    END IF;

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '-------------------------------------------------------------');
    DBMS_OUTPUT.PUT_LINE(' Cluster Configuration');
    DBMS_OUTPUT.PUT_LINE('-------------------------------------------------------------');

    -- Check if RAC/Cluster database
    BEGIN
        SELECT value INTO l_cluster_val
          FROM v$parameter
         WHERE name = 'cluster_database';

        DBMS_OUTPUT.PUT_LINE('Cluster Database Enabled? ' || l_cluster_val);

        IF UPPER(l_cluster_val) = 'TRUE' THEN
            DBMS_OUTPUT.PUT_LINE('Cluster Nodes:');
            BEGIN
                FOR r IN (
                    SELECT inst_id,
                           instance_name,
                           host_name,
                           status,
                           parallel
                      FROM gv$instance
                     ORDER BY inst_id
                ) LOOP
                    DBMS_OUTPUT.PUT_LINE(
                        '  Node ' || r.inst_id || ': ' ||
                        r.instance_name || ' on ' || r.host_name ||
                        ' (' || r.status || ', parallel=' || r.parallel || ')'
                    );
                END LOOP;
            EXCEPTION
                WHEN OTHERS THEN
                    DBMS_OUTPUT.PUT_LINE('  (Unable to read GV$INSTANCE)');
            END;
        ELSE
            DBMS_OUTPUT.PUT_LINE('  Single-instance database.');
        END IF;
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('  (Could not determine cluster configuration)');
    END;

    DBMS_OUTPUT.PUT_LINE(CHR(10) || '-------------------------------------------------------------');
    DBMS_OUTPUT.PUT_LINE(' Database Edition');
    DBMS_OUTPUT.PUT_LINE('-------------------------------------------------------------');

    -- Database Edition Detection
    BEGIN
        FOR r IN (
            SELECT banner FROM v$version
             WHERE banner LIKE 'Oracle Database%'
        ) LOOP
            DBMS_OUTPUT.PUT_LINE('  ' || r.banner);
        END LOOP;
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('  (Unable to determine database edition)');
    END;

    DBMS_OUTPUT.PUT_LINE('=============================================================');
END;
/

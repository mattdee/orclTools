/* 
--------------------
Ensure select privs
--------------------
GRANT select on dba_segments TO public;
GRANT SELECT ON dba_tables TO public;
GRANT SELECT ON dba_tab_partitions TO public;

*/

CREATE OR REPLACE PROCEDURE report_table_size (
    p_owner       IN VARCHAR2 DEFAULT NULL,
    p_table_name  IN VARCHAR2,
    p_live_count  IN BOOLEAN  DEFAULT FALSE  -- TRUE for exact count, FALSE for stats-based
) AS
    v_owner       VARCHAR2(128);
    v_row_count   NUMBER := NULL;
    v_count_sql   VARCHAR2(1000);
BEGIN
    v_owner := NVL(UPPER(p_owner), SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'));

    DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------');
    DBMS_OUTPUT.PUT_LINE('Table Size Report');
    DBMS_OUTPUT.PUT_LINE('Schema : ' || v_owner);
    DBMS_OUTPUT.PUT_LINE('Table  : ' || UPPER(p_table_name));
    DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------');

    --------------------------------------------------------------------
    -- 1. Retrieve Row Count (from dictionary or live count)
    --------------------------------------------------------------------
    IF p_live_count THEN
        v_count_sql := 'SELECT COUNT(*) FROM ' || v_owner || '.' || UPPER(p_table_name);
        EXECUTE IMMEDIATE v_count_sql INTO v_row_count;
    ELSE
        SELECT num_rows
          INTO v_row_count
          FROM dba_tables
         WHERE owner = v_owner
           AND table_name = UPPER(p_table_name);
    END IF;

    --------------------------------------------------------------------
    -- 2. Display Table Size Summary
    --------------------------------------------------------------------
    FOR rec IN (
        SELECT
            segment_name AS table_name,
            ROUND(SUM(bytes)/1024/1024, 2) AS size_mb,
            ROUND(SUM(bytes)/1024/1024/1024, 2) AS size_gb,
            ROUND(SUM(bytes)/1024/1024/1024/1024, 4) AS size_tb
        FROM
            dba_segments
        WHERE
            owner = v_owner
            AND segment_name = UPPER(p_table_name)
        GROUP BY
            segment_name
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('Row count     : ' || TO_CHAR(v_row_count, '999,999,999,999'));
        DBMS_OUTPUT.PUT_LINE('Table size (MB): ' || TO_CHAR(rec.size_mb, '999,999,999.00'));
        DBMS_OUTPUT.PUT_LINE('Table size (GB): ' || TO_CHAR(rec.size_gb, '999,999,999.00'));
        DBMS_OUTPUT.PUT_LINE('Table size (TB): ' || TO_CHAR(rec.size_tb, '999,999,999.0000'));
    END LOOP;

    --------------------------------------------------------------------
    -- 3. Partition Breakdown (if any)
    --------------------------------------------------------------------
    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('Partition Breakdown (if any)');
    DBMS_OUTPUT.PUT_LINE(
        RPAD('PARTITION_NAME', 30) ||
        LPAD('SIZE_MB', 15) ||
        LPAD('SIZE_GB', 15) ||
        LPAD('SIZE_TB', 15) ||
        LPAD('ROWS', 15)
    );
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 90, '-'));

    FOR part_rec IN (
        SELECT
            s.partition_name,
            ROUND(SUM(s.bytes)/1024/1024, 2) AS size_mb,
            ROUND(SUM(s.bytes)/1024/1024/1024, 2) AS size_gb,
            ROUND(SUM(s.bytes)/1024/1024/1024/1024, 4) AS size_tb,
            NVL(p.num_rows, 0) AS num_rows
        FROM
            dba_segments s
            LEFT JOIN dba_tab_partitions p
              ON p.table_owner = s.owner
             AND p.table_name = s.segment_name
             AND p.partition_name = s.partition_name
        WHERE
            s.owner = v_owner
            AND s.segment_name = UPPER(p_table_name)
            AND s.partition_name IS NOT NULL
        GROUP BY
            s.partition_name, p.num_rows
        ORDER BY
            size_mb DESC
    ) LOOP
        DBMS_OUTPUT.PUT_LINE(
            RPAD(part_rec.partition_name, 30) ||
            LPAD(TO_CHAR(part_rec.size_mb, '999,999,999.00'), 15) ||
            LPAD(TO_CHAR(part_rec.size_gb, '999,999,999.00'), 15) ||
            LPAD(TO_CHAR(part_rec.size_tb, '999,999,999.0000'), 15) ||
            LPAD(TO_CHAR(part_rec.num_rows, '999,999,999,999'), 15)
        );
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------');

EXCEPTION
    WHEN NO_DATA_FOUND THEN
        DBMS_OUTPUT.PUT_LINE('No table found for ' || v_owner || '.' || p_table_name);
    WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE('Error: ' || SQLERRM);
END;
/



CREATE OR REPLACE PROCEDURE report_space (
    p_schema_name IN VARCHAR2 DEFAULT NULL
) AS
BEGIN
    DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------');
    DBMS_OUTPUT.PUT_LINE('Space Usage Report for Schema: ' ||
                         SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA'));
    DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------');
    DBMS_OUTPUT.PUT_LINE('');

    FOR rec IN (
        SELECT SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA') AS schema_name,
               ROUND(SUM(bytes) / 1024 / 1024, 2) AS used_mb,
               ROUND(SUM(bytes) / 1024 / 1024 / 1024, 2) AS used_gb
          FROM user_segments
         GROUP BY SYS_CONTEXT('USERENV', 'CURRENT_SCHEMA')
    ) LOOP
        DBMS_OUTPUT.PUT_LINE('TOTAL USAGE');
        DBMS_OUTPUT.PUT_LINE('  SCHEMA : ' || rec.schema_name);
        DBMS_OUTPUT.PUT_LINE('  USED_MB: ' || TO_CHAR(rec.used_mb, '999,999,999.00'));
        DBMS_OUTPUT.PUT_LINE('  USED_GB: ' || TO_CHAR(rec.used_gb, '999,999,999.00'));
        DBMS_OUTPUT.PUT_LINE('');
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('DETAILED PARTITION USAGE:');
    DBMS_OUTPUT.PUT_LINE(
        RPAD('OBJECT_NAME', 32) ||
        RPAD('PARTITION_NAME', 32) ||
        RPAD('TABLESPACE_NAME', 22) ||
        LPAD('USED_MB', 14) ||
        LPAD('USED_GB', 14) ||
        LPAD('ROW_COUNT', 14)
    );
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 128, '-'));

    FOR rec IN (
        SELECT s.segment_name AS object_name,
               s.partition_name,
               s.tablespace_name,
               ROUND(SUM(s.bytes) / 1024 / 1024, 2) AS used_mb,
               ROUND(SUM(s.bytes) / 1024 / 1024 / 1024, 2) AS used_gb,
               NVL(tp.num_rows, 0) AS row_count
          FROM user_segments s
               LEFT JOIN user_tab_partitions tp
                 ON tp.table_name = s.segment_name
                AND tp.partition_name = s.partition_name
         WHERE s.partition_name IS NOT NULL
         GROUP BY s.segment_name,
                  s.partition_name,
                  s.tablespace_name,
                  tp.num_rows
         ORDER BY SUM(s.bytes) DESC
    ) LOOP
        DBMS_OUTPUT.PUT_LINE(
            RPAD(NVL(rec.object_name, ' '), 32) ||
            RPAD(NVL(rec.partition_name, ' '), 32) ||
            RPAD(NVL(rec.tablespace_name, ' '), 22) ||
            LPAD(TO_CHAR(rec.used_mb, '999,999,990.00'), 14) ||
            LPAD(TO_CHAR(rec.used_gb, '999,999,990.00'), 14) ||
            LPAD(TO_CHAR(rec.row_count, '999,999,999'), 14)
        );
    END LOOP;

    DBMS_OUTPUT.PUT_LINE('');
    DBMS_OUTPUT.PUT_LINE('NON-PARTITIONED OBJECT USAGE');
    DBMS_OUTPUT.PUT_LINE(
        RPAD('OBJECT_NAME', 32) ||
        RPAD('SEGMENT_TYPE', 28) ||
        RPAD('TABLESPACE_NAME', 22) ||
        LPAD('USED_MB', 14) ||
        LPAD('USED_GB', 14) ||
        LPAD('ROW_COUNT', 14)
    );
    DBMS_OUTPUT.PUT_LINE(RPAD('-', 128, '-'));

    FOR rec IN (
        SELECT s.segment_name AS object_name,
               s.segment_type,
               s.tablespace_name,
               ROUND(SUM(s.bytes) / 1024 / 1024, 2) AS used_mb,
               ROUND(SUM(s.bytes) / 1024 / 1024 / 1024, 2) AS used_gb,
               NVL(t.num_rows, 0) AS row_count
          FROM user_segments s
               LEFT JOIN user_tables t
                 ON t.table_name = s.segment_name
         WHERE s.partition_name IS NULL
         GROUP BY s.segment_name,
                  s.segment_type,
                  s.tablespace_name,
                  t.num_rows
         ORDER BY SUM(s.bytes) DESC
    ) LOOP
        DBMS_OUTPUT.PUT_LINE(
            RPAD(NVL(rec.object_name, ' '), 32) ||
            RPAD(NVL(rec.segment_type, ' '), 28) ||
            RPAD(NVL(rec.tablespace_name, ' '), 22) ||
            LPAD(TO_CHAR(rec.used_mb, '999,999,990.00'), 14) ||
            LPAD(TO_CHAR(rec.used_gb, '999,999,990.00'), 14) ||
            LPAD(TO_CHAR(rec.row_count, '999,999,999'), 14)
        );
    END LOOP;

    DECLARE
        v_colname  VARCHAR2(128);
        v_sql      VARCHAR2(4000);
        c          SYS_REFCURSOR;
        r_collection_name  VARCHAR2(128);
        r_storage_model    VARCHAR2(32);
        r_used_mb          NUMBER;
        r_row_count        NUMBER;
    BEGIN
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('JSON COLLECTION TABLES');
        DBMS_OUTPUT.PUT_LINE(
            RPAD('COLLECTION_NAME', 32) ||
            RPAD('STORAGE_MODEL', 16) ||
            LPAD('USED_MB', 14) ||
            LPAD('ROW_COUNT', 14)
        );
        DBMS_OUTPUT.PUT_LINE(RPAD('-', 80, '-'));

        BEGIN
            SELECT column_name
              INTO v_colname
              FROM user_tab_columns
             WHERE table_name = 'USER_JSON_COLLECTIONS'
               AND data_type IN ('NUMBER','FLOAT')
               AND column_name NOT IN ('ROW_COUNT')
               AND ROWNUM = 1;

            v_sql :=
                'SELECT collection_name, storage_model, ' ||
                'ROUND(' || v_colname || ' / 1024 / 1024, 2), row_count ' ||
                'FROM user_json_collections ORDER BY ' || v_colname || ' DESC';

            OPEN c FOR v_sql;

            LOOP
                FETCH c INTO r_collection_name, r_storage_model, r_used_mb, r_row_count;
                EXIT WHEN c%NOTFOUND;

                DBMS_OUTPUT.PUT_LINE(
                    RPAD(r_collection_name, 32) ||
                    RPAD(r_storage_model, 16) ||
                    LPAD(TO_CHAR(r_used_mb, '999,999,990.00'), 14) ||
                    LPAD(TO_CHAR(r_row_count, '999,999,999'), 14)
                );
            END LOOP;
            CLOSE c;

        EXCEPTION
            WHEN NO_DATA_FOUND THEN
                DBMS_OUTPUT.PUT_LINE('USER_JSON_COLLECTIONS found but I am working on this....');
            WHEN OTHERS THEN
                DBMS_OUTPUT.PUT_LINE('USER_JSON_COLLECTIONS view not accessible or unsupported in this release.');
        END;
    EXCEPTION
        WHEN OTHERS THEN
            DBMS_OUTPUT.PUT_LINE('JSON collection information not available.');
    END;

END;
/


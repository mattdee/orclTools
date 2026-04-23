/* 
--------------------
Ensure select privs
--------------------
GRANT select on dba_segments TO public;
GRANT SELECT ON dba_tables TO public;
GRANT SELECT ON dba_tab_partitions TO public;

*/

/*

Packaged version

Package spec

*/
CREATE OR REPLACE PACKAGE space_report_pkg AS
    PROCEDURE report_schema_space;

    PROCEDURE report_table_size (
        p_table_name IN VARCHAR2,
        p_live_count IN BOOLEAN DEFAULT FALSE
    );

    PROCEDURE report_table_storage_map (
        p_table_name IN VARCHAR2
    );

    PROCEDURE report_table_datafiles (
        p_table_name IN VARCHAR2
    );

    PROCEDURE report_json_collections (
        p_collection_name IN VARCHAR2 DEFAULT NULL,
        p_live_count      IN BOOLEAN  DEFAULT FALSE
    );
END space_report_pkg;
/

/*

Package body 

*/
CREATE OR REPLACE PACKAGE BODY space_report_pkg AS

    ------------------------------------------------------------------
    -- Helpers
    ------------------------------------------------------------------
    PROCEDURE put_line(p_text IN VARCHAR2 DEFAULT NULL) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(p_text);
    END put_line;

    PROCEDURE put_rule(p_len IN PLS_INTEGER DEFAULT 60) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE(RPAD('-', p_len, '-'));
    END put_rule;

    FUNCTION fmt_num(p_value IN NUMBER, p_model IN VARCHAR2) RETURN VARCHAR2 IS
    BEGIN
        RETURN TO_CHAR(NVL(p_value, 0), p_model);
    END fmt_num;

    FUNCTION table_exists(p_table_name IN VARCHAR2) RETURN BOOLEAN IS
        v_dummy NUMBER;
    BEGIN
        SELECT 1
          INTO v_dummy
          FROM user_tables
         WHERE table_name = UPPER(p_table_name);

        RETURN TRUE;
    EXCEPTION
        WHEN NO_DATA_FOUND THEN
            RETURN FALSE;
    END table_exists;

    ------------------------------------------------------------------
    -- Report overall schema space
    ------------------------------------------------------------------
    PROCEDURE report_schema_space IS
        v_schema_name VARCHAR2(128) := USER;
    BEGIN
        put_rule(60);
        put_line('Space Usage Report for Schema: ' || v_schema_name);
        put_rule(60);
        put_line;

        FOR rec IN (
            SELECT ROUND(SUM(bytes) / 1024 / 1024, 2) AS used_mb,
                   ROUND(SUM(bytes) / 1024 / 1024 / 1024, 2) AS used_gb,
                   ROUND(SUM(bytes) / 1024 / 1024 / 1024 / 1024, 4) AS used_tb
              FROM user_segments
        ) LOOP
            put_line('TOTAL USAGE');
            put_line('  SCHEMA : ' || v_schema_name);
            put_line('  USED_MB: ' || fmt_num(rec.used_mb, '999,999,999.00'));
            put_line('  USED_GB: ' || fmt_num(rec.used_gb, '999,999,999.00'));
            put_line('  USED_TB: ' || fmt_num(rec.used_tb, '999,999,999.0000'));
            put_line;
        END LOOP;

        put_line('DETAILED PARTITION USAGE');
        put_line(
            RPAD('OBJECT_NAME', 32) ||
            RPAD('PARTITION_NAME', 32) ||
            RPAD('TABLESPACE_NAME', 22) ||
            LPAD('USED_MB', 14) ||
            LPAD('USED_GB', 14) ||
            LPAD('ROW_COUNT', 14)
        );
        put_rule(128);

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
            put_line(
                RPAD(NVL(rec.object_name, ' '), 32) ||
                RPAD(NVL(rec.partition_name, ' '), 32) ||
                RPAD(NVL(rec.tablespace_name, ' '), 22) ||
                LPAD(fmt_num(rec.used_mb, '999,999,990.00'), 14) ||
                LPAD(fmt_num(rec.used_gb, '999,999,990.00'), 14) ||
                LPAD(fmt_num(rec.row_count, '999,999,999'), 14)
            );
        END LOOP;

        put_line;
        put_line('NON-PARTITIONED OBJECT USAGE');
        put_line(
            RPAD('OBJECT_NAME', 32) ||
            RPAD('SEGMENT_TYPE', 28) ||
            RPAD('TABLESPACE_NAME', 22) ||
            LPAD('USED_MB', 14) ||
            LPAD('USED_GB', 14) ||
            LPAD('ROW_COUNT', 14)
        );
        put_rule(128);

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
            put_line(
                RPAD(NVL(rec.object_name, ' '), 32) ||
                RPAD(NVL(rec.segment_type, ' '), 28) ||
                RPAD(NVL(rec.tablespace_name, ' '), 22) ||
                LPAD(fmt_num(rec.used_mb, '999,999,990.00'), 14) ||
                LPAD(fmt_num(rec.used_gb, '999,999,990.00'), 14) ||
                LPAD(fmt_num(rec.row_count, '999,999,999'), 14)
            );
        END LOOP;
    END report_schema_space;

    ------------------------------------------------------------------
    -- Report a single table size
    ------------------------------------------------------------------
    PROCEDURE report_table_size (
        p_table_name IN VARCHAR2,
        p_live_count IN BOOLEAN DEFAULT FALSE
    ) IS
        v_table_name VARCHAR2(128) := UPPER(p_table_name);
        v_row_count  NUMBER := 0;
        v_count_sql  VARCHAR2(1000);
        v_found      BOOLEAN := FALSE;
    BEGIN
        IF NOT table_exists(v_table_name) THEN
            put_line('No table found for ' || USER || '.' || v_table_name);
            RETURN;
        END IF;

        put_rule(60);
        put_line('Table Size Report');
        put_line('Schema : ' || USER);
        put_line('Table  : ' || v_table_name);
        put_rule(60);

        IF p_live_count THEN
            v_count_sql := 'SELECT COUNT(*) FROM "' || REPLACE(v_table_name, '"', '""') || '"';
            EXECUTE IMMEDIATE v_count_sql INTO v_row_count;
        ELSE
            SELECT NVL(num_rows, 0)
              INTO v_row_count
              FROM user_tables
             WHERE table_name = v_table_name;
        END IF;

        FOR rec IN (
            SELECT segment_name AS table_name,
                   ROUND(SUM(bytes) / 1024 / 1024, 2) AS size_mb,
                   ROUND(SUM(bytes) / 1024 / 1024 / 1024, 2) AS size_gb,
                   ROUND(SUM(bytes) / 1024 / 1024 / 1024 / 1024, 4) AS size_tb
              FROM user_segments
             WHERE segment_name = v_table_name
               AND segment_type IN ('TABLE', 'TABLE PARTITION', 'TABLE SUBPARTITION')
             GROUP BY segment_name
        ) LOOP
            v_found := TRUE;
            put_line('Row count      : ' || fmt_num(v_row_count, '999,999,999,999'));
            put_line('Table size (MB): ' || fmt_num(rec.size_mb, '999,999,999.00'));
            put_line('Table size (GB): ' || fmt_num(rec.size_gb, '999,999,999.00'));
            put_line('Table size (TB): ' || fmt_num(rec.size_tb, '999,999,999.0000'));
        END LOOP;

        IF NOT v_found THEN
            put_line('No allocated segments found for ' || USER || '.' || v_table_name);
        END IF;

        put_line;
        put_line('Partition Breakdown (if any)');
        put_line(
            RPAD('PARTITION_NAME', 30) ||
            LPAD('SIZE_MB', 15) ||
            LPAD('SIZE_GB', 15) ||
            LPAD('SIZE_TB', 15) ||
            LPAD('ROWS', 15)
        );
        put_rule(90);

        FOR part_rec IN (
            SELECT s.partition_name,
                   ROUND(SUM(s.bytes) / 1024 / 1024, 2) AS size_mb,
                   ROUND(SUM(s.bytes) / 1024 / 1024 / 1024, 2) AS size_gb,
                   ROUND(SUM(s.bytes) / 1024 / 1024 / 1024 / 1024, 4) AS size_tb,
                   NVL(p.num_rows, 0) AS num_rows
              FROM user_segments s
              LEFT JOIN user_tab_partitions p
                ON p.table_name = s.segment_name
               AND p.partition_name = s.partition_name
             WHERE s.segment_name = v_table_name
               AND s.partition_name IS NOT NULL
             GROUP BY s.partition_name, p.num_rows
             ORDER BY size_mb DESC
        ) LOOP
            put_line(
                RPAD(NVL(part_rec.partition_name, '-'), 30) ||
                LPAD(fmt_num(part_rec.size_mb, '999,999,999.00'), 15) ||
                LPAD(fmt_num(part_rec.size_gb, '999,999,999.00'), 15) ||
                LPAD(fmt_num(part_rec.size_tb, '999,999,999.0000'), 15) ||
                LPAD(fmt_num(part_rec.num_rows, '999,999,999,999'), 15)
            );
        END LOOP;

        put_rule(60);
    EXCEPTION
        WHEN OTHERS THEN
            put_line('Error in report_table_size: ' || SQLERRM);
    END report_table_size;

    ------------------------------------------------------------------
    -- Report table storage map
    ------------------------------------------------------------------
    PROCEDURE report_table_storage_map (
        p_table_name IN VARCHAR2
    ) IS
        v_table_name VARCHAR2(128) := UPPER(p_table_name);
        v_found      BOOLEAN := FALSE;

        FUNCTION short_file(p_file VARCHAR2) RETURN VARCHAR2 IS
        BEGIN
            RETURN CASE
                WHEN LENGTH(p_file) > 60 THEN '...' || SUBSTR(p_file, -57)
                ELSE p_file
            END;
        END;
    BEGIN
        IF NOT table_exists(v_table_name) THEN
            put_line('No table found for ' || USER || '.' || v_table_name);
            RETURN;
        END IF;

        put_rule(60);
        put_line('TABLE STORAGE MAP');
        put_line('Schema : ' || USER);
        put_line('Table  : ' || v_table_name);
        put_rule(60);

        put_line(
            RPAD('LEVEL',12) ||
            RPAD('PARTITION',18) ||
            RPAD('TABLESPACE',20) ||
            RPAD('DATAFILE',60) ||
            LPAD('SIZE_MB',12) ||
            LPAD('TS_MB',12)
        );

        put_rule(134);

        FOR r IN (
            WITH ts_total AS (
                SELECT tablespace_name, SUM(bytes) total_bytes
                FROM user_segments
                GROUP BY tablespace_name
            )
            SELECT
                x.storage_level,
                x.partition_name,
                x.tablespace_name,
                df.file_name,
                ROUND(x.bytes/1024/1024,2) size_mb,
                ROUND(ts.total_bytes/1024/1024,2) ts_mb
            FROM (
                SELECT segment_name table_name,
                       'PARTITION' storage_level,
                       partition_name,
                       tablespace_name,
                       bytes
                FROM user_segments
                WHERE segment_type = 'TABLE PARTITION'
            ) x
            LEFT JOIN ts_total ts
              ON ts.tablespace_name = x.tablespace_name
            LEFT JOIN sys.dba_data_files df
              ON df.tablespace_name = x.tablespace_name
            WHERE x.table_name = v_table_name
            ORDER BY partition_name
        ) LOOP
            v_found := TRUE;

            put_line(
                RPAD(r.storage_level,12) ||
                RPAD(NVL(r.partition_name,'-'),18) ||
                RPAD(r.tablespace_name,20) ||
                RPAD(short_file(r.file_name),60) ||
                LPAD(fmt_num(r.size_mb,'999,999,990.0'),12) ||
                LPAD(fmt_num(r.ts_mb,'999,999,990.0'),12)
            );
        END LOOP;

        IF NOT v_found THEN
            put_line('No storage rows found.');
        END IF;
    END;

    ------------------------------------------------------------------
    -- Report JSON collections
    ------------------------------------------------------------------
    PROCEDURE report_json_collections (
        p_collection_name IN VARCHAR2 DEFAULT NULL,
        p_live_count      IN BOOLEAN  DEFAULT FALSE
    ) IS
        v_collection_name   VARCHAR2(128) := UPPER(TRIM(p_collection_name));
        v_found             BOOLEAN := FALSE;
        v_row_count         NUMBER;
        v_count_sql         VARCHAR2(1000);
    BEGIN
        put_line;
        put_line('JSON COLLECTION TABLES');
        IF v_collection_name IS NOT NULL THEN
            put_line('Filter          : ' || v_collection_name);
        ELSE
            put_line('Filter          : ALL');
        END IF;
        put_line('Row count mode  : ' ||
                 CASE WHEN p_live_count THEN 'LIVE COUNT(*)'
                      ELSE 'USER_TABLES.NUM_ROWS'
                 END);

        put_line(
            RPAD('COLLECTION_NAME', 32) ||
            RPAD('WITH_ETAG', 12) ||
            RPAD('TABLESPACE_NAME', 24) ||
            LPAD('USED_MB', 14) ||
            LPAD('USED_GB', 14) ||
            LPAD('USED_TB', 14) ||
            LPAD('ROW_COUNT', 14)
        );
        put_rule(124);

        FOR r IN (
            SELECT
                j.collection_name,
                NVL(j.with_etag, 'NO') AS with_etag,
                s.tablespace_name,
                ROUND(NVL(SUM(s.bytes), 0) / 1024 / 1024, 2) AS used_mb,
                ROUND(NVL(SUM(s.bytes), 0) / 1024 / 1024 / 1024, 2) AS used_gb,
                ROUND(NVL(SUM(s.bytes), 0) / 1024 / 1024 / 1024 / 1024, 4) AS used_tb,
                NVL(t.num_rows, 0) AS stats_row_count
            FROM user_json_collection_tables j
            LEFT JOIN user_segments s
                ON s.segment_name = j.collection_name
               AND s.segment_type IN ('TABLE', 'TABLE PARTITION', 'TABLE SUBPARTITION')
            LEFT JOIN user_tables t
                ON t.table_name = j.collection_name
            WHERE v_collection_name IS NULL
               OR j.collection_name = v_collection_name
            GROUP BY
                j.collection_name,
                j.with_etag,
                s.tablespace_name,
                t.num_rows
            ORDER BY
                used_mb DESC,
                j.collection_name,
                s.tablespace_name
        ) LOOP
            v_found := TRUE;

            IF p_live_count THEN
                BEGIN
                    v_count_sql :=
                        'SELECT COUNT(*) FROM "' ||
                        REPLACE(r.collection_name, '"', '""') || '"';

                    EXECUTE IMMEDIATE v_count_sql INTO v_row_count;
                EXCEPTION
                    WHEN OTHERS THEN
                        v_row_count := NULL;
                END;
            ELSE
                v_row_count := r.stats_row_count;
            END IF;

            put_line(
                RPAD(r.collection_name, 32) ||
                RPAD(r.with_etag, 12) ||
                RPAD(NVL(r.tablespace_name, '-'), 24) ||
                LPAD(fmt_num(r.used_mb, '999,999,990.00'), 14) ||
                LPAD(fmt_num(r.used_gb, '999,999,990.00'), 14) ||
                LPAD(fmt_num(r.used_tb, '999,999,990.0000'), 14) ||
                LPAD(
                    CASE
                        WHEN v_row_count IS NULL THEN 'ERROR'
                        ELSE fmt_num(v_row_count, '999,999,999,999')
                    END,
                    14
                )
            );
        END LOOP;

        IF NOT v_found THEN
            IF v_collection_name IS NULL THEN
                put_line('No JSON collection tables found in schema ' || USER);
            ELSE
                put_line('No JSON collection table found for ' || USER || '.' || v_collection_name);
            END IF;
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            put_line('Error in report_json_collections: ' || SQLERRM);
    END report_json_collections;

        ------------------------------------------------------------------
    -- Report distinct tablespaces and datafiles for a table
    ------------------------------------------------------------------
    PROCEDURE report_table_datafiles (
        p_table_name IN VARCHAR2
    ) IS
        v_table_name VARCHAR2(128) := UPPER(p_table_name);
        v_found      BOOLEAN := FALSE;

        FUNCTION short_file(p_file VARCHAR2) RETURN VARCHAR2 IS
        BEGIN
            RETURN CASE
                WHEN LENGTH(p_file) > 60 THEN '...' || SUBSTR(p_file, -57)
                ELSE p_file
            END;
        END;
    BEGIN
        IF NOT table_exists(v_table_name) THEN
            put_line('No table found for ' || USER || '.' || v_table_name);
            RETURN;
        END IF;

        put_rule(60);
        put_line('TABLE DATAFILES');
        put_line('Schema : ' || USER);
        put_line('Table  : ' || v_table_name);
        put_rule(60);

        put_line(
            RPAD('TABLESPACE_NAME',24) ||
            RPAD('FILE_NAME',60) ||
            LPAD('FILE_MB',12) ||
            LPAD('FILE_GB',12) ||
            LPAD('FILE_TB',12)
        );

        put_rule(120);

        FOR r IN (
            WITH ts AS (
                SELECT DISTINCT tablespace_name
                FROM user_segments
                WHERE segment_name = v_table_name
                  AND segment_type IN ('TABLE','TABLE PARTITION','TABLE SUBPARTITION')
            )
            SELECT
                ts.tablespace_name,
                df.file_name,
                ROUND(df.bytes/1024/1024,2) AS file_mb,
                ROUND(df.bytes/1024/1024/1024,2) AS file_gb,
                ROUND(df.bytes/1024/1024/1024/1024,4) AS file_tb
            FROM ts
            JOIN sys.dba_data_files df
              ON df.tablespace_name = ts.tablespace_name
            ORDER BY ts.tablespace_name, df.file_name
        ) LOOP
            v_found := TRUE;

            put_line(
                RPAD(r.tablespace_name,24) ||
                RPAD(short_file(r.file_name),60) ||
                LPAD(fmt_num(r.file_mb,'999,999,990.0'),12) ||
                LPAD(fmt_num(r.file_gb,'999,999,990.0'),12) ||
                LPAD(fmt_num(r.file_tb,'999,999,990.0'),12)
            );
        END LOOP;

        IF NOT v_found THEN
            put_line('No datafiles found.');
        END IF;

    EXCEPTION
        WHEN OTHERS THEN
            put_line('DBA_DATA_FILES not accessible.');
    END;


END space_report_pkg;
/


/* 

Run examples

*/
set serveroutput on;
exec space_report_pkg.report_schema_space;
exec space_report_pkg.report_table_size('foobar');
exec space_report_pkg.report_table_storage_map('foobar');
exec space_report_pkg.report_json_collections;


/* Implement heat map for confirming object access for legacy applications

author: Matt DeMarco (matthew.demarco@oracle.com)

Other notes here...

*/

-- Enable & confirm heat_map
SET SERVEROUTPUT ON SIZE UNLIMITED;
ALTER SYSTEM SET HEAT_MAP = ON SCOPE = BOTH;
SHOW PARAMETER heat_map;

-- Start a 'fresh' tracking window
EXEC dbms_ilm_admin.set_heat_map_start(start_date => SYSDATE - 5);

-- Ensure user has permissions to views
-- Run as DBA user
GRANT SELECT ON dba_segments TO &user;
GRANT SELECT ON dba_heat_map_segment TO &user;

-- Heat map analysis with access patterns
WITH heat_data AS (
    SELECT 
        h.owner,
        h.object_name,
        h.subobject_name,
        o.object_type,
        h.segment_write_time,
        h.segment_read_time,
        h.full_scan,
        h.lookup_scan,
        CASE 
            WHEN h.segment_read_time > SYSDATE - 7 THEN 'HOT'
            WHEN h.segment_read_time > SYSDATE - 30 THEN 'WARM'
            WHEN h.segment_read_time > SYSDATE - 90 THEN 'COOL'
            ELSE 'COLD'
        END AS temperature,
        CASE
            WHEN h.full_scan IS NOT NULL AND h.lookup_scan IS NULL THEN 'FULL_SCAN_ONLY'
            WHEN h.full_scan IS NULL AND h.lookup_scan IS NOT NULL THEN 'INDEX_ACCESS_ONLY'
            WHEN h.full_scan IS NOT NULL AND h.lookup_scan IS NOT NULL THEN 'MIXED_ACCESS'
            ELSE 'NO_ACCESS'
        END AS access_pattern
    FROM dba_heat_map_segment h
    LEFT JOIN dba_objects o 
        ON h.owner = o.owner 
        AND h.object_name = o.object_name
        AND (h.subobject_name IS NULL OR h.subobject_name = o.subobject_name)
    WHERE h.owner NOT IN ('SYS','SYSTEM','DBSNMP','XDB')
)
SELECT 
    owner,
    object_name,
    object_type,
    temperature,
    access_pattern,
    TO_CHAR(segment_read_time, 'YYYY-MM-DD HH24:MI:SS') last_read,
    TO_CHAR(segment_write_time, 'YYYY-MM-DD HH24:MI:SS') last_write,
    ROUND(SYSDATE - segment_read_time) days_since_read,
    ROUND(SYSDATE - segment_write_time) days_since_write
FROM heat_data
WHERE 1 = 1
AND 2 = 2
-- modify the owner for a specific schema for analysis
-- AND owner = &owner
AND owner = 'MATT'
ORDER BY 
    DECODE(temperature, 'HOT', 1, 'WARM', 2, 'COOL', 3, 'COLD', 4),
    object_type,
    object_name;



-- More heat map analysis for determining ILM policy
WITH table_sizes AS (
    SELECT
        owner,
        segment_name,
        partition_name,
        SUM(bytes)/1024/1024 size_mb
    FROM dba_segments
    WHERE segment_type LIKE 'TABLE%'
    -- Add your schema filter here
    AND owner = 'SOE'
    GROUP BY owner, segment_name, partition_name
),
access_info AS (
    SELECT
        h.owner,
        h.object_name,
        h.subobject_name,
        h.segment_read_time,
        h.segment_write_time,
        h.full_scan,
        h.lookup_scan,
        t.size_mb,
        CASE
            WHEN h.segment_read_time IS NULL THEN 'NEVER_ACCESSED'
            WHEN h.segment_read_time < SYSDATE - 180 THEN 'ARCHIVED_CANDIDATE'
            WHEN h.segment_read_time < SYSDATE - 90 THEN 'COMPRESS_CANDIDATE'
            WHEN h.segment_read_time < SYSDATE - 30 THEN 'MONITOR'
            ELSE 'ACTIVE'
        END AS ilm_recommendation
    FROM dba_heat_map_segment h
    JOIN table_sizes t
        ON h.owner = t.owner
        AND h.object_name = t.segment_name
        AND NVL(h.subobject_name, '-') = NVL(t.partition_name, '-')
    WHERE 1 = 1
    -- modify for your analysis
    AND h.owner = 'SOE' 
)
SELECT * FROM access_info
ORDER BY ilm_recommendation, size_mb DESC;

-- Cold access review
VAR days NUMBER;

-- modify the review starting date as needed
EXEC :days := 1;

SELECT 
    seg.owner, 
    seg.segment_name, 
    seg.partition_name,
    h.segment_read_time,
    NVL(TRUNC(SYSDATE - h.segment_read_time), 9999) AS days_since_read,
    ROUND(seg.bytes/1024/1024, 2) AS size_mb,
    CASE 
        WHEN h.segment_read_time IS NULL THEN 'NEVER_ACCESSED'
        WHEN TRUNC(SYSDATE - h.segment_read_time) > 365 THEN 'ARCHIVE_READY'
        WHEN TRUNC(SYSDATE - h.segment_read_time) > 180 THEN 'COMPRESS_HIGH'
        WHEN TRUNC(SYSDATE - h.segment_read_time) > 90 THEN 'COMPRESS_MEDIUM'
        ELSE 'KEEP_ONLINE'
    END AS storage_recommendation
FROM dba_segments seg
LEFT JOIN dba_heat_map_segment h
    ON h.owner = seg.owner
    AND h.object_name = seg.segment_name
    AND NVL(h.subobject_name, 'NULL') = NVL(seg.partition_name, 'NULL')
WHERE seg.owner = 'SOE'  -- Modify as needed for your schema to analyze
    AND seg.segment_type LIKE 'TABLE%'
    AND (h.segment_read_time IS NULL 
         OR TRUNC(h.segment_read_time) <= TRUNC(SYSDATE) - :days)
ORDER BY days_since_read DESC NULLS FIRST, size_mb DESC;



-- Additional object level activity
SELECT 
    TO_CHAR(h.track_time, 'YYYY-MM-DD HH24:MI:SS') AS access_time,
    o.owner,
    h.object_name,
    o.object_type,
    CASE 
        WHEN h.segment_write = 'YES' AND h.segment_read = 'YES' THEN 'READ/WRITE'
        WHEN h.segment_write = 'YES' THEN 'WRITE_ONLY'
        WHEN h.segment_read = 'YES' THEN 'READ_ONLY'
        ELSE 'OTHER'
    END AS access_type,
    CASE
        WHEN h.full_scan = 'YES' AND h.lookup_scan = 'YES' THEN 'MIXED'
        WHEN h.full_scan = 'YES' THEN 'FULL_SCAN'
        WHEN h.lookup_scan = 'YES' THEN 'INDEX_LOOKUP'
        ELSE 'NONE'
    END AS scan_type
FROM v$heat_map_segment h
JOIN dba_objects o 
    ON h.object_name = o.object_name
WHERE h.track_time > SYSDATE - 1
    AND o.owner NOT IN ('SYS', 'SYSTEM', 'XDB')
ORDER BY h.track_time DESC, o.owner, h.object_name;


-- Group by hour and object type
SELECT 
    TO_CHAR(h.track_time, 'YYYY-MM-DD HH24') AS access_hour,
    o.object_type,
    COUNT(DISTINCT h.object_name) AS objects_accessed,
    SUM(CASE WHEN h.segment_write = 'YES' THEN 1 ELSE 0 END) AS write_operations,
    SUM(CASE WHEN h.segment_read = 'YES' THEN 1 ELSE 0 END) AS read_operations,
    SUM(CASE WHEN h.full_scan = 'YES' THEN 1 ELSE 0 END) AS full_scans,
    SUM(CASE WHEN h.lookup_scan = 'YES' THEN 1 ELSE 0 END) AS index_lookups
FROM v$heat_map_segment h
JOIN dba_objects o 
    ON h.object_name = o.object_name
WHERE h.track_time > SYSDATE - 1
    AND o.owner NOT IN ('SYS', 'SYSTEM', 'XDB')
GROUP BY TO_CHAR(h.track_time, 'YYYY-MM-DD HH24'), o.object_type
ORDER BY access_hour DESC, object_type;


-- Frequently accessed objects with access time, owner, object name and type
SELECT 
    o.owner,
    h.object_name,
    o.object_type,
    COUNT(*) access_count,
    SUM(CASE WHEN h.segment_write = 'YES' THEN 1 ELSE 0 END) write_count,
    SUM(CASE WHEN h.segment_read = 'YES' THEN 1 ELSE 0 END) read_count,
    MAX(h.track_time) last_access
FROM v$heat_map_segment h
JOIN dba_objects o 
    ON h.object_name = o.object_name
WHERE h.track_time > SYSDATE - 7  -- Change as needed
    AND o.owner NOT IN ('SYS', 'SYSTEM', 'XDB')
GROUP BY o.owner, h.object_name, o.object_type
ORDER BY access_count DESC
FETCH FIRST 20 ROWS ONLY;


-- Access patterns by schmea
SELECT 
    owner,
    COUNT(DISTINCT object_name) total_objects,
    SUM(CASE WHEN segment_read_time > SYSDATE - 7 THEN 1 ELSE 0 END) accessed_last_week,
    SUM(CASE WHEN segment_read_time > SYSDATE - 30 THEN 1 ELSE 0 END) accessed_last_month,
    SUM(CASE WHEN segment_read_time IS NULL THEN 1 ELSE 0 END) never_accessed
FROM dba_heat_map_segment
WHERE owner NOT IN ('SYS','SYSTEM','DBSNMP','XDB')
GROUP BY owner
ORDER BY total_objects DESC;

-- Reporting package
-- Still testing so...be careful...
CREATE OR REPLACE PACKAGE heat_map_reports AS
    PROCEDURE generate_access_report(p_schema VARCHAR2, p_days NUMBER DEFAULT 30);
    PROCEDURE identify_unused_objects(p_schema VARCHAR2, p_threshold_days NUMBER DEFAULT 90);
    PROCEDURE suggest_ilm_actions(p_schema VARCHAR2);
END heat_map_reports;
/

CREATE OR REPLACE PACKAGE BODY heat_map_reports AS
    
    PROCEDURE generate_access_report(p_schema VARCHAR2, p_days NUMBER DEFAULT 30) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('=== Heat Map Access Report for ' || p_schema || ' ===');
        DBMS_OUTPUT.PUT_LINE('Period: Last ' || p_days || ' days');
        DBMS_OUTPUT.PUT_LINE('Generated: ' || TO_CHAR(SYSDATE, 'YYYY-MM-DD HH24:MI:SS'));
        DBMS_OUTPUT.PUT_LINE(CHR(10));
        
        FOR rec IN (
            SELECT 
                object_name,
                segment_read_time,
                segment_write_time,
                ROUND(SYSDATE - NVL(segment_read_time, SYSDATE-9999)) days_unread
            FROM dba_heat_map_segment
            WHERE owner = p_schema
                AND segment_read_time > SYSDATE - p_days
            ORDER BY segment_read_time DESC
        ) LOOP
            DBMS_OUTPUT.PUT_LINE(
                RPAD(rec.object_name, 30) || ' | ' ||
                'Last Read: ' || TO_CHAR(rec.segment_read_time, 'YYYY-MM-DD') || ' | ' ||
                'Days Unread: ' || rec.days_unread
            );
        END LOOP;
    END;
    
    PROCEDURE identify_unused_objects(p_schema VARCHAR2, p_threshold_days NUMBER DEFAULT 90) IS
        v_count NUMBER := 0;
    BEGIN
        DBMS_OUTPUT.PUT_LINE('=== Unused Objects Report ===');
        FOR rec IN (
            SELECT 
                object_name,
                segment_read_time,
                ROUND(bytes/1024/1024, 2) size_mb
            FROM dba_heat_map_segment h
            JOIN dba_segments s 
                ON h.owner = s.owner 
                AND h.object_name = s.segment_name
            WHERE h.owner = p_schema
                AND (h.segment_read_time IS NULL 
                     OR h.segment_read_time < SYSDATE - p_threshold_days)
            ORDER BY size_mb DESC
        ) LOOP
            v_count := v_count + 1;
            DBMS_OUTPUT.PUT_LINE(
                rec.object_name || ' (' || rec.size_mb || ' MB) - ' ||
                NVL(TO_CHAR(rec.segment_read_time, 'YYYY-MM-DD'), 'NEVER ACCESSED')
            );
        END LOOP;
        DBMS_OUTPUT.PUT_LINE('Total unused objects: ' || v_count);
    END;
    
    PROCEDURE suggest_ilm_actions(p_schema VARCHAR2) IS
    BEGIN
        DBMS_OUTPUT.PUT_LINE('=== ILM Action Recommendations ===');
        
        -- Archive candidates
        DBMS_OUTPUT.PUT_LINE(CHR(10) || '1. ARCHIVE CANDIDATES (>365 days):');
        FOR rec IN (
            SELECT object_name, ROUND(bytes/1024/1024/1024, 2) size_gb
            FROM dba_heat_map_segment h
            JOIN dba_segments s ON h.owner = s.owner AND h.object_name = s.segment_name
            WHERE h.owner = p_schema
                AND h.segment_read_time < SYSDATE - 365
                AND bytes > 1024*1024*1024 -- Only objects > 1GB modify as needed
        ) LOOP
            DBMS_OUTPUT.PUT_LINE('  - ' || rec.object_name || ' (' || rec.size_gb || ' GB)');
        END LOOP;
        
        -- Compression candidates
        DBMS_OUTPUT.PUT_LINE(CHR(10) || '2. COMPRESSION CANDIDATES (90-365 days):');
        FOR rec IN (
            SELECT object_name, ROUND(bytes/1024/1024, 2) size_mb
            FROM dba_heat_map_segment h
            JOIN dba_segments s ON h.owner = s.owner AND h.object_name = s.segment_name
            WHERE h.owner = p_schema
                AND h.segment_read_time BETWEEN SYSDATE - 365 AND SYSDATE - 90
                AND bytes > 100*1024*1024 -- Only objects > 100MB
        ) LOOP
            DBMS_OUTPUT.PUT_LINE('  - ' || rec.object_name || ' (' || rec.size_mb || ' MB)');
        END LOOP;
    END;
END heat_map_reports;
/

-- Run the heap_map_reports package with various input args
-- Basic usage for access report defaults to last 30 days
EXEC heat_map_reports.generate_access_report('MATT');

-- Custom time period, last 7 days
EXEC heat_map_reports.generate_access_report('MATT', 7);

-- For a different schema
EXEC heat_map_reports.generate_access_report('SOE', 60);

-- Identify unused objects
-- Default threshold, 90 days
EXEC heat_map_reports.identify_unused_objects('MATT');

-- Custom threshold, 180 days
EXEC heat_map_reports.identify_unused_objects('MATT', 180);

-- Check never accessed objects, use very high number
EXEC heat_map_reports.identify_unused_objects('MATT', 9999);

-- Analyze a schema for ILM actions
EXEC heat_map_reports.suggest_ilm_actions('MATT');
EXEC heat_map_reports.suggest_ilm_actions('SOE')


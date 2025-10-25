-- Create Oracle user with bare minimum permissions for working in their own schema
-- This script will prompt for username and password interactively
-- Optionally enables ORDS (Oracle REST Data Services) for the schema
-- Optionally grants access to another schema's objects

-- Prompt for username and password
-- The && creates a substitution variable that will be used throughout the script
-- ACCEPT command prompts the user for input
ACCEPT new_username CHAR PROMPT 'Enter username for new user: '
ACCEPT new_password CHAR PROMPT 'Enter password for new user: ' HIDE

-- Display what will be created
PROMPT
PROMPT Creating user &&new_username with minimum permissions...
PROMPT

-- Step 1: Create the user
CREATE USER &&new_username
IDENTIFIED BY "&new_password"
DEFAULT TABLESPACE USERS
TEMPORARY TABLESPACE TEMP
QUOTA UNLIMITED ON USERS;

-- Step 2: Grant minimum required system privileges

-- Required to connect to the database
GRANT CREATE SESSION TO &&new_username;

-- Step 3: Grant privileges to create database objects in their own schema

-- Create tables in their own schema
GRANT CREATE TABLE TO &&new_username;

-- Create views based on their own tables
GRANT CREATE VIEW TO &&new_username;

-- Create sequences for auto-incrementing values
GRANT CREATE SEQUENCE TO &&new_username;

-- Create stored procedures and functions
GRANT CREATE PROCEDURE TO &&new_username;

-- Create triggers on their own tables
GRANT CREATE TRIGGER TO &&new_username;

-- Create synonyms for database objects
GRANT CREATE SYNONYM TO &&new_username;

-- Step 4: Grant SODA_APP role for JSON document collections
-- This role enables the user to work with SODA (Simple Oracle Document Access) collections
GRANT SODA_APP TO &&new_username;

-- db_developer_role
GRANT DB_DEVELOPER_ROLE to &&new_username;

-- Display completion message
PROMPT
PROMPT User &&new_username created successfully with the following privileges:
PROMPT - CREATE SESSION (connect to database)
PROMPT - CREATE TABLE
PROMPT - CREATE VIEW
PROMPT - CREATE SEQUENCE
PROMPT - CREATE PROCEDURE
PROMPT - CREATE TRIGGER
PROMPT - CREATE SYNONYM
PROMPT - SODA_APP (JSON document collections)
PROMPT - DB_DEVELOPER_ROLE 

-- Step 5: Optionally grant access to another schema's objects
ACCEPT grant_other_schema CHAR PROMPT 'Grant SELECT, INSERT, UPDATE, DELETE on another schema''s tables? (Y/N): '
ACCEPT other_schema_name CHAR PROMPT 'Enter the schema name that &&new_username should have access to (leave blank to skip): '

SET SERVEROUTPUT ON
DECLARE
    v_grant_other VARCHAR2(1) := UPPER('&grant_other_schema');
    v_other_schema VARCHAR2(128) := UPPER('&other_schema_name');
    v_count NUMBER;
    v_sql VARCHAR2(4000);
BEGIN
    IF v_grant_other = 'Y' AND v_other_schema IS NOT NULL THEN
        -- Check if the schema exists
        SELECT COUNT(*) INTO v_count
        FROM all_users
        WHERE username = v_other_schema;
        
        IF v_count > 0 THEN
            DBMS_OUTPUT.PUT_LINE('');
            DBMS_OUTPUT.PUT_LINE('Granting SELECT, INSERT, UPDATE, DELETE on all tables in ' || v_other_schema || ' to ' || UPPER('&&new_username'));
            
            -- Grant permissions on all tables
            FOR rec IN (SELECT table_name FROM all_tables WHERE owner = v_other_schema) LOOP
                BEGIN
                    v_sql := 'GRANT SELECT, INSERT, UPDATE, DELETE ON ' || v_other_schema || '.' || rec.table_name || ' TO &&new_username';
                    EXECUTE IMMEDIATE v_sql;
                    DBMS_OUTPUT.PUT_LINE('  Granted on ' || rec.table_name);
                EXCEPTION
                    WHEN OTHERS THEN
                        DBMS_OUTPUT.PUT_LINE('  Failed to grant on ' || rec.table_name || ': ' || SQLERRM);
                END;
            END LOOP;
            
            -- Grant permissions on all views (SELECT only)
            DBMS_OUTPUT.PUT_LINE('');
            DBMS_OUTPUT.PUT_LINE('Granting SELECT on all views in ' || v_other_schema || ' to ' || UPPER('&&new_username'));
            FOR rec IN (SELECT view_name FROM all_views WHERE owner = v_other_schema) LOOP
                BEGIN
                    v_sql := 'GRANT SELECT ON ' || v_other_schema || '.' || rec.view_name || ' TO &&new_username';
                    EXECUTE IMMEDIATE v_sql;
                    DBMS_OUTPUT.PUT_LINE('  Granted on ' || rec.view_name);
                EXCEPTION
                    WHEN OTHERS THEN
                        DBMS_OUTPUT.PUT_LINE('  Failed to grant on ' || rec.view_name || ': ' || SQLERRM);
                END;
            END LOOP;
            
            DBMS_OUTPUT.PUT_LINE('');
            DBMS_OUTPUT.PUT_LINE('Note: Grants were attempted on existing objects only.');
            DBMS_OUTPUT.PUT_LINE('For future objects, consider creating a role or using default privileges.');
            
        ELSE
            DBMS_OUTPUT.PUT_LINE('');
            DBMS_OUTPUT.PUT_LINE('Schema ' || v_other_schema || ' does not exist. Skipping grants.');
        END IF;
    ELSE
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('Skipping grants to other schema objects.');
        DBMS_OUTPUT.PUT_LINE('To grant access later, use:');
        DBMS_OUTPUT.PUT_LINE('  GRANT SELECT, INSERT, UPDATE, DELETE ON schema.table_name TO ' || UPPER('&&new_username') || ';');
    END IF;
END;
/

-- Step 6: Optionally enable ORDS for the schema
ACCEPT enable_ords CHAR PROMPT 'Enable ORDS for this schema? (Y/N): '

-- Check if user wants to enable ORDS
SET SERVEROUTPUT ON
DECLARE
    v_enable_ords VARCHAR2(1) := UPPER('&enable_ords');
BEGIN
    IF v_enable_ords = 'Y' THEN
        -- Enable ORDS for the schema
        ORDS.ENABLE_SCHEMA(
            p_enabled => TRUE,
            p_schema => UPPER('&&new_username'),
            p_url_mapping_type => 'BASE_PATH',
            p_url_mapping_pattern => LOWER('&&new_username'),
            p_auto_rest_auth => FALSE
        );
        
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('ORDS has been enabled for schema ' || UPPER('&&new_username'));
        DBMS_OUTPUT.PUT_LINE('URL mapping pattern: /' || LOWER('&&new_username'));
        DBMS_OUTPUT.PUT_LINE('Auto REST authentication: DISABLED');
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('To enable REST services on specific objects, use:');
        DBMS_OUTPUT.PUT_LINE('  ORDS.ENABLE_OBJECT(p_schema => ''' || UPPER('&&new_username') || ''', p_object => ''TABLE_NAME'');');
    ELSE
        DBMS_OUTPUT.PUT_LINE('');
        DBMS_OUTPUT.PUT_LINE('ORDS not enabled for schema ' || UPPER('&&new_username'));
        DBMS_OUTPUT.PUT_LINE('To enable ORDS later, run:');
        DBMS_OUTPUT.PUT_LINE('  EXEC ORDS.ENABLE_SCHEMA(p_enabled => TRUE, p_schema => ''' || UPPER('&&new_username') || ''');');
    END IF;
END;
/

-- Try this approach
exec ords.enable_schema(p_schema=>'&&new_username');

-- Verify the granted privileges
PROMPT
PROMPT Verifying privileges for &&new_username:
SELECT grantee, privilege, admin_option 
FROM dba_sys_privs 
WHERE grantee = UPPER('&&new_username')
ORDER BY privilege;

-- Show granted roles
SELECT grantee, granted_role, admin_option, default_role
FROM   dba_role_privs
WHERE  grantee = UPPER('&new_username')
ORDER  BY granted_role;

-- Check ORDS status if enabled
COLUMN is_ords_enabled FORMAT A15
COLUMN url_pattern FORMAT A30
COLUMN ords_status FORMAT A10
SELECT 
    CASE 
        WHEN COUNT(*) > 0 THEN 'Yes'
        ELSE 'No'
    END as is_ords_enabled,
    MAX(pattern) as url_pattern,
    MAX(status) as ords_status
FROM dba_ords_schemas
WHERE parsing_schema = UPPER('&&new_username');



-- Clear substitution variables (optional cleanup)
UNDEFINE new_username
UNDEFINE new_password
UNDEFINE grant_other_schema
UNDEFINE other_schema_name
UNDEFINE enable_ords

/*
Notes:
- The ACCEPT command prompts for user input
- HIDE option masks password input for security
- && creates a substitution variable that persists throughout the script
- & references the variable value
- SODA_APP role enables working with JSON document collections (SODA API)
- Step 5 grants access to another schema's objects if requested
- ORDS.ENABLE_SCHEMA enables REST services for the entire schema
- p_auto_rest_auth => FALSE means REST endpoints will be public by default
- Individual objects still need to be REST-enabled separately
- The user can automatically SELECT, INSERT, UPDATE, DELETE on objects they create
- No access to other schemas unless explicitly granted
- UNLIMITED quota on USERS tablespace allows creating objects without space restrictions
- All privileges are granted without ADMIN OPTION (user cannot grant to others)

Roles explained:
- SODA_APP: Allows creating and managing JSON document collections using Simple Oracle Document Access (SODA)
  - Enables DBMS_SODA package access
  - Allows creation of JSON collections
  - Useful for modern application development with JSON data

- DB_DEVELOPER_ROLE: The DB_DEVELOPER_ROLE role provides an application developer with all the necessary privileges to design, implement, debug, and deploy applications on Oracle databases.
    
    
ORDS Parameters explained:
- p_enabled: TRUE enables ORDS for the schema
- p_schema: The schema name to enable
- p_url_mapping_type: 'BASE_PATH' creates a simple URL pattern
- p_url_mapping_pattern: The URL path (typically lowercase schema name)
- p_auto_rest_auth: FALSE makes REST endpoints public, TRUE requires authentication


EXEC ORDS.ENABLE_SCHEMA(p_enabled => FALSE, p_schema => 'sakila');
*/
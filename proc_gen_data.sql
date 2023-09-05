CREATE OR REPLACE PROCEDURE genData(
    p_table_name IN VARCHAR2,
    p_num_rows IN NUMBER
) IS
    v_column_name VARCHAR2(100);
    v_data_type VARCHAR2(100);
    v_sql VARCHAR2(1000);

    upper_sql VARCHAR2(1000) := 'select upper('||DBMS_ASSERT.ENQUOTE_LITERAL(p_table_name)||') from dual';

    upper_p_table_name VARCHAR2(1000);

BEGIN

	EXECUTE IMMEDIATE upper_sql into upper_p_table_name;
	
/* debugging
	DBMS_OUTPUT.PUT_LINE(p_table_name);
	DBMS_OUTPUT.PUT_LINE(upper_sql);
	DBMS_OUTPUT.PUT_LINE(upper_p_table_name);
*/

    FOR i IN 1..p_num_rows LOOP
        -- Loop through the columns of the specified table
        FOR col IN (SELECT column_name, data_type
                      FROM all_tab_columns
                     WHERE table_name = upper_p_table_name ) LOOP
            v_column_name := col.column_name;
            v_data_type := col.data_type;
            
            -- Generate random data based on data type
            IF v_data_type IN ('NUMBER', 'INTEGER', 'FLOAT') THEN
                -- Generate random number data
                v_sql := 'INSERT INTO ' || p_table_name || '(' || v_column_name || ') VALUES (' || DBMS_RANDOM.VALUE(1, 100) || ')';
            ELSIF v_data_type IN ('VARCHAR2', 'CHAR') THEN
                -- Generate random string data
                v_sql := 'INSERT INTO ' || p_table_name || '(' || v_column_name || ') VALUES (''' || DBMS_RANDOM.STRING('A', 10) || ''')';
            ELSE
                -- Handle other data types as needed
                -- Future work
                NULL;
            END IF;
            
            -- Execute the generated SQL
            -- DBMS_OUTPUT.PUT_LINE(v_sql);
            EXECUTE IMMEDIATE v_sql;
        END LOOP;
    END LOOP;
    
    COMMIT;
EXCEPTION
    WHEN OTHERS THEN
        -- Handle exceptions here
        DBMS_OUTPUT.PUT_LINE('An error occurred: ' || SQLERRM);
END;
/





CREATE OR REPLACE PROCEDURE getTblSize(p_table_name IN VARCHAR2) IS


  v_rowquery VARCHAR2(1000);
  v_rows VARCHAR2(1000);

  v_sizequery VARCHAR2(1000);
  v_size VARCHAR2(1000);

BEGIN

  v_rowquery := 'SELECT count(*) from '|| DBMS_ASSERT.NOOP(p_table_name) ;

  -- DBMS_OUTPUT.PUT_LINE(v_rowquery);

  EXECUTE IMMEDIATE v_rowquery into v_rows;
  
  DBMS_OUTPUT.PUT_LINE('Table: ' ||  p_table_name || ' has ' || v_rows || ' rows.');

  v_sizequery := 'SELECT sum(bytes)/1024/1024 MB from user_segments where segment_name=upper('|| DBMS_ASSERT.ENQUOTE_LITERAL(p_table_name) ||')';
  
  -- DBMS_OUTPUT.PUT_LINE(v_sizequery);
  
  EXECUTE IMMEDIATE v_sizequery into v_size;


  DBMS_OUTPUT.PUT_LINE('Table: '||p_table_name||' is using '||v_size||'MB of space.');


EXCEPTION
  WHEN OTHERS THEN
    -- Handle exceptions here
    DBMS_OUTPUT.PUT_LINE('An error occurred: ' || SQLERRM);
END;
/



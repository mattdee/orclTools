/* 
As sys/system
GRANT SELECT ON v_$session TO <your_user>;
*/

SELECT
    s.sid,
    s.serial#,
    s.username,
    s.machine,
    s.program,
    l.locked_mode,
    o.object_name
FROM
    v$locked_object l
    JOIN all_objects o ON l.object_id = o.object_id
    JOIN v$session s ON l.session_id = s.sid
WHERE
    o.object_name = 'SALES_DATA'
    AND o.owner = 'MATT';

CREATE OR REPLACE PROCEDURE kill_user_sessions(p_username IN VARCHAR2 DEFAULT 'MATT')
AS
  v_username VARCHAR2(128) := UPPER(p_username);
  v_count    PLS_INTEGER := 0;
BEGIN
  DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------');
  DBMS_OUTPUT.PUT_LINE('Killing all active sessions for user: ' || v_username);
  DBMS_OUTPUT.PUT_LINE('------------------------------------------------------------');

  FOR r IN (
    SELECT sid, serial#, machine, program
      FROM v$session
     WHERE username = v_username
       AND username NOT IN ('SYS', 'SYSTEM')
  )
  LOOP
    BEGIN
      EXECUTE IMMEDIATE
        'ALTER SYSTEM KILL SESSION ''' || r.sid || ',' || r.serial# || ''' IMMEDIATE';
      DBMS_OUTPUT.PUT_LINE(
        'Killed SID=' || r.sid || ', SERIAL#=' || r.serial# ||
        ', MACHINE=' || NVL(r.machine, 'N/A') ||
        ', PROGRAM=' || NVL(r.program, 'N/A')
      );
      v_count := v_count + 1;
    EXCEPTION
      WHEN OTHERS THEN
        DBMS_OUTPUT.PUT_LINE(
          'Failed to kill SID=' || r.sid || ', SERIAL#=' || r.serial# ||
          ' - ' || SQLERRM
        );
    END;
  END LOOP;

  IF v_count = 0 THEN
    DBMS_OUTPUT.PUT_LINE('No active sessions found for user: ' || v_username);
  ELSE
    DBMS_OUTPUT.PUT_LINE('Total sessions killed: ' || v_count);
  END IF;

EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Unexpected error: ' || SQLERRM);
END;
/

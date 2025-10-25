/* Create oracle function for conversion */
drop function now;
create or replace function oldnow(xwx varchar2 := null)
	return timestamp
	IS nownows timestamp;

	begin

	select systimestamp into nownows from dual;

	return(nownows);

end now;
/

/* intial version */
create or replace function now(xwx varchar2 := null)
  return varchar2
is
  nownows varchar2(50);
begin
  select to_char(systimestamp, 'yyyy-mm-dd hh24:mi:ss.ff6tzh') 
  into nownows 
  from dual;

  return nownows;
end now;
/

/* all versions */
select now() from dual;

/* 23ai version */
select now();



/* return time, date or timestamp depending on passed arg */
CREATE OR REPLACE FUNCTION now(xwx VARCHAR2 := NULL)
  RETURN TIMESTAMP WITH TIME ZONE
IS
  nownows TIMESTAMP WITH TIME ZONE;
  str_out VARCHAR2(50);
BEGIN
  IF xwx = '1' THEN
    -- Return only the time portion as string converted to timestamp
    SELECT TO_TIMESTAMP_TZ(TO_CHAR(SYSTIMESTAMP, 'HH24:MI:SS.FF6TZH'), 'HH24:MI:SS.FF6TZH')
    INTO nownows
    FROM dual;

  ELSIF xwx = '2' THEN
    -- Return only the date portion (midnight timestamp)
    SELECT TO_TIMESTAMP_TZ(TO_CHAR(SYSTIMESTAMP, 'YYYY-MM-DD') || ' 00:00:00-00:00',
                           'YYYY-MM-DD HH24:MI:SS-TZH:TZM')
    INTO nownows
    FROM dual;

  ELSE
    -- Default: return full timestamp
    SELECT SYSTIMESTAMP
    INTO nownows
    FROM dual;
  END IF;

  RETURN nownows;
END now;
/





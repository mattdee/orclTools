/* edition-based redefinition for pl/sql version control 🤷‍♂️ */


-- set the base edition
alter session set edition = ora$base;

-- set the version before making changes
create edition release_1 as child of ora$base; 

-- switch to the new version before making changes
alter session set edition = release_1; 

-- create a helper function to check your edition version
CREATE OR REPLACE FUNCTION current_edition RETURN VARCHAR2 IS
BEGIN
  RETURN SYS_CONTEXT('USERENV', 'SESSION_EDITION_NAME');
END;
/

-- check your edition
SELECT current_edition FROM dual;

-- now create your initial objects or code
create table foo(id int, somedata varchar2(100),indate timestamp default systimestamp);
create sequence seq_foo_id start with 1 increment by 1;

-- we will want to change the order in the new version
create or replace view foo_v
	as 
	select 
		somedata,indate,id 
	from
	foo;

-- we will change to align with the view ordering
create or replace trigger trg_foo_v_insert
instead of insert on foo_v
for each row
begin
  insert into foo (somedata, indate, id)
  values (:new.somedata, :new.indate, nvl(:new.id, seq_foo_id.nextval)); 
end;
/

-- create a new version before making changes
create edition release_2 as child of release_1; 

-- switch to the new version 
alter session set edition = release_2;

-- check your edition version
select sys_context('userenv','session_edition_name');

-- create a new version of the view with our 'correct' order
create or replace view foo_v
	as 
	select 
		id,somedata,indate
	from
	foo;

-- our 'new' insert trigger
create or replace trigger trg_foo_v_insert
instead of insert on foo_v
for each row
begin
  insert into foo (id, somedata, indate)
  values (nvl(:new.id, seq_foo_id.nextval),:new.somedata, :new.indate); 
end;
/

-- check our edition
SELECT current_edition FROM dual;


-- once we are happy about our change, we can promote the edition
ALTER DATABASE DEFAULT EDITION = release_2;

-- check the version hierarchy
SELECT edition_name, parent_edition_name, usable
FROM   dba_editions
ORDER  BY edition_name;

-- current hierarchy looks like this
ORA$BASE
   └── RELEASE_1
         └── RELEASE_2

-- make release_2 a child of ora$base
ALTER EDITION release_2 REPLACE CHILD OF ora$base;

-- hierarchy is now linked to ora$base
ORA$BASE
   └── RELEASE_2


-- now we can safely drop the release_1 edition
DROP EDITION release_1 CASCADE;




-- one script to promote as needed
-- ===================================================================
--  Edition Promotion Script
--  Purpose  : Promote a tested edition to become the active default
--              and clean up obsolete editions safely.
--  Author   : Matt
-- ===================================================================

-- 1. Variables (adjust to match your environment)
DEFINE new_release = 'RELEASE_2';
DEFINE previous_release = 'RELEASE_1';
DEFINE base_edition = 'ORA$BASE';

-- 2. Show current editions for visibility
COLUMN edition_name FORMAT A20
COLUMN parent_edition_name FORMAT A20
COLUMN usable FORMAT A6
SELECT edition_name, parent_edition_name, usable
FROM   dba_editions
ORDER  BY edition_name;

PROMPT
PROMPT ===============================================================
PROMPT Step 1: Re-parent & Promote Edition &&new_release
PROMPT ===============================================================

-- 3. Re-parent new edition directly under ORA$BASE
BEGIN
  EXECUTE IMMEDIATE
    'ALTER EDITION ' || '&&new_release' || ' REPLACE CHILD OF ' || '&&base_edition';
  DBMS_OUTPUT.PUT_LINE('Re-parented ' || '&&new_release' || ' under ' || '&&base_edition');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Re-parent failed or already correct: ' || SQLERRM);
END;
/

-- 4. Make the new edition the database default
BEGIN
  EXECUTE IMMEDIATE 'ALTER DATABASE DEFAULT EDITION = ' || '&&new_release';
  DBMS_OUTPUT.PUT_LINE('Database default edition set to ' || '&&new_release');
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Failed to set default edition: ' || SQLERRM);
END;
/

PROMPT
PROMPT ===============================================================
PROMPT Step 2: Drop obsolete edition &&previous_release (if safe)
PROMPT ===============================================================

-- 5. Drop the old edition if it exists
DECLARE
  v_count NUMBER;
BEGIN
  SELECT COUNT(*) INTO v_count FROM dba_editions WHERE edition_name = UPPER('&&previous_release');
  IF v_count > 0 THEN
    EXECUTE IMMEDIATE 'DROP EDITION ' || '&&previous_release' || ' CASCADE';
    DBMS_OUTPUT.PUT_LINE('Dropped old edition ' || '&&previous_release');
  ELSE
    DBMS_OUTPUT.PUT_LINE('Edition ' || '&&previous_release' || ' does not exist.');
  END IF;
EXCEPTION
  WHEN OTHERS THEN
    DBMS_OUTPUT.PUT_LINE('Could not drop old edition: ' || SQLERRM);
END;
/

PROMPT
PROMPT ===============================================================
PROMPT Step 3: Verify new default edition
PROMPT ===============================================================

SELECT property_name, property_value
FROM   database_properties
WHERE  property_name = 'DEFAULT_EDITION_NAME';

SELECT edition_name, parent_edition_name, usable
FROM   dba_editions
ORDER  BY edition_name;

PROMPT
PROMPT Promotion complete.
PROMPT ===============================================================


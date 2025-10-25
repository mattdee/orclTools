/* server side functions */
/* Mongo version 
db.system.js.insertOne(
   {
      _id: "echo",
      value : function(x) { return x; }
   }
)
*/
/* PL/SQL 23ai version, not using dual */
/* take input, return input in uppercase */
create or replace function echo_plsql(name varchar2 := null)
  return varchar2
is
  whatname varchar2(2000);
begin
  select upper(name) into whatname;
  return whatname;
end echo_plsql;
/

/* MLE with JavaScript, module then function */
/* Ensure you have permissions
GRANT CREATE MLE TO :you;
GRANT CREATE FUNCTION TO :you;
*/

create or replace mle module echo_js
language javascript
as
export function echojs(name) {
  if (name === null || name === undefined) {
    return null;
  }
	return name.toUpperCase();
}
/

create or replace function echo_js_fn(name varchar2)
return varchar2
as mle module echo_js
signature 'echojs(string)';
/

/* simple varible use in SQLPlus or SQLcl*/
VAR my_input VARCHAR2(100)
EXEC :my_input := 'Hello from SQL!'s

select echo_plsql(:my_input) as echothisplsql;
select echo_js_fn(:my_input) as echothismlejs;


/* From here we operate in mongsh */
/* define local variable and call the function */
let inputName = 'matt';
// define local variable and call the function //
db.echonames.aggregate([
  {
    $sql: `
      SELECT echo_plsql('${inputName}') 
    `
  }
]);


let inputNameList = ['matt', 'nick', 'sunil'];
db.echonames.aggregate([
  {
    $sql: `
      SELECT echo_plsql('${inputNameList}') 
    `
  }
]);
db.aggregate([
	{
		$sql: `select echo_js_fn('${inputNameList}')`
}]);


/* let's create a JSON Collection WITHOUT SQL 😵‍💫 */
db.echonames.insertMany([
{"name" : "Lance"},
{"name" : "Prakash"},
{"name" : "Virginia"},
{"name" : "Nick"},
{"name" : "Sunil"},
{"name" : "Matt"}
]);

/* take the collection as input and call the functions */
/* call plsql function */
db.echonames.aggregate([
  {
    $sql: `
      SELECT JSON_OBJECT(
        'original' VALUE JSON_VALUE(v.data, '$.name'),
        'echoed'   VALUE echo_plsql(JSON_VALUE(v.data, '$.name'))
      )
      FROM input v
    `
  }
]);

/* call the MLE JavaScript function */
db.echonames.aggregate([
  {
    $sql: `
      SELECT JSON_OBJECT(
        'original' VALUE JSON_VALUE(v.data, '$.name'),
        'echoed'   VALUE echo_js_fn(JSON_VALUE(v.data, '$.name'))
      )
      FROM input v
    `
  }
]);






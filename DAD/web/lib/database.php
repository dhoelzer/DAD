<?php
#   This file is a part of the DAD Log Aggregation and Analysis tool
#    Copyright (C) 2006, David Hoelzer/Cyber-Defense.org
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA
require_once '../config/constants.php';

/*---------------------------------------------------------------------
 * Database.php
 *
 * This library contains all of the low level calls necessary for
 * database interaction.  No other code should directly access a
 * database.  Instead, these functions act as a data abstraction
 * layer, acting as an intermediary between the web application and
 * the actual database functions.
 *---------------------------------------------------------------------
 */
// set connection constants
require_once '../config/dbconfig.php';

define('KEY_ROWNUM', 0);
define('KEY_COLUMN1', 1);
//define('MYSQL_BOTH', 1);
//define('MYSQL_ASSOC', 2);

/*
   Should we exit or return null on error?
   Exit maybe more secure but returning nulls allow the
   app to "handle" the error which is a responsibility.
 */

/*---------------------------------------------------------------------
 * closeDb($DatabaseObject)
 *---------------------------------------------------------------------
 * This function closes a currently open database connection.
 *
 */
function closeDb(&$objDb) {
   mysql_close($objDb);
}

/*---------------------------------------------------------------------
 * getConnection($address, $username, $password, $database)
 *---------------------------------------------------------------------
 * The getConnection function creates a network connection to the
 * database server, returning a database object handle.
 *
 */

function getConnection($strAddress = DB_ADDRESS, 
                       $strUsername = DB_USERNAME, 
                       $strPassword = DB_PASSWORD,
                       $strDbName = DB_NAME) {


					   #Client multi keeps producing errors.  Commented out for now.  Only needed to send
					   # multiple SQL statements in one query.  This might actually be a BAD thing!
	$objDb = mysql_connect($strAddress, $strUsername, $strPassword); #, 'CLIENT_MULTI_STATEMENTS');
   if(!$objDb) { 
      trigger_error("Error opening connection to database server at $strAddress: ".mysql_error()); 
      return null;
   }

   if($strDbName != null) {
      if(false == mysql_select_db($strDbName, $objDb)) {
         return null;
      }
   }
   return($objDb);
}

/*---------------------------------------------------------------------
 * runInsertReturnID($strSQL)
 *---------------------------------------------------------------------
 * The runInsertReturnID function will execute a SQL command as
 * specified by $strSQL and return the ID of the inserted row
 * provided that the insert runs successfully.  There is no actual
 * check to verify that the SQL statement sent to this function is
 * in fact an INSERT.  The function will return NULL on failure.
 *
 */
function runInsertReturnID($strSQL) {
   $intInsertedID = NULL;
//   logger("INFO: Inserting with '$strSQL'");
   $objDb = getConnection();
   $objResult = mysql_query($strSQL, $objDb);
   $intError = mysql_errno();
   
   if($intError!=0) {
     trigger_error("SQL error:". mysql_error()."\n$strSQL");
     return NULL;
   }
   if ($objResult) {
      $intInsertedID = mysql_insert_id($objDb);
   }

   closeDB($objDb);
   return $intInsertedID;
}

function SQLListFields($Table) 
{
	global	$Global;
	
	return(runQueryReturnArray("SHOW COLUMNS FROM $Table"));
}

/*---------------------------------------------------------------------
 * runQueryReturnArray($SQL[, KeyCode[, ReturnType]])
 *---------------------------------------------------------------------
 * The runQueryReturnArray function will execute the given SQL query
 * and return an array containing the results.  By default, the array
 * returned will be both associative and indexed.  If you wish to
 * specify only one return type, the ReturnType value can be set to
 * the appropriate value.  By default the key for the associative array
 * will be the row number, but the KeyCode argument can be used to
 * set the array key to whatever we might like.
 */
function runQueryReturnArray($strSQL, $intKeyCode=KEY_ROWNUM, $intMySQLRowType=MYSQL_BOTH) {
global	$Global;
	
    $objDb     = getConnection();
    $objResult = '';

    // split string into individual SQL statements
    $stmts = preg_split( "/;\n/", $strSQL );

    foreach( $stmts as $stmt ){

        $objResult = @mysql_query($stmt, $objDb);
        $intError = mysql_errno();

        if ($intError != 0) {
            trigger_error("SQL Error:<br />\n" . mysql_error(). "<br /><br />\n\n   SQL->$strSQL");
            $objResult=NULL;
            return NULL;
        }

    }

    $aRows = NULL;
    $aRow = NULL;
    for($i=0; $aRow = mysql_fetch_array($objResult); $i++) {
        if($intKeyCode==KEY_COLUMN1) 
		{
            $aKey = array_keys($aRow);
            $aRows[$aRow[$aKey[0]]] = $aRow;      
        } 
		elseif($intKeyCode==KEY_ROWNUM) 
		{
           $aRows[$i] = $aRow;
        }
    }

	# Build the index of column names
	for($column = 0; $column != mysql_num_fields($objResult); $column++)
		{
			$column_names[$column] = mysql_field_name($objResult, $column);
		}
	add_global("LAST_QUERY_FIELD_NAMES", $column_names);
	

    mysql_free_result($objResult); 
    closeDB($objDb);
    return $aRows;
}

/*
runs SQL statement (i.e. - DELETE, UPDATE) and returns number of rows affected or null. Should use only for INSERT, UPDATE, DELETE statements since mysql_affected_rows is only good for those statements.
*/
/*---------------------------------------------------------------------
 * runSQLReturnAffected($strSQL)
 *---------------------------------------------------------------------
 * This function will run the SQL code passed into the function
 * and return the number of rows that were affected.  This is ideal
 * for running an UPDATE or even a DELETE.  If the function is
 * unsuccessful, it will return NULL.  If the function affects zero
 * rows, zero will be returned.
 */
function runSQLReturnAffected($strSQL) {
   $intRowsAffected = NULL;

//   logger("INFO: Querying with '$strSQL'");
   $objDb = getConnection();
   $objResult = mysql_query($strSQL, $objDb);
   $intError = mysql_errno();
   
   if($intError!=0) {
     trigger_error("SQL error:". mysql_error()."\n$strSQL");
     return NULL;
   }
   if ($objResult) {
      $intRowsAffected  = mysql_affected_rows($objDb);
   }

   closeDB($objDb);
   return $intRowsAffected;
}

//This function brought over from Saul's code
/*------------------------------------------------------------------------------
 * boolean replaceEmptyWithZeroes(&$value)
 *------------------------------------------------------------------------------
 * This function checks $value to see if it is empty.  If it is, a zero is
 * placed in the variable and false is returned.  If it isn't empty, the
 * value is left unchanged and true is returned.
 */
function replaceEmptyWithZeros(&$value) {
   $orig = $value;
   $value = !$value? 0: $value;  
   
   return $orig == $value? true: false;
}

?>

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

/*
 * Sessions library
 * 6/21/05
 *
 */
 
/* function PopulateUserGlobals()
 *
 * Gets user data from database and places it into $Global.
 * Relies on $Global['UserID'].
 *
 */
function PopulateUserGlobals () 
{    
  global $Global;

   if(!$Global["ValidSession"])
   {
     return;
   }
   $CurrentUserID = (isset($Global['UserID']) ? $Global['UserID'] : 0);
   $strSQL = "SELECT u.UserID,l.LanguageCode, l.LanguageName, u.UserName
                FROM User u, Language l
                WHERE u.UserID = '$CurrentUserID' AND u.LanguageID = l.LanguageID";
   
   $aResults = runQueryReturnArray($strSQL);
   
   $intUserID = NULL; 
   if(count($aResults==1)) {
      add_global("LanguageCode", $aResults[0]["LanguageCode"]);
  	  add_global("LanguageName", $aResults[0]["LanguageName"]);
      add_global("txtUserName", $aResults[0]["UserName"]);
   }
}

/* 
 * delSessionForUserID($intUserID)
 * Deletes all session rows for the specified user.
 *
*/ 
function delSessionForUserID($intUserID) {

  $strSQL = "DELETE FROM Session
              WHERE UserID=$intUserID";
              
  $intRowsAffected = runSQLReturnAffected($strSQL);

  if ($intRowsAffected > 1) {
    trigger_error(ERR_NOSCREEN_TAG.ERR_SECURITY_ALERT."$intRowsAffected row(s) deleted in Session for UserID: $strUserID",
                  E_USER_WARNING);
  }
  return $intRowsAffected;
}
/*
function destroySession($strSessionAuthenticator) {
   $intSessionID = GetAuthenticatorSessionID($strSessionAuthenticator);
   $intRowsAffected = delSessionForSessionID($intSessionID);
  
   return $intRowsAffected == 1? true : false;
}
*/

/*
 * genRandomString($intLength)
 *
 * Generates a random string of the specified length which is used as the session key.
 * Returns a string.
*/ 

function genRandomString($intLength) {
   $strValidChars="abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789\$~.|_";
   // Someday we'll do something better for the randomizer.  This should be sufficient for now.
   srand(rand(rand(1,314157911),time()));
   $intFieldSize = strlen($strValidChars) - 1;
  
   for($i = 0; $i < $intLength; $i++) {
     $aSessKey[$i] = $strValidChars[(rand(0, $intFieldSize))];
   }
   $strSessionKey = join($aSessKey, "");
   return ($strSessionKey);
}

/* getUserSession($strSessionID) 
 * Gets session row for the specified session ID and returns results array.
*/
function getUserSession ($strSessionID) {
  $strSQL="SELECT SessionID,
                  UserID,
                  IPAddress,
                  ExpireTime
             FROM Session
            WHERE SessionID = '" . $strSessionID . "'";

  $aResults=RunQueryReturnArray($strSQL, KEY_COLUMN1, MYSQL_ASSOC);
  return $aResults;
}

/* insSession($intUserID, $strSessionKey, $dtmExpireDatetime)
 *
 * Inserts a session row into the database. Returns the inserted session ID.
 */ 
function insSession($intUserID) {

   $strIPAddress = $_SERVER["REMOTE_ADDR"];
   $strSessionID = genRandomString(64);
   $numExpireTime = gmmktime() + SESSION_DURATION; 

   $strSQL = "INSERT INTO Session (SessionID, UserID, IPAddress, ExpireTime)
          VALUES ('$strSessionID', $intUserID, '$strIPAddress', $numExpireTime)";
   $intRowsAffected = runSQLReturnAffected($strSQL);
 
   if ($intRowsAffected > 0) {
      add_global("ValidSession", true);
      add_global("SessionID", $strSessionID);
      return $strSessionID;
   } else {
      add_global("ValidSession", false);
      add_global("SessionID", "");
      trigger_error(ERR_NOSCREEN_TAG.ERR_SYSTEM_LOG."Unable to create session ID row for user ID: $intUserID");   
      return NULL;
   }   
}

/* updSession($intUserID, $strSessionKey, $dtmExpireDatetime)
 *
 * Updates session row with new expire time. Returns rows affected.
 */ 
function updSession($strSessionID, $numNewExpireTime) {

   $strSQL = "UPDATE Session
                 SET ExpireTime = $numNewExpireTime
               WHERE SessionID = '" . $strSessionID . "'";
   
   $intRowsAffected = runSQLReturnAffected($strSQL);
   return($intRowsAffected);
}

/* validateSessionID($strSessionID)
 * Validates the session authenticator by comparing it's value with the key values stored 
 * in the session table for the logged on user. In addition, it ensures the session has
 * not expired.  Returns boolean.
*/
function validateSessionID($strSessionID) {

   global $Global;
   $aSession = getUserSession($strSessionID);
   $intReturn = RETURN_FAILURE;
   $strCurrentIPAddress = $_SERVER["REMOTE_ADDR"];   
   
   switch (count($aSession)) { 
   
      case 0:
         // session does not exist in database
         $intReturn = RETURN_FAILURE;
         trigger_error(ERR_NOSCREEN_TAG.ERR_SECURITY_LOG."Invalid session ID: $strSessionID");
         break;

      case 1:
         // potentially valid session here
         if ($strCurrentIPAddress != $aSession[$strSessionID]["IPAddress"]) {
            trigger_error(ERR_NOSCREEN_TAG.ERR_SECURITY_LOG."IP Address for current user no longer matches session: $strSessionID");
            break;
         }
         // Check if session has expired.
         if (gmmktime() > $aSession[$strSessionID]["ExpireTime"]) {
            trigger_error(ERR_NOSCREEN_TAG.ERR_SECURITY_LOG."Session Expired");
         } else {
            add_global($aSession[$strSessionID]);
            add_global("ValidSession", true);
            
            // Update expire time to now + session duration
            $intRowsAffected = updSession($strSessionID, (gmmktime() + SESSION_DURATION));
            $intReturn = RETURN_SUCCESS;
         }
         break;
         
      default: 
         // more than 1 session row - trigger error, delete all for this user and return
         trigger_error(ERR_NOSCREEN_TAG.ERR_SECURITY_LOG."Multiple sessions exist for user ID: {$Global['UserID']}");
         delSessionForUserID($Global["UserID"]);
   }
   
   if ($intReturn == RETURN_FAILURE) {
      add_global("ValidSession", false);
   }
   
   return $intReturn;
}

/* 
 * loginUser($strDomainLoginName, $strUserName, $strPassword)
 *
 * Validates user logon info. If valid, generates a 64 byte random session key and places
 * session row into the database. In addition, it deletes all old sessions for this user. 
 * Returns session key.
 */

function IsPasswordComplex( $Password, $Silent=0 )
{
  $criteria_met = 0;
  $upper_lower = false;
  $numeric = false;
  $alpha = false;
  $punctuation = false;
  $length = false;
  $dictionary = false;
  
  $pass_lower = strtolower($Password);
  if($pass_lower !== $Password) { $upper_lower = true; $criteria_met++;}
  $pass_array = preg_split("//", $pass_lower);
  foreach($pass_array as $char)
  {
    if(is_numeric($char)) { $numeric = true; }
  }
  if($numeric) { $criteria_met++; }
  $words = file("../lib/dictionary");
  $word_string = join(" ", $words);
  $words = strtolower($word_string);
  $words = preg_replace("/[^a-z]/", "", $word_string);
  $pass = preg_replace("/[^a-z]/", "", $pass_lower);
  $pos = strpos($words, $pass);
  if($pos === false) { $dictionary = true; $criteria_met++;}
  $password = preg_replace("/[^a-zA-Z0-9]/", "", $Password);
  if($password !== $Password) { $punctuation = true; $criteria_met++;}
  if(strlen($Password) > 7) { $length = true; }

  if( ((! $Silent) && ($criteria_met < 3)) | (! $length) ){
      if(!$dictionary) { add_element("Password must not be based on a dictionary word.<BR>"); }
      if(!$upper_lower) { add_element("Password must use upper and lower case.<BR>"); }
      if(!$numeric){ add_element("Passwords must contain letters and numbers.<BR>"); }
      if(!$punctuation) { add_element("Passwords must contain at least one special character.<BR>"); }
      if(!$length) { add_element("Passwords must be at least eight characters long.<BR>"); }
      add_element("<HR>");
  }
  return(($criteria_met > 2) && $length);
}
?>
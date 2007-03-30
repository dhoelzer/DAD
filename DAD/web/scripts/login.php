<?php
/* showLoginPage()
 *
 * Constructs the HTML form for the login page and calls the add_element function.
 *
*/
function showLoginPage() {

   global $gaLiterals;

   $strFormHTML = "<form id=\"frmLogin\" action=\"${_SERVER['PHP_SELF']}?" . ARG_OPTION . "=" . OPTIONID_LOGINUSER . "\" method=\"post\" style=\"position:relative; top:25px;\">
            <table>
               <tr>
                  <td colspan=\"2\"><h2>${gaLiterals['Log In']}</h2></td>
               </tr>
               <tr>
                  <td>${gaLiterals['User Name']}:</td>
                  <td><input id=\"txtLoginName\" type=\"text\" maxlength=\"10\" name=\"txtUserName\" value=''></td>
               </tr>
               <tr>
                  <td>${gaLiterals['Password']}:</td>
                  <td><input type=\"password\" maxlength=\"45\" name=\"txtPassword\" value='' ></td>
               </tr>
               <tr>
                  <td><input type=\"submit\" name=\"btnSubmit\" value=\"submit\"></td>
                  </td>
               </tr>
            </table>               
            </form>";

   add_element($strFormHTML);
}

/* loginUser()
 *
 * If the domain login name, user name and password are valid, this function deletes all old session
 * rows for this user and then inserts a new session row.  In addition, login count and date are updated 
 * in the user stats table, and then the user is re-directed to the home page.  If the login information
 * is not valid, the loginFailed() function is called.
 *
*/
function loginUser() {

   global $Global;
   
   // Get post variables from $Globals array
   $strUserName = isset($Global["txtUserName"]) ? $Global["txtUserName"] : NULL;
   $strPassword = isset($Global["txtPassword"]) ? $Global["txtPassword"] : NULL;

   // Is this a valid user?
   $intUserID = getUser($strUserName, $strPassword);

   if (empty($intUserID)) {
      logger("SEC: Failed login attempt for $strUserName in domain $strDomainLoginName");
      loginFailed();
      return;
   }
   
   // If valid, first delete all old sessions for this user
   delSessionForUserID($intUserID);
   $strSessionID = insSession($intUserID);
   
   // Update user stats table
   updUserStats($intUserID);

   // If session was created, go directly to home page
   if ($Global["ValidSession"] == true) {
      dispatch(OPTIONID_HOME);
   } else {
      logger("SEC: Failed to create session during login.  $strUserName in domain $strDomainLoginName");
      loginFailed();
   }
   return;
}

/* loginFailed() 
 * 
 * This function is called from logonUser when the login attempt fails.  It calls the showLogonPage function to 
 * construct the login page, and also adds an element to display a failure message to the user.
 *
*/
function loginFailed() {

   global $Global;
   
   // This needs to change to come from language messages.
   showLoginPage();
   add_element('<p style="color:red">Login failed. Please try again.</p>');
}
/* getUser($strDomainLoginName, $strUserName, $strPassword) 
 *
 * Gets user data from database and returns in an associative array. 
 * This will probably change to get more data than just user ID.
 *
*/
function getUser ($strUserName, $strPassword) {    

   $strSQL = "SELECT u.UserID
                FROM User u
               WHERE u.Username = '$strUserName'
                 AND u.PasswordText = sha('$strPassword')
                 AND u.DeletedDatetime < 1"; 
       // Previous line referring to deleted datetime probably needs to change...
   
   $aResults = runQueryReturnArray($strSQL);
   
   $intUserID = NULL; 
   if(count($aResults==1)) {
      $intUserID = $aResults[0]["UserID"];
      // Add current option to globals array
      add_global("UserID", $intUserID);
   }
   return $intUserID;
}
/* updUserStats($intUserID)
 * Updates the LoginCount and LatestLoginStamp fields in the UserStats table for this user ID.
 * 
*/
function updUserStats($intUserID) {

   $strSQL = "UPDATE UserStat 
                 SET LoginCount = LoginCount + 1
               WHERE UserID = $intUserID";

   $intRowsAffected = runSQLReturnAffected($strSQL);
   if ($intRowsAffected < 1) {
      // Perhaps no row exists for this user yet - do an insert instead...
      $strSQL = "INSERT INTO UserStat (UserStatID, UserID, LoginCount) 
                      VALUES (null, $intUserID, 1)";
      $intRowsAffected = runSQLReturnAffected($strSQL);
      if ($intRowsAffected < 1) {
         trigger_error(ERR_NOSCREEN_TAG.ERR_SYSTEM_LOG."Unable to insert UserStat row for user ID: $intUserID");
      }
   }
   return;
}

/*-------------------------------------------------------------------------
 * LogoutUser()
 *-------------------------------------------------------------------------
 * Login and logout are in the same module.  Logout simply destroys
 * the existing session (if there is one) and dispatches the login
 * page.
 */
function LogoutUser()
{
  global $Global;
  
  if(!$Global["ValidSession"])
  {
    logger("ERROR: Tried to call logout function with no valid session.");
    dispatch(OPTION_LOGINPAGE);
    return;
  }
  if(!$Global["UserID"])
  {
    logger("ERROR: Tried to call logout function with no global user id.");
    dispatch(OPTIONID_LOGINPAGE);
    return;
  }
  delSessionForUserID($Global["UserID"]);
  $Global["UserID"] = NULL;
  $Global["SessionID"] = NULL;
  $Global["ValidSession"] = 0;
  dispatch(OPTIONID_LOGOUT);
  return;
}
?>
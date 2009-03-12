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

function CreateUserForm() {

    global $gaLiterals;
    global $Global;

    if( checkOptionPermission( $Global['UserID'], $Global['OptionID'] ) == 0 ){
        dispatch( OPTIONID_LOGOUT );
        return;
    }

    $strURL  = getOptionURL(OPTIONID_CREATEUSERFORM);

    $arrVals = array( 
                 'username'  => array( isset( $Global['username'] ) ? $Global['username'] : '' ),
                 'firstname' => array( isset( $Global['firstname'] ) ? $Global['firstname'] : '' ),
                 'lastname'  => array( isset( $Global['lastname'] ) ? $Global['lastname'] : '' ),
                 'email'     => array( isset( $Global['email'] ) ? $Global['email'] : '' ),
                 'language'  => array( isset( $Global['language'] ) ? $Global['language'] : '' ),
                 'role'      => array( isset( $Global['role'] ) ? $Global['role'] : '' )
               );

    //if the Create button was click, will do the following code
    if( isset( $Global['bt'] ) && $Global['bt'] === $gaLiterals['Create'] ) {

        $flgBad = '';

        //check username
        if( !isset( $Global['username'] ) || $Global['username'] == '' ) {
            $arrVals['username'][1] = $gaLiterals{'Required'};
            $flgBad = 1;
        } else {
            $tmp = runQueryReturnArray( "SELECT UserID FROM user WHERE UserName = '${Global['username']}'" );
            if( $tmp ) {
                //username already in use
                $flgBad = 1;
                $arrVals['username'][1] = $gaLiterals{'Already Exists'};
            } else if( strlen( $Global['username'] > 20 ) ) {
                $flgBad = 1;
                $arrVals['username'][1] = $gaLiterals{'Max20Chars'};
            } else {
                $arrVals['username'][1] = '';
            }
        }

        //check if first and last name exists; unique full name not required
        if( !isset( $Global['firstname'] ) || $Global['firstname'] == '' ) {
            $arrVals['firstname'][1] = $gaLiterals{'Required'};
            $flgBad = 1;
        }
        if( !isset( $Global['lastname'] ) || $Global['lastname'] === '' ) {
            $arrVals['lastname'][1] = $gaLiterals{'Required'};
            $flgBad = 1;
        }


        //email address not required

        //check language
        if( $Global['language'] == '' ){
            $arrVals['language'][1] = $gaLiterals{'Required'};
            $flgBad = 1;
        } else {
            $arrVals['language'][1] = '';
        }

        //check role
        if( $Global['role'] == '' ){
            $arrVals['role'][1] = $gaLiterals{'Required'};
            $flgBad = 1;
        } else {
            $arrVals['role'][1] = '';
        }

        //fetch a new password
        while( 1 ) {
            $strPass = genRandomString( 10 );
            if( IsPasswordComplex( $strPass, 1 ) ) {
                break;
            }
        }

        //if all the above checks pass, will go ahead and create the user
        if( $flgBad != 1 ){

            $strSQL = "INSERT INTO User( 
                     UserName, 
                     PasswordText, 
                     FirstName, 
                     LastName, 
                     EmailAddress, 
                     LanguageID, 
                     CreatedDatetime, 
                     LatestChangeUserID, 
                     LatestChangeStamp ) 
                   VALUES (
                     '${Global['username']}',
                     sha( '" . $strPass . "' ),
                     '${Global['firstname']}',
                     '${Global['lastname']}',
                     '${Global['email']}',
                     '${Global['language']}',
                     NOW(),
                     ( SELECT UserID FROM session WHERE SessionID = '${Global['SessionID']}' ),
                     NOW()
                   );";

            $strUserID  =  runInsertReturnID( $strSQL );

            $strSQL = "INSERT INTO UserRole( UserID, RoleID ) VALUES ( '$strUserID', '${Global['role']}' );";
            $strAff =  runSQLReturnAffected( $strSQL );

            //LOGGING
            logger( "USER CREATION SUCCESS: UserID: $strUserID; UserName: ${Global['username']}; FirstName: ${Global['firstname']}'; LastName: ${Global['lastname']}; Email: ${Global['email']}; RoleID: ${Global['role']}; " );

        }

    }

    $strSQL  = "SELECT LanguageID, LanguageName FROM language ORDER BY LanguageName ASC";
    $arrLang = runQueryReturnArray( $strSQL );

    $strSQL  = "SELECT RoleID, RoleDescr FROM role ORDER BY RoleDescr ASC";
    $arrRole = runQueryReturnArray( $strSQL );

    $strHTML =  "<b><font size=2>${gaLiterals['Create New User']}</font></b><br><br>";

    $strHTML .="
      <form id='createuserform' action='$strURL' method='post'>\n
        <table>
          <tr>
            <td>
              ${gaLiterals['User Name']}
            </td>
            <td>
              <input type='text' width='25' maxlength='20' name='username' value='" . (isset( $Global['username'] ) ? $Global['username'] : '') . "'>
            </td>
            <td><font color=red>";

    $strHTML .= ( isset( $arrVals['username'][1] ) ? $arrVals['username'][1] : '' );

    $strHTML .= "</font></td>
          </tr>
          <tr>
            <td>
              ${gaLiterals['First Name']}
            </td>
            <td>
              <input type='text' width='30' name='firstname' value='" . (isset( $Global['firstname'] ) ? $Global['firstname'] : '') . "'>
            </td>
            <td><font color=red>";

    $strHTML .= ( isset( $arrVals['firstname'][1] ) ? $arrVals['firstname'][1] : '' );

    $strHTML .= "</font></td>
          </tr>
          <tr>
            <td>
              ${gaLiterals['Last Name']}
            </td>
            <td>
              <input type='text' width='30' name='lastname' value='" . (isset( $Global['lastname'] ) ? $Global['lastname'] : '') . "'>
            </td>
            <td><font color=red>";

    $strHTML .= ( isset( $arrVals['lastname'][1] ) ? $arrVals['lastname'][1] : '' );

    $strHTML .= "</font></td>
          </tr>
          <tr>
            <td>
              ${gaLiterals['Email Address']}
            </td>
            <td>
              <input type='text' width='30' name='email' value='" . (isset( $Global['email'] ) ? $Global['email'] : '') . "'>
            </td>
            <td><font color=red>";

    $strHTML .= ( isset( $arrVals['email'][1] ) ? $arrVals['email'][1] : '' );

    $strHTML .= "</font></td>
          </tr>
          <tr>
            <td>
              ${gaLiterals['Language']}
            </td>
            <td>
              <select name='language'>
              <option></option>";

    foreach( $arrLang as $lang ){
        $strHTML .= "<OPTION VALUE=${lang['LanguageID']}";

        if( isset( $Global['language'] ) && $lang['LanguageID'] == $Global['language'] ) {
            $strHTML .= ' SELECTED>';
        } else {
            $strHTML .= '>';
        }

        $strHTML .= "${lang['LanguageName']}</OPTION>";
    }

    $strHTML .="</select></td>
            <td><font color=red>";

    $strHTML .= ( isset( $arrVals['language'][1] ) ? $arrVals['language'][1] : '' );

    $strHTML .= "</font></td>
          </tr>
          <tr>
            <td>
              ${gaLiterals['Role']}
            </td>
            <td>
              <select name='role'>
              <option></option>";

    foreach( $arrRole as $role ){

        $strHTML .= "<OPTION VALUE=${role['RoleID']}";

        if( isset( $Global['role'] ) && $role['RoleID'] == $Global['role'] ) {
            $strHTML .= ' SELECTED>';
        } else {
            $strHTML .= '>';
        }

        $strHTML .= "${role['RoleDescr']}</OPTION>";
    }

    $strHTML .= "</select></td>
            <td><font color=red>";

    $strHTML .= ( isset( $arrVals['role'][1] ) ? $arrVals['role'][1] : '' );

    $strHTML .= "</font></td>
          </tr>
        </table>
        <input type='submit' name='bt' id='bt' value='${gaLiterals['Create']}'>
      </form>";


    if( isset($strAff) ) {
        $strHTML .= "<br><br><b>${Global['username']}</b> ${gaLiterals['successfully created']}.\n ${gaLiterals['New Password']}: <b>$strPass</b>";
    }

    add_element( $strHTML );

}


function DeleteUserForm() {

    global $gaLiterals;
    global $Global;

    if( checkOptionPermission( $Global['UserID'], $Global['OptionID'] ) == 0 ) {
        dispatch( OPTIONID_LOGOUT );
        return;
    }

    $strURL   = getOptionURL(OPTIONID_DELETEUSERFORM);

    //if Delete button was clicked
    if( isset( $Global['bt'] ) && $Global['bt'] === $gaLiterals['Delete'] ) {

        //check to see if you're trying to delete yourself
        if( $Global['UserID'] == $Global['deleteuserid'] ){

            $strMsg = "<b><font color='red'>${gaLiterals['DelSelf']}</font></b>";
            logger( "USER DELETION FAILURE: User tried to delete himself" );

        } else if( $Global['deleteuserid'] == 1 ) {

            $strMsg = "<b><font color='red'>${gaLiterals['DelAdmin']}</font></b>";
            logger( "USER DELETION FAILURE: User tried to delete the administrator account" );

        } else {

            //we do left joins just incase a role or language was deleted, but the user was never update... will still beable to interact with the account
            $strSQL = "SELECT u.UserName, u.FirstName, u.LastName, u.EmailAddress, l.LanguageName, r.RoleDescr
                       FROM user AS u
                         LEFT JOIN language AS l
                           ON u.LanguageID = l.LanguageID
                         LEFT JOIN userrole AS ur
                           ON u.UserID = ur.UserID
                         LEFT JOIN role AS r
                           ON ur.RoleID = r.RoleID
                       WHERE u.UserID = '${Global['deleteuserid']}' ";
            $arrUser = runQueryReturnArray( $strSQL );

            if( isset( $arrUser ) ){
                $strSQL = "DELETE FROM User WHERE UserID = '${Global['deleteuserid']}'";
                $strAff = runSQLReturnAffected( $strSQL );
                $strSQL = "DELETE FROM UserRole WHERE UserID = '${Global['deleteuserid']}'";
                $strAff = runSQLReturnAffected( $strSQL );
                $strSQL = "DELETE FROM Session WHERE UserID = '${Global['deleteuserid']}'";
                $strAff = runSQLReturnAffected( $strSQL );

                $strMsg = "<b>" . $arrUser[0][0] . "</b> ${gaLiterals['successfully deleted']}.";

                logger( "USER DELETION SUCCESS: User deleted UserID: ${Global['deleteuserid']}; UserName: " . $arrUser[0][0] . "; FirstName: " . $arrUser[0][1] . "; LastName: " . $arrUser[0][2] . "; Email: " . $arrUser[0][3] . "; RoleID: " . $arrUser[0][4] . "; " );
            }
        }
    }

    $strHTML  = "<b><font size=2>${gaLiterals['Delete Current User']}</font></b><br><br>";

    $strSQL   = "SELECT UserID, CONCAT( LastName, ', ', FirstName, ' (', UserName, ')' ) AS 'Name' FROM user ORDER BY LastName ASC, FirstName ASC";
    $arrUsers = runQueryReturnArray( $strSQL );

    $strHTML .= "<form id='deleteuserform' action='$strURL' method='post'>\n";
    $strHTML .= "<b>${gaLiterals['User To Delete']}</b>&nbsp;&nbsp;<SELECT name=deleteuserid><option></option>";

    foreach( $arrUsers as $user ) {

        $strHTML .= "<OPTION VALUE=${user['UserID']}";

        if( isset( $Global['deleteuserid'] ) && $user['UserID'] == $Global['deleteuserid'] ) {
            $strHTML .= ' SELECTED>';
        } else {
            $strHTML .= '>';
        }

        $strHTML .= "${user['Name']}</OPTION>";
    }

    $strHTML .= "</select><input type='submit' name='bt'value='${gaLiterals['Delete']}'>";
    $strHTML .= "</form>";

    add_element( $strHTML );

    //Display returned message
    if( isset( $strMsg ) ) {
        add_element( "<br>$strMsg<br>" );
    }

    //Display deleted user info if Delete button was pushed
    if( isset( $Global['bt'] ) && $Global['bt'] === $gaLiterals['Delete'] ) {
        $strHTML = "<table><tr><td>&nbsp;&nbsp;&nbsp;</td></tr>";
        $strHTML .= "<tr><td colspan=2><b>${gaLiterals['Details']}</b></td></tr>";
        $strHTML .= "<tr><td></td><td><b>${gaLiterals['Name']}</b></td><td>". $arrUser[0][1] . " " . $arrUser[0][2] . "</td></tr>";
        $strHTML .= "<tr><td></td><td><b>${gaLiterals['User Name']}</b></td><td>". $arrUser[0][0] . "</td></tr>";
        $strHTML .= "<tr><td></td><td><b>${gaLiterals['Email']}</b></td><td>". $arrUser[0][3] . "</td></tr>";
        $strHTML .= "<tr><td></td><td><b>${gaLiterals['Language']}</b></td><td>". $arrUser[0][4] . "</td></tr>";
        $strHTML .= "<tr><td></td><td><b>${gaLiterals['Role']}</b></td><td>". $arrUser[0][5] . "</td></tr>";

        add_element( $strHTML );
    }

}



function ChangeOwnPasswordForm() {
    global $gaLiterals;
    global $Global;

    $strURL = getOptionURL(OPTIONID_CHANGEOWNPASSWORDFORM);
    $arrMsg = array();


    if( isset( $Global['bt'] ) && $Global['bt'] === $gaLiterals['Change'] ) {

        //check to see if old password is correct, if not, fail and return
        $strSQL  = "SELECT UserID FROM user WHERE UserID = '${Global['UserID']}' AND PasswordText = sha( '${Global['oldpassword']}' )";
        $arrUser = runQueryReturnArray( $strSQL );
        if( ! $arrUser ) {

            $arrMsg[0] = $gaLiterals['PassNotCorr'];
            logger( 'USER CHANGE_OWN_PASSWORD FAILED: Old password incorrect' );

        } else {

            //check to see if new password is the same as confirm password, if not, fail and return
            if( $Global['newpassword'] !== $Global['confirmpassword'] ) {

                $arrMsg[1] = $gaLiterals['PassNotSame'];
                $arrMsg[2] = $gaLiterals['PassNotSame'];

            } else {

                //check to make sure new password is not the same as the old password; if their the same, will fail
                if( $Global['oldpassword'] !== $Global['newpassword'] ) {

                    //check to see if new password is complex, if not, fail and return
                    if( IsPasswordComplex( $Global['newpassword'], 0 ) ) {

                        //passed all checks; will go ahead and change password for current user
                        $strSQL = "UPDATE User SET PasswordText = sha( '${Global['newpassword']}' ) WHERE UserID = '${Global['UserID']}'";
                        $strAff = runSQLReturnAffected( $strSQL );

                        if( $strAff ) {

                            $arrMsg[3] = $gaLiterals['Success'];
                            logger( 'USER CHANGE_OWN_PASSWORD SUCCESS' );

                        } else {

                            $arrMsg[3] = $gaLiterals['Failed'];

                        }

                    } else {

                        $arrMsg[1] = $gaLiterals['PassNotComp'];

                    }    //end if( IsPasswordComplex( $Global['newpassword'], 0 ) )

                } else {

                    $arrMsg[0] = $gaLiterals['PassSame'];
                    $arrMsg[1] = $gaLiterals['PassSame'];

                }    //end if( $Global['oldpassword'] !== $Global['newpassword'] )

            }        //end if( $Global['newpassword'] !== $Global['confirmpassword'] )

        }            //end if( ! $arrUser )

    }                //end if( $Global['bt'] === $gaLiterals['Change'] )

    $strHTML  = "<form id='changeownpasswordform' action='$strURL' method='post'>\n";
    $strHTML .= "<table>\n";
    $strHTML .= "<tr><td><b>${gaLiterals['Old Password']}</b></td><td><input type='password' name='oldpassword' value=''></td><td><font color='red'>" . ( isset( $arrMsg[0] ) ? $arrMsg[0] : '' ) . "</font></td></tr>\n";
    $strHTML .= "<tr><td><b>${gaLiterals['New Password']}</b></td><td><input type='password' name='newpassword' value=''></td><td><font color='red'>" . ( isset( $arrMsg[0] ) ? $arrMsg[1] : '' ) . "</font></td></tr>\n";
    $strHTML .= "<tr><td><b>${gaLiterals['Confirm Password']}</b></td><td><input type='password' name='confirmpassword' value=''></td><td><font color='red'>" . ( isset( $arrMsg[0] ) ? $arrMsg[2] : '' ) . "</font></td></tr>\n";
    $strHTML .= "</table><input type='submit' name='bt' value='${gaLiterals['Change']}'>\n";
    $strHTML .= "</form>\n";
    if( isset( $arrMsg[3] ) ) {
        $strHTML .= "<br><b><font color='red' size='3'>${arrMsg[3]}</font></b>";
    }

    add_element( $strHTML );

}



function ResetUserPasswordForm(){
    global $gaLiterals;
    global $Global;

    $strURL = getOptionURL(OPTIONID_RESETUSERPASSWORDFORM);

    if( checkOptionPermission( $Global['UserID'], $Global['OptionID'] ) == 0 ){
        dispatch( OPTIONID_LOGOUT );
        return;
    }

    if( isset( $Global['bt'] ) && $Global['bt'] === $gaLiterals['Reset Password'] ) {

        while( 1 ) {
            $strPass = genRandomString( 10 );
            if( IsPasswordComplex( $strPass, 1 ) ) {
                break;
            }
        }

        $strSQL  = "UPDATE user SET PasswordText = sha( '$strPass' ) WHERE UserID = '${Global['useridtoreset']}'";
        $strAff  = runSQLReturnAffected( $strSQL );

        if( $strAff ) {

            $strSQL  = "SELECT UserName FROM user WHERE UserID = '${Global['useridtoreset']}'";
            $arrUser = runQueryReturnArray( $strSQL );

            $strMsg  = '<b>' . $arrUser[0][0] . '</b> ' . $gaLiterals['password rest to'] . ' <b>' . $strPass . '</b>';
            logger( "USER RESET_PASSWORD SUCCESS: UserID: ${Global['useridtoreset']}; UserName: " . $arrUser[0][0] . "; " );

        } else {

            $strMsg  = '<b>' . $gaLiterals['ERROR'] . '<b> ' . $gaLiterals['with resetting password for'] . ' <b>' . $arrUser[0][0] . '</b>.';
            logger( "USER RESET_PASSWORD FAILED: UserID: ${Global['useridtoreset']}; UserName: " . $arrUser[0][0] . "; " );

        }

    }        // end if isset( $Global['bt'] )

    $strSQL   = "SELECT UserID, CONCAT( LastName, ', ', FirstName, ' (', UserName, ')' ) AS 'Name' FROM user ORDER BY LastName ASC, FirstName ASC";
    $arrUsers = runQueryReturnArray( $strSQL );

    $strHTML  = "<form id='resetuserpasswordform' action='$strURL' method='post'>\n";
    $strHTML .= "<b>${gaLiterals['User']}</b>&nbsp;&nbsp;<select name='useridtoreset'><option></option>";
    
    foreach( $arrUsers as $user ){

        $strHTML .= "<OPTION VALUE=${user['UserID']}";

        if( isset( $Global['useridtoreset'] ) && $user['UserID'] == $Global['useridtoreset'] ) {
            $strHTML .= ' SELECTED>';
        } else {
            $strHTML .= '>';
        }

        $strHTML .= "${user['Name']}</OPTION>";
    }
 
    $strHTML .= "</select><input type='submit' name='bt' value='${gaLiterals['Reset Password']}'>";

    if( isset( $strMsg ) ) {
        $strHTML .= "<br><font color=red>$strMsg</font>";
    }

    add_element( $strHTML );

}




function ChangeUserRoleForm() {
    global $gaLiterals;
    global $Global;

    $strURL = getOptionURL(OPTIONID_CHANGEUSERROLEFORM);

    if( checkOptionPermission( $Global['UserID'], $Global['OptionID'] ) == 0 ){
        dispatch( OPTIONID_LOGOUT );
        return;
    }

    if( isset( $Global['bt'] ) && $Global['bt'] === $gaLiterals['Change'] ) {

        //does sure UserID exists?
        $strSQL      = "SELECT UserID, UserName FROM user WHERE UserID = '${Global['useridchange']}'";
        $arrUser     = runQueryReturnArray( $strSQL );
        $strUserName = $arrUser[0][1];

        if( ! isset( $arrUser ) ) {

            $strMsg = $gaLiterals['UserNotExist'];
            logger( "USER CHANGE_ROLE FAILURE: User does not exist; UserID: ${Global['useridchange']}; " );

        } else {      //UserID does exist

            //does user have entry in UserRole?
            $strSQL = "SELECT UserID, RoleID FROM userrole WHERE UserID = '${Global['useridchange']}'";
            $arrUser = runQueryReturnArray( $strSQL );
            if( $arrUser ) {

                //does user already have the rights?
                if( $arrUser[0][1] == $Global['roleidchange'] ) {

                    //do nothing; already has these rights; will print "Success"
                    $strMsg = $gaLiterals['Success'];
                    logger( "USER CHANGE_ROLE SUCCESS: Changed to same role; UserID: ${Global['useridchange']}; UserName: $strUserName; Old RoleID: " . $Global['roleidchange'] . "; New RoleID: " . $arrUser[0][1] . "; " );

                } else {     //user does not have the rights

                    //make sure RoleID exists
                    $strSQL  = "SELECT RoleID FROM role WHERE RoleID = '${Global['roleidchange']}'";
                    $arrRole = runQueryReturnArray( $strSQL );

                    if( ! $arrRole ) {    //role does not exist

                        $strMsg = $gaLiterals['RoleNotExist'];
                        logger( "USER CHANGE_ROLE FAILURE: Role does not exist; UserID: ${Global['useridchange']}; UserName: $strUserName; Old RoleID: " . $Global['roleidchange'] . "; New RoleID: " . $arrUser[0][1] . "; " );

                    } else {    //All is good, go ahead and make the change

                        $strSQL = "UPDATE UserRole SET RoleID = '${Global['roleidchange']}', LatestChangeUserID = '${Global['UserID']}' WHERE UserID = '${Global['useridchange']}'";
                        $strAff = runSQLReturnAffected( $strSQL );

                        if( $strAff ) {
                            $strMsg = $gaLiterals['Success'];
                            logger( "USER CHANGE_ROLE SUCCESS: Changed to a different role; UserID: ${Global['useridchange']}; UserName: $strUserName; Old RoleID: " . $Global['roleidchange'] . "; New RoleID: " . $arrUser[0][1] . "; " );
                        } else {
                            $strMsg = $gaLiterals['ERROR'];
                            logger( "USER CHANGE_ROLE FAILURE: UserID: ${Global['useridchange']}; UserName: $strUserName; Old RoleID: " . $Global['roleidchange'] . "; New RoleID: " . $arrUser[0][1] . "; " );
                        }

                    }       //end make sure RoleID exists

                }           //end does user already have the rights?

            } else {  //does not have entry in UserRole; will do INSERT instead

                $strSQL = "INSERT INTO UserRole( UserID, RoleID, LatestChangeUserID ) VALUES ( '${Global['useridchange']}', '${Global['roleidchange']}', '${Global['UserID']}' )";
                $strAff = runSQLReturnAffected( $strSQL );

                if( $strAff ) {
                    $strMsg = $gaLiterals['Success'];
                    logger( "USER CHANGE_ROLE SUCCESS: Changed to a different role; UserID: ${Global['useridchange']}; UserName: $strUserName; Old RoleID: " . $Global['roleidchange'] . "; New RoleID: " . $arrUser[0][1] . "; " );
                } else {
                    $strMsg = $gaLiterals['ERROR'];
                    logger( "USER CHANGE_ROLE FAILURE: UserID: ${Global['useridchange']}; UserName: $strUserName; Old RoleID: " . $Global['roleidchange'] . "; New RoleID: " . $arrUser[0][1] . "; " );
                }

            }         //end does user have entry in UserRole

        }             //end does sure UserID exists?

    }                 //end if( $Global['bt'] === $gaLiterals['Change'] )

    $strHTML  = "<form name='changeuserroleform' action='$strURL' method='post'>\n";

    //Build user select list
    $strSQL   = "SELECT
                   u.UserID,
                   CONCAT( u.LastName, ', ', u.FirstName, ' (', u.UserName, ')' ) AS 'Name', 
                   r.RoleDescr
                 FROM user AS u
                   LEFT JOIN userrole AS ur
                     ON u.UserID = ur.UserID
                   LEFT JOIN role AS r
                     ON r.RoleID = ur.RoleID
                 ORDER BY u.LastName ASC, u.FirstName ASC";
    $arrUsers = runQueryReturnArray( $strSQL );

    $strHTML .= "<select name='useridchange'><option></option>";

    foreach( $arrUsers as $user ){

        $strHTML .= "<OPTION VALUE=${user['UserID']}";

        if( isset( $Global['useridchange'] ) && $user['UserID'] == $Global['useridchange'] ) {
            $strHTML .= ' SELECTED>';
        } else {
            $strHTML .= '>';
        }

        $strHTML .= "${user['Name']} -- ${user['RoleDescr']}</OPTION>";
    }

    $strHTML .= "</select><br>\n";

    //Build role select list
    $strSQL   = "SELECT RoleID, RoleDescr FROM role ORDER BY RoleDescr ASC";
    $arrRoles = runQueryReturnArray( $strSQL );

    $strHTML .= "<select name='roleidchange'><option></option>";

    foreach( $arrRoles as $role ){

        $strHTML .= "<OPTION VALUE=${role['RoleID']}";

        if( isset( $Global['roleidchange'] ) && $role['RoleID'] == $Global['roleidchange'] ) {
            $strHTML .= ' SELECTED>';
        } else {
            $strHTML .= '>';
        }

        $strHTML .= "${role['RoleDescr']}</OPTION>";
    }

    $strHTML .= "</select><br><input type='submit' name='bt' value='${gaLiterals['Change']}'>";
    if( isset( $strMsg ) ) {
        $strHTML .= "<br>$strMsg\n";
    }

    add_element( $strHTML );

}



function ChangeUserDetailsForm() {
    global $gaLiterals;
    global $Global;

    $strURL  = getOptionURL(OPTIONID_CHANGEUSERDETAILSFORM);
    $arrUser = '';
    $strMsg = "";

    if( checkOptionPermission( $Global['UserID'], $Global['OptionID'] ) == 0 ){
        dispatch( OPTIONID_LOGOUT );
        return;
    }

    if( isset($Global['bt']) && $Global['bt'] != '' ){

        $strSQL  = "SELECT
                      u.UserID,
                      u.FirstName,
                      u.LastName,
                      u.UserName,
                      u.EmailAddress,
                      u.LanguageID,
                      r.RoleID,
                      u.CreatedDatetime,
                      u.LatestChangeStamp,
                      cu.UserName
                    FROM user AS u
                      LEFT JOIN userrole AS r
                        ON u.UserID = r.UserID
                      LEFT JOIN user AS cu
                        ON u.LatestChangeUserID = cu.UserID
                    WHERE u.UserID = '${Global['useridselect']}'";
        $arrUser = runQueryReturnArray( $strSQL );

    }


    if( isset($Global['bt']) && $Global['bt'] === $gaLiterals['Save'] ) {

        $flgBad = '';
        $strUserName = '';
        $strLog = "UserID: " . $arrUser[0][0] . "; Old FirstName: " . $arrUser[0][1] . "; Old LastName: " . $arrUser[0][2] . "; Old UserName " . $arrUser[0][3] . "; Old EmailAddress: " . $arrUser[0][4] . "; Old LanguageID: " . $arrUser[0][5] . "; Old RoleID: " . $arrUser[0][6] . "; ";

        //check username
        if( $Global['username'] == '' ){
            $arrVals['username'][1] = 'required';
            $flgBad = 1;
        }else{
            $tmp = runQueryReturnArray( "SELECT UserID FROM user WHERE UserName = '${Global['username']}' AND UserID != '${Global['useridfield']}' " );
            if( $tmp ){
                //username already in use
                $flgBad = 1;
                $arrVals['username'][1] = $gaLiterals{'Already Exists'};
            }
            if( strlen( $Global['username'] > 20 ) ){
                $flgBad = 1;
                $arrVals['username'][1] = $gaLiterals{'Max20Chars'};
            }
        }

        //check first and last name
        if( $Global['firstname'] == '' ) {
            $arrVals['firstname'][1] = $gaLiterals{'Required'};
            $flgBad = 1;
        }
        if( $Global['lastname'] === '' ) {
            $arrVals['lastname'][1] = $gaLiterals{'Required'};
            $flgBad = 1;
        }

        //email address not required

        //check language
        if( $Global['language'] == '' ){
            $arrVals['language'][1] = $gaLiterals{'Required'};
            $flgBad = 1;
        }

        //check role
        if( $Global['role'] == '' ){
            $arrVals['role'][1] = $gaLiterals{'Required'};
            $flgBad = 1;
        }

        //submit changes if all values are good
        if( $flgBad != 1 ) {

            //UPDATE User table
            $strSQL = "UPDATE User SET
                         UserName           = '${Global['username']}',
                         FirstName          = '${Global['firstname']}',
                         LastName           = '${Global['lastname']}',
                         EmailAddress       = '${Global['email']}',
                         LanguageID         = '${Global['language']}',
                         LatestChangeUserID = '${Global['UserID']}'
                       WHERE UserID = '${Global['useridselect']}'";
            $strAff = runSQLReturnAffected( $strSQL );

            if( ! $strAff ){
                $strMsg = $gaLiterals['ERROR'];
                logger( "USER CHANGE_DETAILS FAILURE: MySQL error running UPDATE; UserID: ${Global['useridselect']};" );
            } else {
                logger( $strLog . "New FirstName: ${Global['firstname']}; New LastName: ${Global['lastname']}; New UserName: ${Global['username']}; New EmailAddress: ${Global['email']}; New LanguageID: ${Global['language']}; New RoleID: ${Global['role']}; " );
            }


            //UPDATE Role table
            //Doing do a straight lookup of the current RoleID because the UPDATE statement will return 0 rows affected if the UserID is already assigned to that role;
            //  thus, when we check to see if UPDATE was successful, we'd see a 0 and then try to do an INSERT, resulting in a double entry.
            //  if he doesn't even have an entry in the UserRole table, we'll just INSERT

            //does user have entry in UserRole?
            $strSQL = "SELECT UserID, RoleID FROM userrole WHERE UserID = '${Global['useridselect']}'";
            $arrUser = runQueryReturnArray( $strSQL );
            if( $arrUser ) {

                //does user already have the rights?
                if( $arrUser[0][1] == $Global['role'] ) {

                    //do nothing; already has these rights;

                } else {     //user does not have the rights

                    //make sure RoleID exists
                    $strSQL  = "SELECT RoleID FROM role WHERE RoleID = '${Global['role']}'";
                    $arrRole = runQueryReturnArray( $strSQL );

                    if( ! $arrRole ) {    //role does not exist

                        $strMsg = $gaLiterals['RoleNotExist'];
                        //LOG

                    } else {    //All is good, go ahead and make the change

                        $strSQL = "UPDATE UserRole SET RoleID = '${Global['role']}', LatestChangeUserID = '${Global['UserID']}' WHERE UserID = '${Global['useridselect']}'";
                        $strAff = runSQLReturnAffected( $strSQL );

                        if( $strAff ) {
                            $strMsg = $gaLiterals['Success'];
                            //LOG
                        } else {
                            $strMsg = $gaLiterals['ERROR'];
                            //LOG
                        }

                    }       //end make sure RoleID exists

                }           //end does user already have the rights?

            } else {  //does not have entry in UserRole; will do INSERT instead

                $strSQL = "INSERT INTO UserRole( UserID, RoleID, LatestChangeUserID ) VALUES ( '${Global['useridselect']}', '${Global['role']}', '${Global['UserID']}' )";
                $strAff = runSQLReturnAffected( $strSQL );

                if( $strAff ) {
                    $strMsg = $gaLiterals['Success'];
                    //LOG
                } else {
                    $strMsg = $gaLiterals['ERROR'];
                    //LOG
                }

            }       //end if( $arrUser )

        }           //end if( ! $flgBad )

        //if successfully alter account, re-lookup
//        if( $strAff ) {

            $strSQL  = "SELECT
                          u.UserID,
                          u.FirstName,
                          u.LastName,
                          u.UserName,
                          u.EmailAddress,
                          u.LanguageID,
                          r.RoleID,
                          u.CreatedDatetime,
                          u.LatestChangeStamp,
                          cu.UserName
                        FROM user AS u
                          LEFT JOIN userrole AS r
                            ON u.UserID = r.UserID
                          LEFT JOIN user AS cu
                            ON u.LatestChangeUserID = cu.UserID
                        WHERE u.UserID = '${Global['useridselect']}'";
            $arrUser = runQueryReturnArray( $strSQL );

            $strMsg = $gaLiterals['Success'];

//        } else {

//            $strMsg = $gaLiterals['ERROR'];

//        }

    }           //end if( $Global['bt'] === $gaLiterals['Save'] )

    $strHTML  = "<form name='changeuserdetailsform' action='$strURL' method='post'>\n";

    //Build select list of usernames
    $strSQL   = "SELECT CONCAT( LastName, ', ', FirstName, ' (', UserName, ')' ) AS Name, UserID FROM user";
    $arrUsers = runQueryReturnArray( $strSQL );

    $strHTML .= "${gaLiterals['User']}&nbsp;&nbsp;<select name='useridselect'><option></option>";

    foreach( $arrUsers as $user ){

        $strHTML .= "<OPTION VALUE=${user['UserID']}";
        
        if( isset($Global['useridselect']) && $user['UserID'] == $Global['useridselect'] ) {
            $strHTML .= ' SELECTED>';
        } else {
            $strHTML .= '>';
        }

        $strHTML .= "${user['Name']}</OPTION>";
    }

    $strHTML .= "</select><input type='submit' name='bt' value='${gaLiterals['Select']}'>\n";

    //Build table of account details
    if( $arrUser ){
        $strHTML .= "<table>\n";
        $strHTML .= "<tr><td>${gaLiterals['User ID']}</td><td><input READONLY type='text' name='useridfield' value='" . $arrUser[0][0] . "'></td></tr>";
        $strHTML .= "<tr>
            <td>
              ${gaLiterals['User Name']}
            </td>
            <td>
              <input type='text' width='30' name='username' value='" . $arrUser[0][3] . "'>
            </td>
            <td><font color=red>";

        $strHTML .= ( isset( $arrVals['username'][1] ) ? $arrVals['username'][1] : '');

        $strHTML .= "</font></td>
          </tr>
          <tr>
            <td>
              ${gaLiterals['First Name']}
            </td>
            <td>
              <input type='text' width='30' name='firstname' value='" . $arrUser[0][1] . "'>
            </td>
            <td><font color=red>";

        $strHTML .= ( isset( $arrVals['firstname'][1] ) ? $arrVals['firstname'][1] : '');

        $strHTML .= "</font></td>
          </tr>
          <tr>
            <td>
              ${gaLiterals['Last Name']}
            </td>
            <td>
              <input type='text' width='30' name='lastname' value='" . $arrUser[0][2] . "'>
            </td>
            <td><font color=red>";

        $strHTML .= ( isset( $arrVals['lastname'][1] ) ? $arrVals['lastname'][1] : '');

        $strHTML .= "</font></td>
          </tr>
          <tr>
            <td>
              ${gaLiterals['Email Address']}
            </td>
            <td>
              <input type='text' width='30' name='email' value='" . $arrUser[0][4] . "'>
            </td>
            <td><font color=red>";

        $strHTML .= ( isset( $arrVals['email'][1] ) ? $arrVals['email'][1] : '');

        $strHTML .= "</font></td>
          </tr>
          <tr>
            <td>
              ${gaLiterals['Language']}
            </td>
            <td>
              <select name='language'>
              <option></option>";


        $strSQL  = "SELECT LanguageID, LanguageName FROM language ORDER BY LanguageName ASC";
        $arrLang = runQueryReturnArray( $strSQL );
        foreach( $arrLang as $lang ){
            $strHTML .= "<OPTION VALUE=${lang['LanguageID']}";

            if( $lang['LanguageID'] == $arrUser[0][5] ) {
                $strHTML .= ' SELECTED>';
            } else {
                $strHTML .= '>';
            }

            $strHTML .= "${lang['LanguageName']}</OPTION>";
        }

        $strHTML .="</select></td><td><font color=red>" . ( isset( $arrVals['language'][1] ) ? $arrVals['language'][1] : '') . "</font></td></tr>";
        $strHTML .= "<tr><td>${gaLiterals['Role']}</td><td><select name='role'><option></option>";

        $strSQL  = "SELECT RoleID, RoleDescr FROM role ORDER BY RoleDescr ASC";
        $arrRole = runQueryReturnArray( $strSQL );
        foreach( $arrRole as $role ){

            $strHTML .= "<OPTION VALUE=${role['RoleID']}";

            if( $role['RoleID'] == $arrUser[0][6] ) {
                $strHTML .= ' SELECTED>';
            } else {
                $strHTML .= '>';
            }

            $strHTML .= "${role['RoleDescr']}</OPTION>";
        }

        $strHTML .= "</select></td><td><font color=red>";
        $strHTML .= ( isset( $arrVals['role'][1] ) ? $arrVals['role'][1] : '');
        $strHTML .= "</font></td></tr>";
        $strHTML .= "<tr><td>${gaLiterals['When Created']}</td><td><input READONLY type='text' name='whencreate' value='" . $arrUser[0][7] . "'></td></tr>\n";
        $strHTML .= "<tr><td>${gaLiterals['Last Editor']}</td><td><input READONLY type='text' name='whencreate' value='" . $arrUser[0][9] . "'></td></tr>\n";
        $strHTML .= "<tr><td>${gaLiterals['Last Changed']}</td><td><input READONLY type='text' name='whencreate' value='" . $arrUser[0][8] . "'></td></tr>\n";
        $strHTML .= "</table><input type='submit' name='bt' value='${gaLiterals['Save']}'>";

    }

    $strHTML .= "</form>\n";
    $strHTML .= "<br>$strMsg\n";

    add_element( $strHTML );

}

?>

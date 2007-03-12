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
 * Dispatcher - 6/22/2005
 *
 */

/*
 * dispatch($intOptionID)
 *
 * Determines what to output to the user.  If session is invalid, the login page is queued. 
 * Both the content page name and function name are retrieved from the database, and then the retrieved 
 * function is called.
 */
function dispatch($intOptionID) {

   global $Global;

   PopulateUserGlobals();
   getAllLiteralsForUserLang();

   // If invalid session and user is not currently trying to log in, force login page.
   if (! $Global["ValidSession"] && $intOptionID != OPTIONID_LOGINUSER) {
      $intOptionID = OPTIONID_LOGINPAGE;
   }

   // Add current option to globals array
   add_global("OptionID", $intOptionID);
   
   // Get content path and function for option ID from DB
   $aOption = getMenuOption($intOptionID);
   $strFilePathAndName = "../scripts/" . $aOption[$intOptionID]['ContentPathName'];
   if (!empty($aOption[$intOptionID]['ContentPathName']) && is_readable("$strFilePathAndName"))
   {
      include_once "$strFilePathAndName";
      // Call function for this menu option
      $strFunctionName = $aOption[$intOptionID]['FunctionName'];
      if ($strFunctionName) {
         $strFunctionName();
      }
   }
   else if ( empty($aOption[$intOptionID]['ContentPathName']) )
   {
       // when navigating to another tab, there will not be an option ID that is passed along, thus we'll ingnore the fact that we can't "read the file"; 
       //   the reason why we can't is because there is not file to be read
       // nothing to do
   }
   else
   {
       logger("Serious Error:  Could not find path or could not read file for $strFilePathAndName");
   }   
}

function getMenuOption($intOptionID){

      $strSQL = "SELECT mo.MenuOptionID,
                        mo.ContentPathName,
                        mo.FunctionName
                   FROM MenuOption mo
                  WHERE mo.MenuOptionID = $intOptionID";
 /*   
   $strSQL = "SELECT DISTINCT 
                   mo.MenuOptionID,
                   mo.OptionName,
                   mo.SequenceNum OptionSequenceNum,
                   m.MenuID,
                   m.ParentMenuOptionID,
                   m.LevelNum,
                   m.SequenceNum MenuSequenceNum,
                   m.MenuName,
                   mo.ContentPathName,
                   0 SelectedFlag
              FROM UserRole ur
              JOIN RoleMenuOption rmo ON rmo.RoleID = ur.RoleID
              JOIN MenuOption mo ON mo.MenuOptionID = rmo.MenuOptionID
              JOIN Menu m ON m.MenuID = mo.MenuID
             WHERE ur.UserID = 
          ORDER BY m.LevelNum, m.SequenceNum, m.MenuID, mo.SequenceNum";
*/     

   $aOptions = runQueryReturnArray($strSQL, KEY_COLUMN1, MYSQL_ASSOC);
   return ($aOptions);
}
?>
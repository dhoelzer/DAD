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
 	Before you even look at this code and want to kill me, please know that the menuing system
	is built on older code borrowed from another project.  It is not pretty... In fact, it's quite
	 tortuous, but it works for now.  Someday it will be replaced with something that makes
	 far more sense and is much easier to manage (and understand).
*/

/*------------------------------------------------------------------------
 * Menu Administration & Role Security - 6/30/05
 *
 * This module allows the user to interactively add menus and options
 * through the web interface and to simultaneously assign roles to those
 * menus.
 *------------------------------------------------------------------------
 */

function SubmitNewOption()
{
  global $Global;
  
  // Validation is necessary, but will be added later.  Only software
  // developers will have access to this page in the long run, so the
  // validation is much less important.
  
  $NewOptionName = $Global['OptionName'];
  $ParentMenuID = $Global['ParentMenu'];
  $CodeLocation = $Global['CodeLocation'];
  $FunctionName = $Global['FunctionName'];
  $Sequence = $Global['Sequence'];
  $tmp = '';
  
  $sql = "SELECT MenuOptionID FROM dad.MenuOption WHERE OptionName='$NewOptionName' AND MenuID = '$ParentMenuID'";
  $tmp = runQueryReturnArray($sql);
  if( !$tmp[0][0] == '' ){
      add_element("Error: That Menu Option Name exists on that Tab already");
  }else{
  
      $sql = "INSERT INTO dad.MenuOption (OptionName, MenuID, SequenceNum, ContentPathName,FunctionName)
              VALUES ('$NewOptionName', $ParentMenuID, $Sequence, '$CodeLocation', '$FunctionName')";
      $NewOptionID = runInsertReturnID($sql);
  
      $sql = "SELECT RoleID, RoleName
             FROM dad.Role";
      $RolesReturn = runQueryReturnArray($sql);
      foreach($RolesReturn as $row)
      {
        if(isset($Global[$row['RoleName']]))
        {
          $RolesToInsert[$row['RoleName']] = $row['RoleID'];
        }
      }
      if( is_array($RolesToInsert) ){
          foreach($RolesToInsert as $Role)
          {
            $sql = "INSERT INTO dad.RoleMenuOption (RoleID, MenuOptionID)
                    VALUES ($Role, $NewOptionID)";
            $success = runInsertReturnID($sql);
            if(!$success)
            {
              add_element("Error inserting role ID $Role for $NewOptionID.");
            }
          }
      }else{
          /*if the user did not give it a role, we will default to Software Developer*/
          $sql = "INSERT INTO dad.RoleMenuOption (RoleID, MenuOptionID)
                  VALUES (1, $NewOptionID)";
          $success = runInsertReturnID($sql);
          add_element("<font color=red>Default role asssigned</font><br>");
          if(!$success){
              add_element("Error inserting role ID $Role for $NewOptionID.");
          }
      }
      $OptionConstantName = "OPTIONID_".strtoupper($NewOptionName);
      $OptionConstantName = preg_replace("/ /", "_", $OptionConstantName);
    //Add option to constants
      $OptionIDFile = fopen("../config/OptionIDs.php", "a+");
      fwrite($OptionIDFile, "define('$OptionConstantName', $NewOptionID);\n");
      fclose($OptionIDFile);
    //Add option text to literals
      $OptionIDFile = fopen("../scripts/E/Auto_added_literals.php", "a+");
      fwrite($OptionIDFile, "\$gaLiterals['$NewOptionName'] = '$NewOptionName';\n");
      fclose($OptionIDFile);
      add_element("Completed.  The literal translations will be available following the next page click or refresh.");
  }
}

function CreateNewOptionPage()
{
  global $Global;

  $MenuSelectList = GetMenuSelectList(1);
  $RoleTable = GetRoleTable(0);
  $MenuOptionList = GetMenuOptionList(0);

  $URL = getOptionURL(OPTIONID_SUBMITNEWOPTION);
  
$HTML = "
<form name=\"frmAddMenuOption\" action=\"$URL\" method=post>
<table cellpadding = 5>
  <tr><td align=center><h3>Menu Option Details</h3></td><td align=center><h3>Roles</h3></td></center></td></tr>
  <tr><td valign=top><table cellspacing=5 border=3><tr><td align=right>
      Menu Option Name: <input name=OptionName type=text value=\"\" size=30><p>
      Member of: $MenuSelectList  Option ID#: NA <p>
      Code Location: <input name=CodeLocation type=text size=30 value=\"\"><p>
      Function Run: <input name=FunctionName type=text size=30 value=\"\"><p>
      Position on Page: <input name=Sequence type=text size=30 value=\"\">
      </td></tr></table>
  </td><td valign=top><table cellspacing=5 border=3><td align=left>$RoleTable</td></table></td>
  </tr>
  <tr><td colspan=2 align=center><center><input type=submit name=btnSubmit value=\"Add Menu Option\"></td></tr>
</table>
</form>";
add_element($HTML);
}

function ShowMenuOptions()
{
  global $Global;

  $ThisMenuOption = (isset($Global['SelectOption']) ? $Global['SelectOption'] : 1);
  $constant_name  = '';

  $MenuOptionDetails = GetMenuOptionDetails($ThisMenuOption);
  $OptionName = $MenuOptionDetails['OptionName'];
  $ContentPathName = $MenuOptionDetails['ContentPathName'];
  $FunctionName = $MenuOptionDetails['FunctionName'];
  $Sequence = $MenuOptionDetails['OptionSequenceNum'];
  
  $MenuSelectList = GetMenuSelectList($MenuOptionDetails['MenuID']);
  $RolesWithAccess = GetRolesForOption($ThisMenuOption);
  $RoleTable = GetRoleTable($RolesWithAccess);
  $MenuOptionList = GetMenuOptionList($ThisMenuOption);

  $URL = getOptionURL(OPTIONID_MENUADMINSELECT);
  $HTML = "<form name='MenuAdminSelection' action='$URL' method='post' style='position:relative; top:25px;'>".
    "$MenuOptionList <input type=submit name=btnSubmit value='Select Option to Modify'></form><P><HR>";
  add_element($HTML);
  if(!isset($Global['SelectOption'])) { return; }
  $URL = getOptionURL(OPTIONID_SUBMIT_MODIFIED_MENU);

  $constant_name = $OptionName;
  $constant_name = preg_replace( "/\s/", "_", $constant_name);
  $constant_name = 'OPTIONID_' . ( strtoupper( $constant_name ) );

$HTML = "
<form name=\"frmEditMenuOption\" action=\"$URL\" method=post>
  <table cellpadding = 5>
    <tr><td align=center><h3>Menu Option Details</h3></td><td align=center><h3>Roles</h3></td></center></td></tr>
    <tr><td valign=top><table cellspacing=5 border=3><tr><td align=right>

        Menu Option Name: <input name=OptionName type=text value=\"$OptionName\" size=30><p>
        Member of: $MenuSelectList<p>
        <input type=hidden name=OptionToUpdate value=$ThisMenuOption>
        Code Location: <input name=CodeLocation type=text size=30 value=\"$ContentPathName\"><p>
        Function Run: <input name=FunctionName type=text size=30 value=\"$FunctionName\"><p>
        Position on Page: <input name=Sequence type=text size=30 value=$Sequence><p>
        <div align=left>Option ID#: $ThisMenuOption<br>Constant:&nbsp;&nbsp;&nbsp;$constant_name</div><p>
      </td></tr></table>
    </td><td valign=top><table cellspacing=5 border=3><td>$RoleTable</td></table></td>
    </tr>
    <tr><td colspan=2 align=center><input type=submit name=btnSubmit value=\"Submit Changes\"></td></tr>
  </table>
</form>";
add_element($HTML);
}

function GetMenuSelectList($Parent)
{
  $sql = "SELECT
            me.MenuID,
            me.MenuName
          FROM dad.Menu me
          ORDER BY me.MenuName ASC";
  $MenuResults = runQueryReturnArray($sql);
  $MenuSelectList = "<select name=\"ParentMenu\" style=\"width:155pt\">";
  $ThisMenuID = $Parent;
  foreach($MenuResults as $row)
  {
    $MenuID = $row['MenuID'];
    $MenuName = $row['MenuName'];
    $Selected = "";
    if($MenuID == $ThisMenuID)
    {
      $Selected = "selected";
    }
    $MenuSelectList .= "<option $Selected value=$MenuID>$MenuName</option>";
  }
  $MenuSelectList .= "</select>";
  return($MenuSelectList);
}

function GetRolesForOption($ThisMenuOption)
{
  $sql = "SELECT
            ro.RoleID
            FROM dad.RoleMenuOption ro
            WHERE ro.MenuOptionID=$ThisMenuOption";
  $RolesThisOption = runQueryReturnArray($sql);

  if(!is_array($RolesThisOption)){
    $RolesThisOption = array();
  }
  
  foreach($RolesThisOption as $row)
  {
    $RolesWithAccess[$row['RoleID']] = 1;
  }
  return($RolesWithAccess);
}

function GetRoleTable($RolesWithAccess)
{
  $sql = "SELECT
            ro.RoleID,
            ro.RoleName,
            ro.RoleDescr
          FROM dad.Role ro";
  $RoleResults = runQueryReturnArray($sql);
  $RoleTable = "";
  foreach($RoleResults as $row)
  {
    $Checked = "";
    $RoleName = $row['RoleName'];
    $RoleID = $row['RoleID'];
    $RoleDesc = $row['RoleDescr'];
    if(isset($RolesWithAccess[$RoleID]))
    {
      $Checked = "checked";
    }
    $RoleTable .= "<input type=\"checkbox\" $Checked name=\"$RoleName\" value=\"$RoleID\">$RoleDesc</input><br>";
  }
  return($RoleTable);
}
function GetMenuOptionList($ThisMenuOption)
{
  $sql = "SELECT
            mo.MenuOptionID,
            mo.OptionName
          FROM dad.MenuOption mo
          ORDER BY mo.OptionName";
  $OptionResults = runQueryReturnArray($sql);
  $strOptionList = "<select name=\"SelectOption\" onchange=\"form.submit();\">";
  foreach($OptionResults as $row)
  {
    $OptionID = $row['MenuOptionID'];
    $OptionName = $row['OptionName'];
    $Selected = "";
    if($OptionID == $ThisMenuOption)
    {
      $Selected = "selected";
    }
    $strOptionList .= "<option $Selected value=$OptionID>$OptionName</option>";
  }
  $strOptionList .= "</select>";
  return($strOptionList);
}

function GetMenuOptionDetails($ThisMenuOption)
{
    $sql = "SELECT DISTINCT
                   mo.MenuOptionID,
                   mo.OptionName,
                   mo.SequenceNum OptionSequenceNum,
                   m.MenuID,
                   m.ParentMenuOptionID,
                   m.LevelNum,
                   m.SequenceNum MenuSequenceNum,
                   m.MenuName,
                   mo.ContentPathName,
                   mo.FunctionName,
                   rmo.RoleID
              FROM dad.UserRole ur
              LEFT JOIN dad.RoleMenuOption rmo ON rmo.MenuOptionID = $ThisMenuOption
              JOIN dad.MenuOption mo ON mo.MenuOptionID = rmo.MenuOptionID
              JOIN dad.Menu m ON m.MenuID = mo.MenuID
              WHERE mo.MenuOptionID = $ThisMenuOption";
  $aResults = runQueryReturnArray($sql);

  return($aResults[0]);
}

function SubmitOptionEdit()
{
  global $Global;
  
  // Validation is necessary, but will be added later.  Only software
  // developers will have access to this page in the long run, so the
  // validation is much less important.
  $NewOptionID = $Global['OptionToUpdate'];
  $NewOptionName = $Global['OptionName'];
  $ParentMenuID = $Global['ParentMenu'];
  $CodeLocation = $Global['CodeLocation'];
  $FunctionName = $Global['FunctionName'];
  $Sequence = $Global['Sequence'];
  $sql = "UPDATE dad.MenuOption SET 
            OptionName='$NewOptionName',
            MenuID=$ParentMenuID, 
            SequenceNum=$Sequence, 
            ContentPathName='$CodeLocation',
            FunctionName='$FunctionName'
          WHERE MenuOptionID=$NewOptionID";
  $sqlResult = runSQLReturnAffected($sql);
  if($sqlResult != 1)
  {
    add_element("Critical error updating the database.  Attempt to modify menu option resulted in $sqlResult rows affected.");
    return;
  }
  
  $sql = "DELETE FROM dad.RoleMenuOption WHERE MenuOptionID=$NewOptionID";
  $sqlResults = runSQLReturnAffected($sql);
  add_element("$sqlResults rows removed from the roles table.<BR>");
  $sql = "SELECT RoleID, RoleName
          FROM dad.Role";
  $RolesReturn = runQueryReturnArray($sql);
  foreach($RolesReturn as $row)
  {
    if(isset($Global[$row['RoleName']]))
    {
      $RolesToInsert[$row['RoleName']] = $row['RoleID'];
    }
  }
  if( is_array($RolesToInsert) ){
      foreach($RolesToInsert as $Role)
      {
        $sql = "INSERT INTO dad.RoleMenuOption (RoleID, MenuOptionID)
                VALUES ($Role, $NewOptionID)";
        $success = runInsertReturnID($sql);
        if(!$success)
        {
          add_element("Error inserting role ID $Role for $NewOptionID.");
        }
      }
  }else{
      /*if the user did not give it a role, we will default to Software Developer*/
      $sql = "INSERT INTO dad.RoleMenuOption (RoleID, MenuOptionID)
              VALUES (1, $NewOptionID)";
      $success = runInsertReturnID($sql);
      add_element("<font color=red>Default role asssigned</font><br>");
      if(!$success){
          add_element("Error inserting role ID $Role for $NewOptionID.");
      }
  }
/* Option ID already exists, no need to create a duplicate

  $OptionConstantName = "OPTIONID_".strtoupper($NewOptionName);
  $OptionConstantName = preg_replace("/ /", "_", $OptionConstantName);
//Add option to constants
  $OptionIDFile = fopen("../config/OptionIDs.php", "a+");
  fwrite($OptionIDFile, "define('$OptionConstantName', $NewOptionID);\n");
  fclose($OptionIDFile);
*/

//Add option text to literals
  $OptionIDFile = fopen("../scripts/E/Auto_added_literals.php", "a+");
  fwrite($OptionIDFile, "\$gaLiterals['$NewOptionName'] = '$NewOptionName';\n");
  fclose($OptionIDFile);
  add_element("Completed.  The literal translations will be available following the next page click or refresh.");
}

?>

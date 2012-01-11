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

function AddAlertGroup() {

    global $gaLiterals;
    global $Global;
    $strURL  = getOptionURL(OPTIONID_ADD_ALERT_GROUP);
    $strMsg  = '';

    if( checkOptionPermission( $Global['UserID'], $Global['OptionID'] ) == 0 ){
        dispatch( OPTIONID_LOGOUT );
        return;
    }

    if( isset($Global['bt']) && $Global['bt'] === $gaLiterals['Add'] ){

        //check to see if the group name exists
        $strSQL = "SELECT name FROM dad_adm_alertgroup WHERE name = '${Global['groupname']}'";
        $tmp    = runQueryReturnArray( $strSQL );

        if( isset($tmp[0][0]) ){
            $strMsg = '<font color=red><b>' . $gaLiterals['Already Exists'] . '</b></font>';
        } else {
            $strSQL = "INSERT INTO dad_adm_alertgroup( name, description, calleractive, timeactive ) VALUES( '${Global['groupname']}', '${Global['groupdesc']}', '${Global['txtUserName']}', NOW() )";
            $tmp = runInsertReturnID( $strSQL );
            if( isset($tmp) ){
                $strMsg = '<font color=red><b>' . $gaLiterals['Alert Group Added'] . '</b></font>';
            } else {
                logger( "ERROR: cannot add group; NAME: [${Global['groupname']}], DESCRIP: [${Global['groupdesc']}]" );
                $strMsg = '<font color=red><b>' . $gaLiterals['ERROR'] . '</b></font>';
            }
        }
    }

    $strHTML  = "<form action=$strURL method=post><table>";
    $strHTML .= '<tr><td><b>' . $gaLiterals['Group Name'] . ':</b></td><td><input type=text name=groupname id=groupname maxlength=30 value=' . $Global['groupname'] . '></td></tr>';
    $strHTML .= '<tr><td><b>' . $gaLiterals['Group Desc'] . ':</b></td><td><input type=text name=groupdesc id=groupdesc maxlength=100 value=' . $Global['groupdesc']  . '></td></tr>';
    $strHTML .= "<tr><td><input type=submit name=bt id=bt value=${gaLiterals['Add']}></td></tr>";
    $strHTML .= "</table></form>$strMsg";

    add_element( $strHTML );

}




function RemoveAlertGroup() {

    global $gaLiterals;
    global $Global;
    $strURL  = getOptionURL(OPTIONID_REMOVE_ALERT_GROUP);
    $strMsg  = '';

    if( checkOptionPermission( $Global['UserID'], $Global['OptionID'] ) == 0 ){
        dispatch( OPTIONID_LOGOUT );
        return;
    }

    if( isset($Global['bt']) && $Global['bt'] === $gaLiterals['Remove'] ){

        $strSQL = "DELETE FROM dad_adm_alertgroup WHERE id_dad_adm_alertgroup = '${Global['groupid']}' ";
        $tmp = runSQLReturnAffected( $strSQL );
        if( $tmp > 0 ){
            Logger( "Alert Group deleted; GroupID: [${Global['groupid']}]; GroupName: [${Global['groupname']}]; GroupDesc: ${Global['groupdesc']}" );
            $strMsg = '<font color=red><b>' . $gaLiterals['Success'] . '</b></font>';
        } else {
            Logger( "ERROR: Could not delete Alert Group: GroupID: [${Global['groupid']}]; GroupName: [${Global['groupname']}]" );
            $strMsg = '<font color=red><b>' . $gaLiterals['ERROR'] . '</b></font>';
        }

    }

    $strSQL  = "SELECT id_dad_adm_alertgroup, name FROM dad_adm_alertgroup ORDER BY name ASC";
    $ag_rows = runQueryReturnArray( $strSQL );

    $strHTML  = "<form action=$strURL method=post name=lookup>";
    $strHTML .= "<select name=selalertgroup id=selalertgroup>";
    if($ag_rows) {
		foreach( $ag_rows as $row ){

			$strHTML .= "<option value=$row[0]>$row[1]</option>";

		}
	}
    $strHTML .= "<input type=submit name=bt id=bt value=${gaLiterals['Lookup']}>";
    $strHTML .= "<br><hr>";

    if ( isset($Global['bt']) && $Global['bt'] === $gaLiterals['Lookup'] ){

        $strSQL  = "SELECT id_dad_adm_alertgroup, name, description FROM dad_adm_alertgroup WHERE id_dad_adm_alertgroup = '${Global['selalertgroup']}' ";
        $ag_rows = runQueryReturnArray( $strSQL );

        $strHTML .= "<table>";
        $strHTML .= "<tr><td><b>" . $gaLiterals['Group Name'] . ":</b></td><td><input type=text name=groupname id=groupname maxlength=30 readonly=true value='" . $ag_rows[0][1] . "'></td></tr>";
        $strHTML .= "<tr><td><b>" . $gaLiterals['Group Desc'] . ":</b></td><td><input type=text name=groupdesc id=groupdesc maxlength=100 readonly=true value='" . $ag_rows[0][2]  . "'></td></tr>";
        $strHTML .= "<tr><td><b>" . $gaLiterals['Group ID'] . ":</b></td><td><input type=text name=groupid id=groupid maxlength=100 readonly=true value='" . $ag_rows[0][0]  . "'></td></tr>";
        $strHTML .= "<tr><td><input type=submit name=bt id=bt value=${gaLiterals['Remove']}></td></tr>";
        $strHTML .= "</table>";

    }

    $strHTML .= "</form>$strMsg";

    add_element( $strHTML );

}




?>
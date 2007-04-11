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

/*-----------------------------------------------------
 * checkOptionPermission( $UserID, $OptionID )
 *-----------------------------------------------------
 * Will check to see if the $UserID has permission to run $OptionID.
 * Returns 1 for allowed, 0 for not allowed
 *
 */
function checkOptionPermission( $UserID, $OptionID ){
    $strSQL = "SELECT u.UserID 
               FROM User AS u
                 INNER JOIN UserRole AS ur
                   ON u.UserID = ur.UserID
                 INNER JOIN RoleMenuOption as rmo
                   ON ur.RoleID = rmo.RoleID
               WHERE u.UserID = '$UserID'
                 AND rmo.MenuOptionID = '$OptionID'";
    $arrUser = runQueryReturnArray( $strSQL );

    if( $arrUser ){
        return 1;
    } else {
        return 0;
    }
}


?>

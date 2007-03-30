<?php

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
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


function DisplayFS() {
    global $Global;

    if( checkOptionPermission( $Global['UserID'], OPTIONID_FILE_SYSTEM ) == 0 ){
        dispatch( OPTIONID_LOGOUT );
        return;
    }

    $strHTML  = '<script language="Javascript" src="javascript/WebLIBSmartTree.js"></script>' . "\n";
    $strHTML .= '<script language="Javascript">' . "\n";
    $strHTML .= '    function initialize() {' . "\n";
    $strHTML .= '        displaySmartTree("fs_XMLGenerateTree.php?session=' . $Global['SessionID'] . '", "objSmartTree", "", true);' . "\n";
    $strHTML .= '    }' . "\n";
    $strHTML .= '</script>' . "\n";
    $strHTML .= '<body onload="initialize();">' . "\n";
    $strHTML .= '<div id="objSmartTree"></div>' . "\n";

    add_element( $strHTML );

}



?>


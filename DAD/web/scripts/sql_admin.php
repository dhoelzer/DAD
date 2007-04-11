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

function sql_processlist() {

    global $gaLiterals;
    global $Global;

    if( checkOptionPermission( $Global['UserID'], $Global['OptionID'] ) == 0 ){
        dispatch( OPTIONID_LOGOUT );
        return;
    }

    $strURL  = getOptionURL(OPTIONID_SQL_PROCESS_LIST);
    $strSQL  = '';
    $strHTML = '';

    //if the Create button was click, will do the following code
    if( isset( $Global['bt'] ) && $Global['bt'] === $gaLiterals['Kill'] ) {
        while( (list($k, $v) = each($Global) ) ){
        if( preg_match( '/^sql_cb_(\d+)$/', $k, $matches ) ){
                runSQLReturnAffected( "kill ${matches[1]}" );
            }
        }
    }

    $arrProc = runQueryReturnArray( "show processlist" );
    
    $strHTML = "<b><font size=2>${gaLiterals['SQL Process List']}</font></b><br><br>\n";
    $strHTML.= "<form id='sqlprocesslist' action='$strURL' method='post'>\n
                <table border=on style='font-size:75%'>\n";
    foreach( $arrProc as $file ){
        $strHTML .= "<tr><td><input type='checkbox' name='sql_cb_${file[0]}'></td>";
        $flg_every_other = 0;
        foreach( $file as $col ){
            if( $flg_every_other == 0 ){
                $strHTML .= "<td>$col</td>";
                $flg_every_other = 1;
            }else{
                $flg_every_other = 0;
            }
        }
        $strHTML .= "</tr>";
    }
    $strHTML .= "</table><input type='button' name='bt' value='Refresh' onclick=\"window.navigate('$strURL')\">&nbsp;<input type='submit' name='bt' value='Kill'>";
    add_element($strHTML);
}

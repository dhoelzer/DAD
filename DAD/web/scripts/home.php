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

function showHomePage() {

    global $gaLiterals;

    $strHTML = $gaLiterals["Welcome"]."...";

    $strHTMLTable  = '<table>';
    $strHTMLTable .= '<COLGROUP>';
    $strHTMLTable .= '  <COL align=right width="10%">';    //Descriptions
    $strHTMLTable .= '  <COL align=left width="5%">';      //Counts
    $strHTMLTable .= '  <COL align=left width="85%">';     //remainder of white space on page
    $strHTMLTable .= '</COLGROUP>';
    $strHTMLTable .= '<tr><td>&nbsp;</td><td></td><td></td></tr>';


    /*Get the number of new folder that have shown up*/
    $strSQL   = 'SELECT COUNT(*) FROM dad_fs_path WHERE timeactive = (SELECT MAX(timeactive) FROM dad_fs_path) ';
    $rows = runQueryReturnArray( $strSQL );
    $strHTMLTable .= '<tr><td nowrap><b><a href=' . getOptionURL(OPTIONID_NEW_FILE_SYSTEM_ENTRIES) . ">${gaLiterals['Unreviewed']} ${gaLiterals['Folders']}:</a></b></td><td>&nbsp;" . $rows[0][0] . '</td></tr>';

    /*Get the number of unacknowledged events*/
    $strSQL   = 'SELECT COUNT(*) FROM dad_adm_log WHERE acknowledged != 1 ';
    $rows = runQueryReturnArray( $strSQL );
    $strHTMLTable .= '<tr><td nowrap><b><a href=' . getOptionURL(OPTIONID_SYSTEM_LOGS) . ">${gaLiterals['System']} ${gaLiterals['Events']}:</a></b></td><td>&nbsp;" . $rows[0][0] . '</td></tr>';

    $strHTMLTable .= '</table>';

    $strHTML .= $strHTMLTable;

    add_element($strHTML);
}

?>

<?php

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
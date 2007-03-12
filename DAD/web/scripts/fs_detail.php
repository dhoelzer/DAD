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

function fs_detail_show() {
    global $gaLiterals;
    global $Global;

    $strURL      = getOptionURL(OPTIONID_FS_DETAIL_SHOW);
    $strFolderID = ( isset($Global{'folder'}) ? $Global{'folder'} : '' );
    $strHTML     = '';
    $strSQL      = '';

    if( checkOptionPermission( $Global['UserID'], $Global['OptionID'] ) == 0 ){
        dispatch( OPTIONID_LOGOUT );
        return;
    }

    // BUILD PAGE //

    $strSQL   = "SELECT p.fullpath, p.depth, p.id_dad_fs_path, c.calleractive, c.timeactive, clr.name, acr.name, clw.name, acw.name, ag.name, p.timeactive
                 FROM dad_fs_path AS p
                   LEFT JOIN dad_fs_path_cl as c
                     ON p.id_dad_fs_path = c.id_dad_fs_path
                   LEFT JOIN dad_cl_classification as clr
                     ON c.id_dad_cl_classification_read = clr.id_dad_cl_classification
                   LEFT JOIN dad_cl_classification as clw
                     ON c.id_dad_cl_classification_write = clw.id_dad_cl_classification
                   LEFT JOIN dad_adm_action as acr
                     ON c.id_dad_adm_action_read = acr.id_dad_adm_action
                   LEFT JOIN dad_adm_action as acw
                     ON c.id_dad_adm_action_write = acw.id_dad_adm_action
                   LEFT JOIN dad_fs_alertgroup as fsag
                     ON c.id_dad_fs_path = fsag.id_dad_fs_path
                   LEFT JOIN dad_adm_alertgroup AS ag
                     ON fsag.id_dad_adm_alertgroup = ag.id_dad_adm_alertgroup
                 WHERE p.id_dad_fs_path = '$strFolderID'";
    $fol_rows = runQueryReturnArray( $strSQL );


    $strHTML .= "<h1>Folder Details</h1>";
    $strHTML .= "<form name=\"folderdetails\" id=\"folderdetails\" action=\"$strURL&compact=1\" method=\"post\">";
    $strHTML .= "<input type=\"hidden\" id=\"folder\" name=\"folder\" value=\"$strFolderID\">";
    $strHTML .= "<input type=\"hidden\" id=\"fldaltered\" name=\"fldalerted\">";
    $strHTML .= "<table>";
    $strHTML .= "<COLGROUP>";
    $strHTML .= "  <COL align=\"right\" width=\"20%\">";
    $strHTML .= "  <COL align=\"left\" width=\"20%\">";
    $strHTML .= "  <COL align=\"left\" width=\"20%\">";
    $strHTML .= "  <COL align=\"right\" width=\"20%\">";
    $strHTML .= "  <COL align=\"left\" width=\"20%\">";
    $strHTML .= "</COLGROUP>\n";

    $strHTML .= "<tr><td></td><td></td><td></td><td></td><td></td></tr>";

    // PATH //
    $strHTML .= "<tr><td><b>Path:</b></td><td nowrap colspan=\"4\">" . $fol_rows[0][0] . "</td></tr>";

    // TIME ACTIVE //
    $strHTML .= "<tr><td nowrap><b>Time Active:</b></td><td nowrap colspan=\"4\">" . $fol_rows[0][10] . "</td></tr>";

    // DEPTH //
    $strHTML .= "<tr><td><b>Depth:</b></td><td>" . $fol_rows[0][1] . "</td></tr>";

    // ID //
    $strHTML .= "<tr><td><b>ID:</b></td><td>" . $fol_rows[0][2] . "</td></tr>";

    // LAST EDITOR //
    $strHTML .= "<tr><td nowrap><b>Last Editor:</b></td><td>" . $fol_rows[0][3] . "</td><td></td><td nowrap><b>Edited On:</b></td><td nowrap>" . $fol_rows[0][4] . "</td></tr>\n";

    // READ CLASSIFICATION //
    $strHTML .= "<tr><td nowrap><b>Read Class:</b></td><td nowrap>" . $fol_rows[0][5] . "</td><td></td>";

    //READ ACTION //
    $strHTML .= "<td><b>Action:</b></td><td nowrap>" . $fol_rows[0][6] . "</td></tr>";

    // WRITE CLASSIFICATION //
    $strHTML .= "<tr><td nowrap><b>Write Class:</b></td><td nowrap>" . $fol_rows[0][7] . "</td><td></td>";

    //WRITE ACTION //
    $strHTML .= "<td><b>Action:</b></td><td>" . $fol_rows[0][8] . "</td></tr>";

    // ALERT GROUP //
    $strHTML .= "<tr><td><b>Alerted:</b></td><td>" . $fol_rows[0][9] . "</td></tr>";
       //starting at element number one since the above line took care of element zero
    for ( $i=1; $i<=count($fol_rows)-1; $i++ ) {
        $strHTML .= "<tr><td></td><td colspan=\"3\">" . $fol_rows[$i][9] . "</td></tr>";
    }

    $strHTML .= "</table>";
    $strHTML .= "<table>";


    // SECURITY //
    $strSQL = "SELECT ds.samaccountname, a.description, p.querytime
               FROM dad_fs_permission AS p
                 INNER JOIN dad_fs_dacl AS a
                   ON p.dacl = a.dacl
                 INNER JOIN dad_ds_wks AS ds
                   ON p.objectsid_dad_ds_object = ds.objectsid
               WHERE p.id_dad_fs_path = '$strFolderID'
                 AND p.querytime = ( SELECT MAX(querytime) FROM dad_fs_permission WHERE id_dad_fs_path = '$strFolderID' )

               UNION

               SELECT ds.samaccountname, a.description, p.querytime
               FROM dad_fs_permission AS p
                 INNER JOIN dad_fs_dacl AS a
                   ON p.dacl = a.dacl
                 INNER JOIN dad_ds_object AS ds
                   ON p.objectsid_dad_ds_object = ds.objectsid
               WHERE p.id_dad_fs_path = '$strFolderID'
                 AND p.querytime = ( SELECT MAX(querytime) FROM dad_fs_permission WHERE id_dad_fs_path = '$strFolderID' )
                 AND ds.querytime = ( SELECT MAX(querytime) FROM dad_ds_object )
               ORDER BY samaccountname ASC";
    $ds_rows = runQueryReturnArray( $strSQL );

    $strHTML .= "<tr><td nowrap><b>Security as of:</b></td><td colspan=\"3\" nowrap>" . $ds_rows[0][2] . "</td></tr>";
    $strHTML .= "<tr><td></td><td><i>object</i></td><td align=\"left\"><i>dacl</i></td></tr>";
    foreach ( $ds_rows as $row ) {
        $strHTML .= "<tr><td>&nbsp;</td><td valign=\"top\" sytle=\"border-bottom-style:solid;border-bottom-width:thin;border-bottom-color:grey;\">${row[0]}</td><td align=\"left\" colspan=\"2\">";
        $dacl = explode( ",", $row[1] );
        array_multisort($dacl, SORT_ASC );
        foreach ( $dacl as $d ) {
            $strHTML .= "$d<br>";
        }
        $strHTML .= "</td></tr>\n";
    }

    $strHTML .= "</table>";
    $strHTML .= "<input type=\"button\" name=\"bt\" id=\"bt\" value=\"Edit Settings\" onClick=\"javascript:window.open( '" . getOptionURL( OPTIONID_FS_DETAIL_EDIT ) . "&folder=$strFolderID&compact=1', '', 'height=600,width=600,status=yes,toolbar=no,menubar=no,location=no,scrollbars=yes,resizable=yes');window.back\">";
    $strHTML .= "<input type=\"button\" name=\"bt\" id=\"bt\" value=\"View History\" onClick=\"javascript:window.open( '" . getOptionURL( OPTIONID_FILE_SYSTEM_HISTORY ) . "&folder=$strFolderID&compact=1', '', 'height=600,width=600,status=yes,toolbar=no,menubar=no,location=no,scrollbars=yes,resizable=yes');window.back\">";
    $strHTML .= "</form>";

    add_element( $strHTML );

}


function fs_detail_edit() {
    global $gaLiterals;
    global $Global;
    $strURL      = getOptionURL(OPTIONID_FS_DETAIL_EDIT);
    $strFolderID = ( isset($Global{'folder'}) ? $Global{'folder'} : '' );
    $strMsg      = '';
    $strHTML     = '';
    $strSQL      = '';

    if( checkOptionPermission( $Global['UserID'], $Global['OptionID'] ) == 0 ){
        dispatch( OPTIONID_LOGOUT );
        return;
    }

    // SAVE DETAILS //
    if( $strFolderID === '' ){

        add_element( "<font color=\"red\"><b>Invalid Folder</b></font>" );

    } else {

        if( isset( $Global['bt'] ) && $Global['bt'] === $gaLiterals{'Save'} ){

            $Global['rbactionr'] = ( isset($Global['rbactionr']) ? $Global['rbactionr'] : 1 );
            $Global['rbactionw'] = ( isset($Global['rbactionw']) ? $Global['rbactionw'] : 1 );
            $Global['rbclassr']  = ( isset($Global['rbclassr']) ? $Global['rbclassr'] : 0 );
            $Global['rbclassw']  = ( isset($Global['rbclassw']) ? $Global['rbclassw'] : 0 );

            $grp_flg = '';

            // CONFIRM folder id existance; if doesn't exist, log event and logout; POST tampering
            $strSQL = "SELECT id_dad_fs_path FROM dad_fs_path WHERE id_dad_fs_path = '$strFolderID' ";

            $tmp = runQueryReturnArray( $strSQL );
            if( !isset($tmp[0][0]) ){

                logger( "ERROR: Invalid folder id: $strFolderID" );
                dispatch( OPTIONID_LOGOUT );
                return;

            }

            // CONFIRM action id values
            if( isset($Global['rbactionr']) && isset($Global['rbactionw']) ){

                $strSQL = "SELECT id_dad_adm_action FROM dad_adm_action WHERE activeyesno = 1 AND (id_dad_adm_action = '${Global['rbactionr']}' OR id_dad_adm_action = '${Global['rbactionw']}') ";
                $tmp = runQueryReturnArray( $strSQL );
                if( $Global['rbactionr'] == $Global['rbactionw'] ){

                    // if the two options are the same value, MySQL will only return one record, as long as the value is legitimate
                    if( isset($tmp) && count($tmp) != 1 ){

                        logger( "ERROR: Invalid class id: [${Global['rbactionr']}] or [${Global['rbactionw']}]" );
                        dispatch( OPTIONID_LOGOUT );
                        return;

                    }

                } else {

                    // if the two options are different values, MySQL will return two records, as long as the values are legitimate
                    if( isset($tmp) && count($tmp) != 2 ){

                        logger( "ERROR: Invalid class id: [${Global['rbactionr']}] or [${Global['rbactionw']}]" );
                        dispatch( OPTIONID_LOGOUT );
                        return;

                    }

                }

            } else {

                logger( "ERROR: Empty action id." );
                dispatch( OPTIONID_LOGOUT );
                return;

            }

            // CONFIRM classification id values
            if( isset($Global['rbclassr']) && isset($Global['rbclassw']) ){

                $strSQL = "SELECT id_dad_cl_classification FROM dad_cl_classification WHERE id_dad_cl_classification = '${Global['rbclassr']}' OR id_dad_cl_classification = '${Global['rbclassw']}' ";
                $tmp = runQueryReturnArray( $strSQL );
                if( $Global['rbclassr'] == $Global['rbclassw'] ){

                    // if the two options are the same value, MySQL will only return one record, as long as the value is legitimate
                    if( isset($tmp) && count($tmp) != 1 ){

                        logger( "ERROR: Invalid class id: [${Global['rbclassr']}] or [${Global['rbclassw']}]" );
                        dispatch( OPTIONID_LOGOUT );
                        return;

                    }

                } else {

                    // if the two options are different values, MySQL will return two records, as long as the values are legitimate
                    if( isset($tmp) && count($tmp) != 2 ){

                        logger( "ERROR: Invalid class id: [${Global['rbclassr']}] or [${Global['rbclassw']}]" );
                        dispatch( OPTIONID_LOGOUT );
                        return;

                    }

                }

            } else {

                logger( "ERROR: Empty class id." );
                dispatch( OPTIONID_LOGOUT );
                return;

            }

            // gather and check alert groups
            $strSQL  = "SELECT id_dad_adm_alertgroup FROM dad_adm_alertgroup";
            $ag_rows = runQueryReturnArray( $strSQL );
            foreach( $ag_rows as $row ){
                $grps[$row[0]] = '1';
            }
            $tmp     = array_keys( $Global );

            foreach( $tmp as $val ){

                if( preg_match( '/cbalerted\d+/', $val ) ){

                    if( !$grps[$Global[$val]] ){

                        logger( "ERROR: Invalid alert group id: [${Global[$val]}]" );
                        dispatch( OPTIONID_LOGOUT );
                        return;

                    } else {

                        //will set the value to two so that we know to insert this one. This will save having to loop through all the $Global again.
                        $grps[$Global[$val]] = 2;
                        $grp_flg = 1;

                    }    //end if( !$grps

                }        //end if( preg_match

            }            //end foreach

            // IF YOU MAKE IT THIS FAR AND HAVE NOT BEEN LOGGED OUT, THEN ALL YOUR VALUES MUST BE GOOD. WE WILL NOW INSERT THESE VALUES INTO THE DATABASE //

            // DELETE and then INSERT classifications and actions
            $strSQL = "DELETE FROM dad_fs_path_cl WHERE id_dad_fs_path = '$strFolderID'";
            runSQLReturnAffected( $strSQL );

            $strSQL = "INSERT INTO dad_fs_path_cl( id_dad_fs_path, id_dad_cl_classification_read, id_dad_cl_classification_write, id_dad_adm_action_read, id_dad_adm_action_write, calleractive, timeactive ) VALUES ( '$strFolderID', '${Global['rbclassr']}', '${Global['rbclassw']}', '${Global['rbactionr']}', '${Global['rbactionw']}', '${Global['txtUserName']}', NOW() )";
            $tmp = runSQLReturnAffected( $strSQL );
            if( $tmp != 1 ){

                $strMsg = "<font color=\"red\"><b>${gaLiterals['ERROR']}</b></font>";
                Logger( "ERROR: unable to INSERT into dad_fs_path; folder id [$strFolderID]" );

            } else {

                // DELETE and then INSERT alerted groups
                $strSQL = "DELETE FROM dad_fs_alertgroup WHERE id_dad_fs_path = '$strFolderID'";
                runSQLReturnAffected( $strSQL );

                if( $grp_flg === 1 ){

                    $strSQL = "INSERT INTO dad_fs_alertgroup( id_dad_fs_path, id_dad_adm_alertgroup, calleractive, timeactive ) VALUES";
                    while( list( $k, $v ) = each( $grps ) ){
                        if( $v == 2 ){
                            $strSQL .= " ( '$strFolderID', '$k', '${Global['txtUserName']}', NOW() ),";
                        }
                    }
                    $strSQL = substr( $strSQL, 0, strlen($strSQL)-1 );
                    $tmp = runSQLReturnAffected( $strSQL );
                    if( !$tmp >= 1 ){
                        $strMsg = "<font color=\"red\"><b>${gaLiterals['ERROR']}</b></font>";
                        Logger( "ERROR: unable to INSERT into dad_fs_alertgroup; folder id [$strFolderID]" );
                    }

                }        //end if( $grp_flg

            }            //end if INSERT INTO dad_fs_path_cl

        }                //end if( isset( $Global['bt'] )

    }                    //end if( $strFolderID === '' )

    // BUILD PAGE //

    $strSQL   = "SELECT p.fullpath, p.depth, p.id_dad_fs_path, c.calleractive, c.timeactive, c.id_dad_cl_classification_read, c.id_dad_cl_classification_write, c.id_dad_adm_action_read, c.id_dad_adm_action_write, p.timeactive
                 FROM dad_fs_path AS p 
                   LEFT JOIN dad_fs_path_cl as c
                     ON p.id_dad_fs_path = c.id_dad_fs_path
                 WHERE p.id_dad_fs_path = '$strFolderID'";
    $fol_rows = runQueryReturnArray( $strSQL );

    $strHTML  = "<SCRIPT language=\"jscript\">
                    function selalerted_onclick(){
                        var sel = document.forms[0].document.all.selalerted;
                        var fld = document.forms[0].document.all.fldalerted;
                        var str = '';

                        for( i=0; (i <= sel.options.length-1); i++ ){
                            if (sel.options[i].selected){
                                str += sel.options[i].text + '; ';
                            }
                        }

                        fld.value = str;
                        alert( fld.value );
                    }
                 </SCRIPT>\n";

    $strHTML .= "<h1>Folder Details</h1>";
    $strHTML .= "<form name=\"folderdetails\" id=\"folderdetails\" action=\"$strURL&compact=1\" method=\"post\">";
    $strHTML .= "<input type=\"hidden\" id=\"folder\" name=\"folder\" value=\"$strFolderID\">";
    $strHTML .= "<table>";
    $strHTML .= "<COLGROUP>";
    $strHTML .= "  <COL align=\"right\" width=\"20%\">";
    $strHTML .= "  <COL align=\"left\" width=\"20%\">";
    $strHTML .= "  <COL align=\"left\" width=\"20%\">";
    $strHTML .= "  <COL align=\"right\" width=\"20%\">";
    $strHTML .= "  <COL align=\"left\" width=\"20%\">";
    $strHTML .= "</COLGROUP>\n";

    $strHTML .= "<tr><td></td><td></td><td></td><td></td><td></td></tr>";

    // PATH //
    $strHTML .= "<tr><td><b>Path:</b></td><td nowrap colspan=\"4\">" . $fol_rows[0][0] . "</td></tr>";

    // TIME ACTIVE //
    $strHTML .= "<tr><td nowrap><b>Time Active:</b></td><td nowrap colspan=\"4\">" . $fol_rows[0][9] . "</td></tr>";

    // DEPTH //
    $strHTML .= "<tr><td><b>Depth:</b></td><td>" . $fol_rows[0][1] . "</td></tr>";

    // ID //
    $strHTML .= "<tr><td><b>ID:</b></td><td>" . $fol_rows[0][2] . "</td></tr>";

    // LAST EDITOR //
    $strHTML .= "<tr><td nowrap><b>Last Editor:</b></td><td>" . $fol_rows[0][3] . "</td><td></td><td nowrap><b>Edited On:</b></td><td nowrap>" . $fol_rows[0][4] . "</td></tr>\n";

    // READ CLASSIFICATION //
    $strHTML .= "<tr><td valign=\"top\"><b>Read Class:</b></td><td nowrap>";
        //Build classification radio button list
        $strSQL = "SELECT id_dad_cl_classification, name, color FROM dad_cl_classification ORDER BY id_dad_cl_classification ASC";
        $cl_rows = runQueryReturnArray( $strSQL );
        foreach ( $cl_rows as $row ) {
            if( $fol_rows[0][5] == $row[0] ){
                $strHTML .= "<INPUT TYPE=\"radio\" name=\"rbclassr\" value=\"$row[0]\" style=\"color:${row[2]}\" CHECKED>${row[1]}<br>\n";
            } else {
                $strHTML .= "<INPUT TYPE=\"radio\" name=\"rbclassr\" value=\"$row[0]\" style=\"color:${row[2]}\">${row[1]}<br>\n";
            }
        }
    $strHTML .= "</td><td></td><td valign=\"top\"><b>Action:</b></td><td valign=\"top\" nowrap>";
        //Build Action drop down list
        $strSQL = "SELECT id_dad_adm_action, name FROM dad_adm_action WHERE activeyesno = 1 ORDER BY name ASC";
        $ac_rows = runQueryReturnArray( $strSQL );
        foreach ( $ac_rows as $row ) {
            if( $fol_rows[0][7] == $row[0] ){
                $strHTML .= "<INPUT TYPE=\"radio\" name=\"rbactionr\" value=\"$row[0]\" CHECKED>${row[1]}<br>\n";
            } else {
                $strHTML .= "<INPUT TYPE=\"radio\" name=\"rbactionr\" value=\"$row[0]\">${row[1]}<br>\n";
            }
        }
    $strHTML .= "</td></tr>";

    // WRITE CLASSIFICATION //
    $strHTML .= "<tr><td valign=\"top\" nowrap><b>Write Class:</b></td><td nowrap>";
        //Build classification dropdown list
        foreach ( $cl_rows as $row ) {
            if( $fol_rows[0][6] == $row[0] ){
                $strHTML .= "<INPUT TYPE=\"radio\" name=\"rbclassw\" value=\"$row[0]\" style=\"color:${row[2]}\" CHECKED>${row[1]}<br>\n";
            } else {
                $strHTML .= "<INPUT TYPE=\"radio\" name=\"rbclassw\" value=\"$row[0]\" style=\"color:${row[2]}\">${row[1]}<br>\n";
            }
        }
    $strHTML .= "</td><td></td><td valign=\"top\"><b>Action:</b></td><td valign=\"top\" nowrap>";
        //Build Action drop down list
        foreach ( $ac_rows as $row ) {
            if( $fol_rows[0][8] == $row[0] ){
                $strHTML .= "<INPUT TYPE=\"radio\" name=\"rbactionw\" value=\"$row[0]\" CHECKED>${row[1]}<br>\n";
            } else {
                $strHTML .= "<INPUT TYPE=\"radio\" name=\"rbactionw\" value=\"$row[0]\">${row[1]}<br>\n";
            }
        }
    $strHTML .= "</SELECT></td></tr>";

    // ALERT GROUP //
    $strHTML .= "<tr><td valign=\"top\"><b>Alerted:</b></td>";
        //Build list of owners
        $strSQL   = "SELECT id_dad_adm_alertgroup, name FROM dad_adm_alertgroup ORDER BY name ASC";
        $grp_rows = runQueryReturnArray( $strSQL );
        $strSQL   = "SELECT ag.id_dad_adm_alertgroup, ag.name FROM dad_fs_alertgroup AS fsag INNER JOIN dad_adm_alertgroup AS ag ON fsag.id_dad_adm_alertgroup = ag.id_dad_adm_alertgroup WHERE fsag.id_dad_fs_path = '$strFolderID' ORDER BY ag.name ASC";
        $ag_rows  = runQueryReturnArray( $strSQL );
        $cnt      = 0;
        $grps     = '';

        foreach( $ag_rows as $row ){
            $grps[$row[0]] = 1;
        }

        foreach( $grp_rows as $row ){
            if( isset($grps[$row[0]]) ){
                $strChk = 'CHECKED';
            } else {
                $strChk = '';
            }
            if( $cnt == 3 ){
                $cnt = 1;
                $strHTML .= "</tr><td><td><INPUT TYPE=\"checkbox\" name=\"cbalerted$row[0]\" value=\"$row[0]\" $strChk>${row[1]}</td>";

            } else {
                $cnt++;
                $strHTML .= "<td><INPUT TYPE=\"checkbox\" name=\"cbalerted$row[0]\" value=\"$row[0]\"  $strChk>${row[1]}</td>";
            }

        }
    $strHTML .= "</td></tr>";

    $strHTML .= "</table>";
    $strHTML .= "<table>";


    // SECURITY //
    $strSQL = "SELECT ds.samaccountname, a.description, p.querytime
               FROM dad_fs_permission AS p
                 INNER JOIN dad_fs_dacl AS a
                   ON p.dacl = a.dacl
                 INNER JOIN dad_ds_wks AS ds
                   ON p.objectsid_dad_ds_object = ds.objectsid
               WHERE p.id_dad_fs_path = '$strFolderID'
                 AND p.querytime = ( SELECT MAX(querytime) FROM dad_fs_permission WHERE id_dad_fs_path = '$strFolderID' )

               UNION

               SELECT ds.samaccountname, a.description, p.querytime
               FROM dad_fs_permission AS p
                 INNER JOIN dad_fs_dacl AS a
                   ON p.dacl = a.dacl
                 INNER JOIN dad_ds_object AS ds
                   ON p.objectsid_dad_ds_object = ds.objectsid
               WHERE p.id_dad_fs_path = '$strFolderID'
                 AND p.querytime = ( SELECT MAX(querytime) FROM dad_fs_permission WHERE id_dad_fs_path = '$strFolderID' )
                 AND ds.querytime = ( SELECT MAX(querytime) FROM dad_ds_object )
               ORDER BY samaccountname ASC";

    $ds_rows = runQueryReturnArray( $strSQL );
    $strHTML .= "<tr><td nowrap><b>Security as of:</b></td><td colspan=\"3\" nowrap>" . $ds_rows[0][2] . "</td></tr>";
    $strHTML .= "<tr><td></td><td><i>object</i></td><td colspan=\"2\"><i>dacl</i></td></tr>";
    foreach ( $ds_rows as $row ) {
        $strHTML .= "<tr><td></td><td valign=\"top\">${row[0]}</td><td colspan=\"2\">";
        $dacl = explode( ",", $row[1] );
        array_multisort($dacl, SORT_ASC );
        foreach ( $dacl as $d ) {
            $strHTML .= "$d<br>";
        }
        $strHTML .= "</td></tr>";
    }
    $strHTML .= "</table>";
    $strHTML .= "<input type=\"submit\" name=\"bt\" id=\"bt\" value=\"" . $gaLiterals{'Save'} . "\">";
    $strHTML .= "<input type=\"button\" name=\"bt\" id=\"bt\" value=\"View History\" onClick=\"javascript:window.open( '" . getOptionURL( OPTIONID_FILE_SYSTEM_HISTORY ) . "&folder=$strFolderID&compact=1', '', 'height=600,width=600,status=yes,toolbar=no,menubar=no,location=no,scrollbars=yes,resizable=yes');window.back\">";
    $strHTML .= "<br>$strMsg</form>";

    add_element( $strHTML );

}




function fs_detail_history_show() {
    global $gaLiterals;
    global $Global;

    $strURL        = getOptionURL( OPTIONID_FILE_SYSTEM_HISTORY );
    $strCompact    = ( isset($Global{'compact'}) ? $Global{'compact'} : '0' );
    $strFolderID   = ( isset($Global{'folder'}) ? $Global{'folder'} : '' );
    $strFolderName = ( isset($Global{'fldname'}) ? $Global{'fldname'} : '' );
    $strQueryTime  = ( isset($Global{'fldquerytime'}) ? $Global{'fldquerytime'} : '' );
    $strHTML       = '';
    $strSQL        = '';

    if( checkOptionPermission( $Global['UserID'], $Global['OptionID'] ) == 0 ){
        dispatch( OPTIONID_LOGOUT );
        return;
    }

    if( isset($strFolderName) && $strFolderName != '' ){

        $strSQL  = "SELECT id_dad_fs_path FROM dad_fs_path WHERE fullpath = '$strFolderName'";
        $ds_rows = runQueryReturnArray( $strSQL );
        $strFolderID = $ds_rows[0][0];

        $strFolderName = preg_replace('/\\\\\\\\/', '\\', $strFolderName);

    }else if( isset($strFolderID) && $strFolderID != '' ){

        $strSQL  = "SELECT fullpath FROM dad_fs_path WHERE id_dad_fs_path = '$strFolderID'";
        $ds_rows = runQueryReturnArray( $strSQL );
        $strFolderName = $ds_rows[0][0];

    }

    if( !isset($strQueryTime) | $strQueryTime == '' ){

        $arrDate = getdate();
        $strQueryTime = $arrDate['year'] . '-' . $arrDate['mon'] . '-' . $arrDate['mday'];

    }

    $strHTML .= "<h1>Folder History Details</h1>";
    $strHTML .= "<form name=\"folderdetails\" id=\"folderdetails\" action=\"$strURL&compact=$strCompact\" method=\"post\">";
    $strHTML .= "<input type=\"hidden\" id=\"folder\" name=\"folder\" value=\"$strFolderID\">";
    $strHTML .= "<input type=\"hidden\" id=\"fldaltered\" name=\"fldalerted\">";
    $strHTML .= "<table>";
    $strHTML .= "<COLGROUP>";
    $strHTML .= "  <COL align=\"right\">";
    $strHTML .= "  <COL align=\"left\">";
    $strHTML .= "  <COL align=\"left\">";
    $strHTML .= "  <COL align=\"left\">";
    $strHTML .= "</COLGROUP>";

    if( isset( $Global['bt'] ) && $Global['bt'] === $gaLiterals{'Lookup'} ){

        // SECURITY //
        $strSQL = "SELECT ds.samaccountname, a.description, p.querytime
                   FROM dad_fs_permission AS p
                     INNER JOIN dad_fs_dacl AS a
                       ON p.dacl = a.dacl
                     INNER JOIN dad_ds_wks AS ds
                       ON p.objectsid_dad_ds_object = ds.objectsid
                   WHERE p.id_dad_fs_path = '$strFolderID'
                     AND p.querytime BETWEEN '$strQueryTime 00:00:00' AND '$strQueryTime 23:59:59'

                   UNION

                   SELECT ds.samaccountname, a.description, p.querytime
                   FROM dad_fs_permission AS p
                     INNER JOIN dad_fs_dacl AS a
                       ON p.dacl = a.dacl
                     INNER JOIN dad_ds_object AS ds
                       ON p.objectsid_dad_ds_object = ds.objectsid
                   WHERE p.id_dad_fs_path = '$strFolderID'
                     AND p.querytime BETWEEN '$strQueryTime 00:00:00' AND '$strQueryTime 23:59:59'
                     AND ds.querytime BETWEEN '$strQueryTime 00:00:00' AND '$strQueryTime 23:59:59'
                   ORDER BY samaccountname ASC";

        $ds_rows = runQueryReturnArray( $strSQL );

        if( count($ds_rows) > 0 ){

            $strHTML .= "<tr><td colspan=\"3\" align=\"left\"><b>Security as of: </b>" . $ds_rows[0][2] . "</td></tr>";
            $strHTML .= "<tr><td></td><td><i>object</i></td><td><i>dacl</i></td></tr>";
            foreach ( $ds_rows as $row ) {
                $strHTML .= "<tr><td>&nbsp;</td><td valign=\"top\">${row[0]}</td><td align=\"left\" colspan=\"2\">";

                $dacl = explode( ",", $row[1] );
                array_multisort($dacl, SORT_ASC );
                foreach ( $dacl as $d ) {
                    $strHTML .= "$d<br>";
                }

                $strHTML .= "</td></tr>\n";

            }

        } else {

            $strHTML .= "<tr><td colspan=\"3\" align=\"left\"><font color=\"red\"><b>Sorry, there is no information available for that date.</b></font></td></tr>";

            $strSQL = "SELECT fullpath FROM dad_fs_path WHERE id_dad_fs_path = '$strFolderID'";
            $ds_rows = runQueryReturnArray( $strSQL );
            preg_match("/^([^\\\]+)/i",$ds_rows[0][0], $matches);
            $strSQL = "SELECT message FROM dad_adm_log WHERE message like '%${matches[0]}.txt%' AND eventtime BETWEEN '$strQueryTime 00:00:00' AND '$strQueryTime 23:59:59'";
            $ds_rows = runQueryReturnArray( $strSQL );
            
            if( count($ds_rows) > 0 ){
                $strHTML .= "<tr><td colspan=\"3\" align=\"left\"><font size=\"1\"><font color=\"red\"><b>Log entry: </b></font>" . $ds_rows[0][0] . "</font></td></tr>";
            }


        }

    }

    $strHTML .= "<tr><td>&nbsp;</td></tr>";
    $strHTML .= "<tr><td><b>Folder:</b></td><td><input type=\"text\" name=\"fldname\" size=\"40\" value=\"$strFolderName\"></td><td><i>No leading or trailing slashes</i></td></tr>";
    $strHTML .= "<tr><td><b>Date:</b></td><td><input type=\"text\" name=\"fldquerytime\" size=\"40\" value=\"$strQueryTime\"></td><td><i>yyyy-mm-dd</i></td></tr>";
    $strHTML .= "<tr><td><input type=\"submit\" name=\"bt\" id=\"bt\" value=\"" . $gaLiterals{'Lookup'} . "\"></td></tr>";
    $strHTML .= "</table>";
    $strHTML .= "</form>";

    add_element( $strHTML );

}




function fs_new_show() {
    global $gaLiterals;
    global $Global;

    $rows      = '';
    $strURL    = getOptionURL( OPTIONID_FS_NEW_SHOW );
    $strHTML   = '';
    $strSQL    = '';
    $arrAction = array();

    if( checkOptionPermission( $Global['UserID'], $Global['OptionID'] ) == 0 ){
        dispatch( OPTIONID_LOGOUT );
        return;
    }

    $strSQL = 'SELECT id_dad_adm_action, abbreviation FROM dad_adm_action WHERE abbreviation IS NOT NULL';
    $rows   = runQueryReturnArray( $strSQL );
    if($rows) {
		foreach( $rows as $row ){
			$arrAction[$row[0]] = $row[1];
		}
	}

/*THIS WHERE STATEMENT HAS TO CHANGE IN THIS WHEN THE JOB IS MARKING RESOURCES WITH INHERITED RIGHTS*/
    $strSQL = "CREATE TEMPORARY TABLE tbl( id int, date date, fullpath text, cl_read tinyint, ac_read tinyint, cl_write tinyint, ac_write tinyint );\n
               INSERT INTO tbl( id, date, fullpath, cl_read, ac_read, cl_write, ac_write )
                 SELECT p.id_dad_fs_path, DATE(p.timeactive), p.fullpath, id_dad_cl_classification_read, id_dad_adm_action_read, id_dad_cl_classification_write, id_dad_adm_action_write
                 FROM dad_fs_path AS p
                   LEFT JOIN dad_fs_path_cl AS c
                     ON p.id_dad_fs_path = c.id_dad_fs_path
                 WHERE p.timeactive = (SELECT MAX(timeactive) FROM dad_fs_path)
                 LIMIT 100;\n
               SELECT id, date, fullpath, cl_read, ac_read, cl_write, ac_write
               FROM tbl
               ORDER BY fullpath ASC;";
    $rows   = runQueryReturnArray( $strSQL );

    $strHTML .= '<script language=\"javascript\">
                     function check_all(){
                         var frm = document.formunreviewed;//.document.all;
                         var cnt = frm.length;

                         if( frm.document.all.cball.checked == "1" ){
                             //alert( "check on" );
                             var tmp;
                             for ( i=1; i<cnt; i++ ){
                                 tmp = frm[i].name;
                                 tmp = tmp.substr(0,2);
                                 if( tmp == "cb" ){
                                     frm[i].checked = 1;
                                 }
                             }
                         }else{
                             //alert( "check off" );
                             var tmp;
                             for ( i=1; i<cnt; i++ ){
                                 tmp = frm[i].name;
                                 tmp = tmp.substr(0,2);
                                 if( tmp == "cb" ){
                                     frm[i].checked = 0;
                                 }
                             }
                         }

                     }
                </script>';

    $strHTML .= "<h1>Unreviewed Folders</h1>";
    $strHTML .= "<form name=\"formunreviewed\" id=\"frmunreviewed\" method=\"post\" action=\"$strURL\">";
    $strHTML .= "<table border=\"1\" bordercolor=\"silver\">";
    $strHTML .= "<COLGROUP>";
    $strHTML .= "  <COL align=\"left\" width=\"2%\">";     //checkbox
    $strHTML .= "  <COL align=\"left\" width=\"5%\">";     //date
    $strHTML .= "  <COL align=\"left\" width=\"10%\">";    //classification
    $strHTML .= "  <COL align=\"left\" width=\"73%\">";    //path
    $strHTML .= "</COLGROUP>";
    $strHTML .= "<tr><td colspan=\"4\"><input type=\"submit\" name=\"bt\" id=\"bt\" value=\"${gaLiterals['Acknowledge']}\"></td></tr>";
    $strHTML .= "<tr><td><input type=\"checkbox\" name=\"cball\" id=\"cball\" onclick=\"check_all();\"></td><td><b>Class</b></td><td><b>Date</b></td><td><b>Path</b></td></tr>";

    if($rows){
		foreach( $rows as $row ){

			$strHTML .= "<tr><td><input type=\"checkbox\" name=\"cb${row[0]}\"></td>
                         <td>" . $row[3] . $arrAction[$row[4]] . $row[5] . $arrAction[$row[6]] . "</td>
                         <td nowrap>${row[1]}</td>
                         <td><a href=\"javascript:window.open( '" . getOptionURL( OPTIONID_FS_DETAIL_EDIT ) . "&folder=${row[0]}&compact=1', '', 'height=600,width=600,status=yes,toolbar=no,menubar=no,location=no,scrollbars=yes,resizable=yes');window.back\">${row[2]}</a></td></tr>";

		}
	}
	
    $strHTML .= '</form>';

    add_element( $strHTML );    

}



?>
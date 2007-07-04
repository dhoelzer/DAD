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


require_once("../lib/strings.php");


function systems_edit() {

    global $gaLiterals;
    global $Global;

    if( checkOptionPermission( $Global['UserID'], $Global['OptionID'] ) == 0 ){
        dispatch( OPTIONID_LOGOUT );
        return;
    }
    add_element( "<div class=\"page_head_name\">${gaLiterals['Systems']}</div>" );

    $arrLogThese = array();
    $arrServices = array();
    $flgBad = '';
    $strURL = getOptionURL(OPTIONID_SYSTEMS);

    /*build list of bitmasks for different services*/
    $arr = runQueryReturnArray( 'SELECT log_these_id FROM dad_sys_services WHERE log_these_id > 0' );
    foreach( $arr as $a ){
        array_push( $arrServices, $a[0] );
    }
    $arr = NULL;

    if( (isset( $Global['bt'] ) && $Global['bt'] === $gaLiterals['Update']) || (isset( $Global['form_action'] ) && $Global['form_action'] === 'saveasnew') ) {

        if( !isset( $Global['system_name'] ) || $Global['system_name'] == '' ) {
            add_element( "<div class=\"response_text\">${gaLiterals['Description']} ${gaLiterals['Required']}</div>" );
            $flgBad = 1;
        }

        /*if all the above checks pass, will go ahead and create the user*/
        if( $flgBad != 1 ){

            $bitmask = 0;

            /*we blank out system_id here because we are trying to save this data as a new entry, thus we want
              a new id to be assigned*/
            if( isset($Global['form_action']) && $Global['form_action'] === 'saveasnew' ){
                $Global['system_id'] = '';
            }

            /*we delete and then re-insert; if there's no id to be begin with, then nothing can be delete - by design*/
            $strSQL = "DELETE dad_sys_event_import_from FROM dad_sys_event_import_from WHERE system_name='${Global['system_name']}'";
            $strAff = runSQLReturnAffected( $strSQL );
            $strSQL = "DELETE dad_sys_systems FROM dad_sys_systems WHERE system_id = '${Global['system_id']}'";
            $strAff = runSQLReturnAffected( $strSQL );
            $strSQL = "DELETE dad_adm_computer_group_member FROM dad_adm_computer_group_member WHERE system_id = '${Global['system_id']}'";
            $strAff = runSQLReturnAffected( $strSQL );

            $strSQL = "INSERT INTO dad_sys_systems( 
                system_id,
                system_name,
                contact_information
              ) VALUES ( 
                " . (isset($Global['system_id']) && $Global['system_id'] > 0 ? "'${Global['system_id']}'":'NULL') . ",
                '${Global['system_name']}',
                '${Global['contact_information']}'
              )";
            $strID = runInsertReturnID( $strSQL );
            $Global['system_id'] = $strID;

            /*split cbservices values out... the number appended on the name of the check box is the bit to be stored*/
            /*e.g. - cbservice1 and cbservices4: 1 + 4 = 5;*/
            while( list($k,$v) = each($Global) ){
                $arr = explode('cbservices',$k);
                if( isset($arr[1]) ){
                    $bitmask += $arr[1];
                }
            }
            $strSQL = "INSERT INTO dad_sys_event_import_from( system_name, priority, next_run, log_these ) 
                       VALUES( '${Global['system_name']}', ". (isset($Global['priority'])?$Global['priority']:0)  . ",unix_timestamp(), $bitmask )";
            $strID = runInsertReturnID( $strSQL );
            
            /*split Computer Group entries*/
            $arr = explode('~~~',$Global['selectedgroups_list']);
            foreach( $arr as $a ){
                if( isset($a) && $a >=1 ){
                    /*will check for the existance of this group membership*/
                    $strSQL = "SELECT id_dad_adm_computer_group
                               FROM dad_adm_computer_group_member
                               WHERE system_id = ${Global['system_id']}
                               AND id_dad_adm_computer_group = $a";
                    if( runSQLReturnAffected( $strSQL ) == 0 ){
                        $strSQL = "INSERT INTO dad_adm_computer_group_member( system_id, id_dad_adm_computer_group, calleractive, timeactive ) 
                                    VALUES ( ${Global['system_id']}, $a, '${Global['txtUserName']}',unix_timestamp() )";
                        runSQLReturnAffected( $strSQL );
                    }
                }
            }

            add_element( "<div class=\"response_text\">Successfully added</div>" );

            /* LOGGING
             logger( "JOB CREATION SUCCESS: UserID: $strUserID; UserName: ${Global['username']}; FirstName: ${Global['firstname']}'; LastName: ${Global['lastname']}; Email: ${Global['email']}; RoleID: ${Global['role']}; " );*/

        }

    }

    if( isset( $Global['form_action'] ) && $Global['form_action'] === 'delete' ) {
        $strSQL = "DELETE dad_sys_event_import_from FROM dad_sys_event_import_from WHERE system_name='${Global['system_name']}'";
        $strAff = runSQLReturnAffected( $strSQL );
        $strSQL = "DELETE dad_sys_systems FROM dad_sys_systems WHERE system_id='${Global['system_id']}'";
        $strAff = runSQLReturnAffected( $strSQL );
        if( $strAff ){
            add_element( "<div class=\"response_text\">${gaLiterals['Deleted']} \"${Global['system_name']}\"</div>" );
        }else{
            add_element( "<div class=\"response_text\">${gaLiterals['Error Deleting']}</div>" );
        }
    }

    if( isset( $Global['form_action'] ) && ($Global['form_action'] === 'lookup' || (isset($Global['bt']) && $Global['bt'] === $gaLiterals['Update']) || $Global['form_action'] === 'saveasnew') ) {
        $strSQL = "SELECT sys.system_id, sys.system_name, loc.location_name, sys.timezone, os.os_name, sys.ip_address, sys.contact_information, import.log_these, import.priority, import.next_run
                   FROM dad_sys_systems AS sys
                     LEFT JOIN dad_sys_location AS loc ON sys.location_id = loc.location_id
                     LEFT JOIN dad_sys_os AS os ON sys.os_id = os.os_id
                     LEFT JOIN dad_sys_event_import_from AS import ON sys.system_name = import.system_name
                   WHERE sys.system_id=${Global['system_id']}";
        $arrDetails = runQueryReturnArray( $strSQL );
        if( isset($arrDetails) ){
            $arrDetails = array_shift( $arrDetails );
            $arrLogThese = bitmask_to_array($arrDetails['log_these'],$arrServices);
        }
    }

    $strHTML = "<SCRIPT ID=\"clientEventHandlersJS\" LANGUAGE=\"javascript\" TYPE=\"text/javascript\" src=\"javascript/dad.js\"></SCRIPT>";
    $strHTML .="
      <form id=\"system_edit\" action=\"$strURL\" method=\"post\">\n
        <input type=\"hidden\" name=\"form_action\" id=\"form_action\">
        <input type=\"hidden\" name=\"selectedgroups_list\" id=\"selectedgroups_list\">
        <table>
          <colgroup valign=top></colgroup>
          <tr>
            <td align=\"right\">${gaLiterals['Systems']}:</td>
            <td colspan=3>";
    $strHTML .= build_drop_down( 
                    'SELECT system_id, system_name FROM dad_sys_systems ORDER BY system_name ASC', 
                    'system_id', 
                    (isset($arrDetails)? $arrDetails['system_id'] : ""), 
                    "onchange=\"record_action_and_submit('lookup');\""
                );
    $strHTML .="
            <INPUT type=submit name=bt id=bt value=\"${gaLiterals['Update']}\">
            <INPUT type=button name=bt id=bt value=\"${gaLiterals['Save as New']}\" onclick=\"record_action_and_submit('saveasnew');\">
            <INPUT type=button name=bt id=bt value=\"${gaLiterals['Delete']}\" onclick=\"delete_bt_click(system_id);\">
            <INPUT type=button name=bt id=bt value=\"${gaLiterals['New']}\" onclick=\"window.navigate('$strURL');\">
            <INPUT type=button name=bt id=bt value=\"${gaLiterals['Refresh']}\" onclick=\"record_action_and_submit('lookup');\">
            </td>
          </tr><tr>
            <td align=\"right\" nowrap>System Name: </td><td><INPUT TYPE=\"text\" NAME=\"system_name\" ID=\"system_name\" VALUE=\"" . (isset($arrDetails['system_name'])?$arrDetails['system_name']:'')  . "\"></td>
            <td align=\"right\" nowrap>Location Info: </td><td><INPUT TYPE=\"text\" NAME=\"location_name\" ID=\"location_name\" SIZE=32 VALUE=\"" . (isset($arrDetails['location_name'])?$arrDetails['location_name']:'')  . "\"></td>
          </tr><tr>
            <td align=\"right\"><font color=\"gray\">System ID:</font></td><td><font color=\"gray\">" . (isset($arrDetails['system_id'])?$arrDetails['system_id']:'')  . "</font></td>
            <td align=\"right\" nowrap>Time Zone: </td><td><INPUT TYPE=\"text\" NAME=\"timezone\" ID=\"timezone\" SIZE=32 VALUE=\"" . (isset($arrDetails['timezone'])?$arrDetails['timezone']:'')  . "\"></td>
          </tr><tr>
            <td align=\"right\"><font color=\"gray\">OS:</font></td><td><font color=\"gray\">" . (isset($arrDetails['os_name'])?$arrDetails['os_name']:'')  . "</font></td>
            <td align=\"right\" nowrap rowspan=2>Contact Info: </td><td rowspan=2><TEXTAREA NAME=\"contact_information\" ID=\"contact_information\" ROWS=2 TITLE=\"maximum 80 characters\" COLS=30 STYLE=\"font-size:8pt\">" . (isset($arrDetails['contact_information'])?$arrDetails['contact_information']:'')  . "</TEXTAREA></td>
          </tr><tr>
            <td align=\"right\"><font color=\"gray\">IP Address:</font></td><td><font color=\"gray\">" . (isset($arrDetails['ip_address'])?$arrDetails['ip_address']:'')  . "</font></td>
          </tr><tr>
            <td align=\"right\" nowrap>Priority: </td><td><INPUT TYPE=\"text\" NAME=\"priority\" ID=\"priority\" VALUE=\"" . (isset($arrDetails['priority'])?$arrDetails['priority']:'0')  . "\"></td>
          </tr><tr>
            <td colspan=2><b>All Computer Groups</b><br>" .
            build_drop_down( 
                'SELECT id_dad_adm_computer_group, group_name FROM dad_adm_computer_group ORDER BY group_name DESC',
                'allgroups',
                '',
                "MULTIPLE style=\"width:100%\" ondblclick=\"copy_node(this,selectedgroups);record_list(selectedgroups,selectedgroups_list,'~~~');\" onkeypress=\"select_keypress_copy(this,selectedgroups,selectedgroups_list,'~~~');\" "
            )
         . "</td>
            <td colspan=2><b>Current Member Of</b><br>" . 
            build_drop_down( 
                "SELECT g.id_dad_adm_computer_group, g.group_name 
                 FROM dad_adm_computer_group as g 
                 INNER JOIN dad_adm_computer_group_member as m ON g.id_dad_adm_computer_group = m.id_dad_adm_computer_group
                 WHERE m.system_id = '".(isset($Global['system_id'])? $Global['system_id'] : '').
					"' ORDER BY group_name DESC",
                'selectedgroups',
                '',
                "MULTIPLE style=\"width:100%\" ondblclick=\"remove_node(this);record_list(this,selectedgroups_list,'~~~');\" "
            )
         . "</td>
          </tr><tr>
            <td colspan=4><b>Services to Monitor:</b>" . 
            build_check_box_table ( 
                'SELECT log_these_id, service_name FROM dad_sys_services WHERE log_these_id > 0 ORDER BY service_name ASC', 
                4, 
                2, 
                'cbservices', 
                $arrLogThese 
            ) 
            . "</td>
          </tr>
        </table></form>";

    $strHTML .= "<script>record_list('selectedgroups','selectedgroups_list','~~~')</script>";

    add_element( $strHTML );

}



function computer_group_admin(){
    global $gaLiterals;
    global $Global;

    if( checkOptionPermission( $Global['UserID'], $Global['OptionID'] ) == 0 ){
        dispatch( OPTIONID_LOGOUT );
        return;
    }
    add_element( "<div class=\"page_head_name\">${gaLiterals['Computer Groups']}</div>" );

    $arr = array();
    $flg_lookup = 0;
    $strURL  = getOptionURL(OPTIONID_COMPUTER_GROUPS_ADMIN);
    $strMsg  = '';
    
    if ( isset($Global['form_action']) && $Global['form_action'] === 'delete' ){
        $strAff = runSQLReturnAffected( "DELETE dad_adm_computer_group_member FROM dad_adm_computer_group_member WHERE id_dad_adm_computer_group = ${Global['group_id']}" );
        $strAff = runSQLReturnAffected( "DELETE dad_adm_computer_group FROM dad_adm_computer_group WHERE id_dad_adm_computer_group = ${Global['group_id']}" );
        if( $strAff ){
            add_element( "<div class=\"response_text\">${gaLiterals['Successfully Deleted']} \"${Global['groupname']}\"</div>" );
        }else{
            add_element( "<div class=\"response_text\">${gaLiterals['Error Deleting']} \"${Global['groupname']}\"</div>" );
        }
    }

    if ( isset($Global['form_action']) && $Global['form_action'] === 'saveasnew' ){
        if( isset($Global['groupname']) && preg_match( '/\S/', $Global['groupname'] ) ){
            /*NEED INPUT VALIDATION*/
            $strID = runInsertReturnID( "INSERT INTO dad_adm_computer_group( group_name, description, calleractive, timeactive)VALUES( '${Global['groupname']}', '${Global['descrip']}', '${Global['txtUserName']}', unix_timestamp() )" );
            if( $strID ){
                //ADD computer membership
                $arr = explode('~~~',$Global['selectedcomputers_list']);
                foreach( $arr as $a ){
                    if( isset($a) && $a >=1 ){
                        /*will check for the existance of this group membership*/
                        $strSQL = "SELECT id_dad_adm_computer_group
                                   FROM dad_adm_computer_group_member
                                   WHERE id_dad_adm_computer_group = $strID
                                   AND system_id = $a";
                        if( runSQLReturnAffected( $strSQL ) == 0 ){
                            runSQLReturnAffected( "INSERT INTO dad_adm_computer_group_member( id_dad_adm_computer_group, system_id, calleractive, timeactive ) 
                                                   VALUES ( $strID, $a, '${Global['txtUserName']}',unix_timestamp() )"
                                                );
                        }
                    }
                }
                $Global['group_id'] = $strID;
                add_element( "<div class=\"response_text\">${gaLiterals['Successfully Added']} \"${Global['groupname']}\"</div>" );
            }else{
                add_element( "<div class=\"response_text\">${gaLiterals['Error Adding']} \"${Global['groupname']}\"</div>" );
            }
            $flg_lookup = 1;
        }else{
            add_element("<div class=\"response_text\">${gaLiterals['Error Adding']} \"${Global['groupname']}\". ${gaLiterals['Description Required']}</div>");
        }
    }

    if ( isset($Global['form_action']) && $Global['form_action'] === 'update' ){
        if( isset($Global['groupname']) && preg_match( '/\S/', $Global['groupname'] ) ){
            /*NEED INPUT VALIDATION*/
            $strAff = runSQLReturnAffected( "DELETE dad_adm_computer_group FROM dad_adm_computer_group WHERE id_dad_adm_computer_group = ${Global['group_id']}" );
            if( is_int($strAff) && $stAff >= 0 ){
                $strSQL = "INSERT INTO dad_adm_computer_group( id_dad_adm_computer_group, group_name, description, calleractive, timeactive)VALUES( '${Global['group_id']}', '${Global['groupname']}', '${Global['groupdesc']}', '${Global['txtUserName']}', unix_timestamp() )";
                $strID = runInsertReturnID( $strSQL );

                if( $strID ){
                    // remove email addresses
                    runSQLReturnAffected( "DELETE dad_adm_computer_group_member FROM dad_adm_computer_group_member WHERE id_dad_adm_computer_group = ${Global['group_id']}" );
                    // ADD email address
                    $arr = explode(',',$Global['selectedcomputers_list']);
                    foreach( $arr as $a ){
                        if( isset($a) && $a >=1 ){
                            /*will check for the existance of this group membership*/
                            $strSQL = "SELECT id_dad_adm_computer_group
                                       FROM dad_adm_computer_group_member
                                       WHERE id_dad_adm_computer_group = ${Global['group_id']}
                                       AND system_id = $a";
                            if( runSQLReturnAffected( $strSQL ) == 0 ){
                                runSQLReturnAffected( "INSERT INTO dad_adm_computer_group_member( id_dad_adm_computer_group, system_id, calleractive, timeactive ) 
                                                       VALUES ( ${Global['group_id']}, $a, '${Global['txtUserName']}',unix_timestamp() )"
                                                    );
                            }
                        }
                    }
                    add_element( "<div class=\"response_text\">${gaLiterals['Updated']} \"${Global['groupname']}\"</div>" );
                }else{
                    if( isset($Global['group_id']) && $Global['group_id'] != '' ){
                        add_element( "<div class=\"response_text\">${gaLiterals['Error Updating']} \"${Global['groupname']}\". ${gaLiterals['Internal Error']}</div>" );
//NEED INTERNAL LOGGING... SOMETHING BAD HAPPENED; COULD NOT INSERT NEW DATA
                    }else{
                        add_element( "<div class=\"response_text\">${gaLiterals['Error Updating']} \"${Global['groupname']}\". ${gaLiterals['Does Not Exist']}</div>" );
//NEED INTERNAL LOGGING... SOMETHING BAD HAPPENED - IS THE USER PLAYING AROUND, PASSING WRONG GROUP ID'S??????? HACKING????
                    }
                }
            }else{
                add_element( "<div class=\"response_text\">${gaLiterals['Error Updating']} \"${Global['groupname']}\". ${gaLiterals['Internal Error']}</div>" );
//NEED INTERNAL LOGGING... SOMETHING BAD HAPPENED, COULD NOT DELETE
            }
            $flg_lookup = 1;
        }else{
            add_element("<div class=\"response_text\">${gaLiterals['Error Updating']} \"${Global['groupname']}\". ${gaLiterals['Description Required']}</div>");
        }
    }

    if ( (isset($Global['form_action']) && $Global['form_action'] === 'lookup') || $flg_lookup ){
        $strSQL  = "SELECT id_dad_adm_computer_group, group_name, description, calleractive, from_unixtime(timeactive) as timeactive FROM dad_adm_computer_group WHERE id_dad_adm_computer_group = ${Global['group_id']} ";
        $arr = runQueryReturnArray( $strSQL );
        if( is_array($arr) ){
            $arr = array_shift($arr);
        }else{
            $arr = array();
        }
    }

    $strHTML .= "<SCRIPT ID=\"clientEventHandlersJS\" LANGUAGE=\"javascript\" TYPE=\"text/javascript\" src=\"javascript/dad.js\"></SCRIPT>";
    $strHTML .= "<form id=\"computer_group_admin\" action=\"$strURL\" method=\"post\">
        <input type=\"hidden\" name=\"form_action\" id=\"form_action\">
        <input type=\"hidden\" name=\"selectedcomputers_list\" id=\"selectedusers_list\">
        <table>
          <colgroup valign=top></colgroup>
          <tr>
            <td align=\"right\" nowrap><b>${gaLiterals['Computer Groups']}:</b></td>
            <td>";
    $strHTML .= build_drop_down( 'SELECT id_dad_adm_computer_group, group_name FROM dad_adm_computer_group ORDER BY group_name ASC', 'group_id', $arr['id_dad_adm_computer_group'], "onchange=\"record_action_and_submit('lookup');\"" );
    $strHTML .="
            </td><td colspan=3 nowrap>";
    if( isset($Global['group_id']) ){
        $strHTML .= "<INPUT type=button name=bt id=bt value=\"${gaLiterals['Update']}\" onclick=\"record_action_and_submit('update',1);\">";
    }
    $strHTML .= "
            <INPUT type=button name=bt id=bt value=\"${gaLiterals['Save as New']}\" onclick=\"record_action_and_submit('saveasnew',1);\">
            <INPUT type=button name=bt id=bt value=\"${gaLiterals['Delete']}\" onclick=\"delete_bt_click(group_id);\">
            <INPUT type=button name=bt id=bt value=\"${gaLiterals['New']}\" onclick=\"window.navigate('$strURL');\">
            <INPUT type=button name=bt id=bt value=\"${gaLiterals['Refresh']}\" onclick=\"record_action_and_submit('lookup');\">
            </td>
          </tr><tr>
            <td align=\"right\">" . $gaLiterals['Group Name'] . ":</td><td><input type=text name=groupname id=groupname maxlength=30 value=\"" . ( isset($arr['group_name']) ? $arr['group_name'] : '') . "\"></td>
            <td><font color=\"gray\">${gaLiterals['Last Changed By']}:</font></td><td><font color=\"gray\">${arr['calleractive']}</font></td>
          </tr><tr>
            <td align=\"right\">" . $gaLiterals['Group Desc'] . ":</td><td><input type=text name=groupdesc id=groupdesc maxlength=100 value=\"" . ( isset($arr['description']) ? $arr['description'] : '') . "\"></td>
            <td><font align=\"right\" color=\"gray\">${gaLiterals['Last Changed On']}:</font></td><td><font color=\"gray\">${arr['timeactive']}</font></td>
          </tr><tr>
            <td align=\"right\" id=\"groupid\"><font color=\"gray\">" . $gaLiterals['Group ID'] . ":</font></td><td><font color=\"gray\">" . ( isset($arr['id_dad_adm_computer_group']) ? $arr['id_dad_adm_computer_group'] : '') . "</font></td>
          </tr><tr>
            <td colspan=2>
            <b>${gaLiterals['All Computers']}</b>";
    $strHTML .= build_drop_down( "SELECT system_id, system_name  FROM dad_sys_systems ORDER BY system_name ASC", 'allcomputers', '', "MULTIPLE style=\"width:100%\" ondblclick=\"copy_node(this,selectedcomputers);record_list(selectedcomputers,selectedcomputers_list,'~~~');\" onkeypress=\"select_keypress_copy(this,selectedcomputers,selectedcomputers_list,'~~~');\"");
    $strHTML .= "</td>
            <td colspan=2>
            <b>${gaLiterals['Current Members']}</b>";
    $strSQL = "SELECT c.system_id, c.system_name
               FROM dad_sys_systems AS c 
               INNER JOIN dad_adm_computer_group_member AS m ON c.system_id = m.system_id 
               WHERE m.id_dad_adm_computer_group = ${Global['group_id']} 
               ORDER BY c.system_name ASC";
    $strHTML .= build_drop_down( $strSQL, 'selectedcomputers', '', "MULTIPLE style=\"width:100%\" ondblclick=\"remove_node(this);\"");
    $strHTML .= "</td></tr></table></form>";
    $strHTML .= "<script>record_list('selectedcomputers','selectedcomputers_list','~~~')</script>";

    add_element( $strHTML );
}
?>

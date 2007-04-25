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


function alert_group_admin(){
    global $gaLiterals;
    global $Global;

    if( checkOptionPermission( $Global['UserID'], $Global['OptionID'] ) == 0 ){
        dispatch( OPTIONID_LOGOUT );
        return;
    }
    add_element( "<b><font size=2>${gaLiterals['Alert Groups']}</font></b><br><br>" );

    $arr = array();
    $flg_lookup = 0;
    $strURL  = getOptionURL(OPTIONID_ALERT_GROUP_ADMIN);
    $strMsg  = '';
    
    if ( isset($Global['form_action']) && $Global['form_action'] === 'delete' ){
        $strAff = runSQLReturnAffected( "DELETE dad_adm_alert_group_member FROM dad_adm_alert_group_member WHERE id_dad_adm_alertgroup = ${Global['alertgroup_id']}" );
        $strAff = runSQLReturnAffected( "DELETE dad_adm_alert_group FROM dad_adm_alert_group WHERE id_dad_adm_alertgroup = ${Global['alertgroup_id']}" );
        if( $strAff ){
            add_element( "<div class='response_text'>${gaLiterals['Deleted']} \"${Global['groupname']}\"</div>" );
        }else{
            add_element( "<div class='response_text'>${gaLiterals['ERROR']} ${gaLiterals['Deleting']} \"${Global['groupname']}\"</div>" );
        }
    }

    if ( isset($Global['form_action']) && $Global['form_action'] === 'saveasnew' ){
        if( isset($Global['groupname']) && preg_match( '/\S/', $Global['groupname'] ) ){
            /*NEED INPUT VALIDATION*/
            $strID = runInsertReturnID( "INSERT INTO dad_adm_alert_group( name, description, calleractive, timeactive)VALUES( '${Global['groupname']}', '${Global['descrip']}', '${Global['txtUserName']}', unix_timestamp() )" );
            if( $strID ){
                //ADD email address
                $arr = explode('~~~',$Global['selectedusers_list']);
                foreach( $arr as $a ){
                    if( isset($a) && $a >=1 ){
                        /*will check for the existance of this group membership*/
                        $strSQL = "SELECT id_dad_adm_alertgroup
                                   FROM dad_adm_alert_group_member
                                   WHERE id_dad_adm_alertgroup = $strID
                                   AND id_dad_adm_alertuser = $a";
                        if( runSQLReturnAffected( $strSQL ) == 0 ){
                            runSQLReturnAffected( "INSERT INTO dad_adm_alert_group_member( id_dad_adm_alertgroup, id_dad_adm_alertuser, calleractive, timeactive ) 
                                                   VALUES ( $strID, $a, '${Global['txtUserName']}',unix_timestamp() )"
                                                );
                        }
                    }
                }
                $Global['alertgroup_id'] = $strID;
                add_element( "<div class='response_text'>${gaLiterals['Added']} \"${Global['groupname']}\"</div>" );
            }else{
                add_element( "<div class='response_text'>${gaLiterals['ERROR']} ${gaLiterals['Adding']} \"${Global['groupname']}\"</div>" );
            }
            $flg_lookup = 1;
        }
    }

    if ( isset($Global['form_action']) && $Global['form_action'] === 'update' ){
        if( isset($Global['groupname']) && preg_match( '/\S/', $Global['groupname'] ) ){
            /*NEED INPUT VALIDATION*/
            $strAff = runSQLReturnAffected( "DELETE dad_adm_alert_group FROM dad_adm_alert_group WHERE id_dad_adm_alertgroup = ${Global['alertgroup_id']}" );
            if( is_int($strAff) && $stAff >= 0 ){
                $strSQL = "INSERT INTO dad_adm_alert_group( id_dad_adm_alertgroup, name, description, calleractive, timeactive)VALUES( '${Global['alertgroup_id']}', '${Global['groupname']}', '${Global['groupdesc']}', '${Global['txtUserName']}', unix_timestamp() )";
                $strID = runInsertReturnID( $strSQL );

                if( $strID ){
                    // remove email addresses
                    runSQLReturnAffected( "DELETE dad_adm_alert_group_member FROM dad_adm_alert_group_member WHERE id_dad_adm_alertgroup = ${Global['alertgroup_id']}" );
                    // ADD email address
                    $arr = explode('~~~',$Global['selectedusers_list']);
                    foreach( $arr as $a ){
                        if( isset($a) && $a >=1 ){
                            /*will check for the existance of this group membership*/
                            $strSQL = "SELECT id_dad_adm_alertgroup
                                       FROM dad_adm_alert_group_member
                                       WHERE id_dad_adm_alertgroup = ${Global['alertgroup_id']}
                                       AND id_dad_adm_alertuser = $a";
                            if( runSQLReturnAffected( $strSQL ) == 0 ){
                                runSQLReturnAffected( "INSERT INTO dad_adm_alert_group_member( id_dad_adm_alertgroup, id_dad_adm_alertuser, calleractive, timeactive ) 
                                                       VALUES ( ${Global['alertgroup_id']}, $a, '${Global['txtUserName']}',unix_timestamp() )"
                                                    );
                            }
                        }
                    }
                    add_element( "<div class='response_text'>${gaLiterals['Updated']} \"${Global['groupname']}\"</div>" );
                }else{
                    if( isset($Global['alertgroup_id']) && $Global['alertgroup_id'] != '' ){
                        add_element( "<div class='response_text'>${gaLiterals['ERROR']} ${gaLiterals['Updating']} \"${Global['groupname']}\". Can't insert new data</div>" );
                    }else{
                        add_element( "<div class='response_text'>${gaLiterals['ERROR']} ${gaLiterals['Updating']} \"${Global['groupname']}\". Group does not exist</div>" );
                    }
                }
            }else{
                add_element( "<div class='response_text'>${gaLiterals['ERROR']} ${gaLiterals['Updating']} \"${Global['groupname']}\". Can't remove old entry</div>" );
            }
            $flg_lookup = 1;
        }
    }

    if ( (isset($Global['form_action']) && $Global['form_action'] === 'lookup') || $flg_lookup ){
        $strSQL  = "SELECT id_dad_adm_alertgroup, name, description, calleractive, from_unixtime(timeactive) as timeactive FROM dad_adm_alert_group WHERE id_dad_adm_alertgroup = ${Global['alertgroup_id']} ";
        $arr = runQueryReturnArray( $strSQL );
        if( is_array($arr) ){
            $arr = array_shift($arr);
        }else{
            $arr = array();
        }
    }

    $strHTML .= "<SCRIPT ID='clientEventHandlersJS' LANGUAGE='javascript' TYPE='text/javascript' src='javascript/dad.js'></SCRIPT>";
    $strHTML .= "<form id='alert_group_admin' action='$strURL' method='post'>
        <input type='hidden' name='form_action' id='form_action'>
        <input type='hidden' name='selectedusers_list' id='selectedusers_list'>
        <table>
          <colgroup valign=top></colgroup>
          <tr>
            <td align='right'><b>${gaLiterals['Groups']}:</b></td>
            <td>";
    $strHTML .= build_drop_down( 
        'SELECT id_dad_adm_alertgroup, name FROM dad_adm_alert_group ORDER BY name ASC', 
        'alertgroup_id', 
        $arr['id_dad_adm_alertgroup'], 
        "onchange=\"record_action_and_submit('lookup');\"" 
    );
    $strHTML .="
            </td><td colspan=2>";
    if( isset($Global['alertgroup_id']) ){
        $strHTML .= "<INPUT type=button name=bt id=bt value='${gaLiterals['Update']}' onclick=\"record_action_and_submit('update');\">";
    }
    $strHTML .= "
            <INPUT type=button name=bt id=bt value='${gaLiterals['Save as New']}' onclick=\"record_action_and_submit('saveasnew');\">
            <INPUT type=button name=bt id=bt value='${gaLiterals['Delete']}' onclick=\"delete_bt_click(groupid);\">
            <INPUT type=button name=bt id=bt value='${gaLiterals['New']}' onclick=\"window.navigate('$strURL');\">
            <INPUT type=button name=bt id=bt value='${gaLiterals['Refresh']}' onclick=\"record_action_and_submit('lookup');\">
            </td>
          </tr><tr>
            <td align='right'>" . $gaLiterals['Group Name'] . ":</td><td><input type=text name=groupname id=groupname maxlength=30 value='" . ( isset($arr['name']) ? $arr['name'] : '') . "'></td>
            <td><font color='gray'>${gaLiterals['Last Changed By']}:</font></td><td><font color='gray'>${arr['calleractive']}</font></td>
          </tr><tr>
            <td align='right'>" . $gaLiterals['Group Desc'] . ":</td><td><input type=text name=groupdesc id=groupdesc maxlength=100 value='" . ( isset($arr['description']) ? $arr['description'] : '') . "'></td>
            <td><font color='gray' align='right'>${gaLiterals['Last Changed On']}:</font></td><td><font color='gray'>${arr['timeactive']}</font></td>
          </tr><tr>
            <td align='right' id='groupid'><font color='gray'>" . $gaLiterals['Group ID'] . ":</font></td><td><font color='gray'>" . ( isset($arr['id_dad_adm_alertgroup']) ? $arr['id_dad_adm_alertgroup'] : '') . "</font></td>
          </tr><tr>
            <td colspan=2>
            <b>${gaLiterals['All Users']}</b>";
    $strHTML .= build_drop_down( 
        "SELECT id_dad_adm_alertuser, concat(lastname, ', ', firstname) as fullname FROM dad_adm_alertuser ORDER BY concat(lastname, ', ', firstname) ASC", 
        'allusers', 
        '', 
        "MULTIPLE style=\"width:100%\" ondblclick=\"copy_node(this,selectedusers);record_list(selectedusers,selectedusers_list,'~~~');\" onkeypress=\"select_keypress_copy(this,selectedusers,selectedusers_list,'~~~');\" 
    ");  
    $strHTML .= "</td>
            <td colspan=2>
            <b>${gaLiterals['Current Members']}</b>";
    $strSQL = "SELECT u.id_dad_adm_alertuser, concat(u.lastname, ', ', u.firstname) as fullname 
               FROM dad_adm_alertuser as u 
               INNER JOIN dad_adm_alert_group_member m ON u.id_dad_adm_alertuser = m.id_dad_adm_alertuser 
               WHERE m.id_dad_adm_alertgroup = ${Global['alertgroup_id']} 
               ORDER BY concat(lastname, ', ', firstname) ASC";
    $strHTML .= build_drop_down( 
        $strSQL, 
        'selectedusers', 
        '', 
        "MULTIPLE style=\"width:100%\" ondblclick=\"remove_node(this);record_list('selectedusers','selectedusers_list','~~~');\"
    ");
    $strHTML .= "</td>
          </tr></table>";
    $strHTML .= "</form>";
    //$strHTML .= "<SCRIPT>record_list(document.forms[0].selectedusers);</SCRIPT>";
    $strHTML .= "<script>record_list('selectedusers','selectedusers_list','~~~')</script>";

    add_element( $strHTML );
}



function alert_user_admin(){
    global $gaLiterals;
    global $Global;

    if( checkOptionPermission( $Global['UserID'], $Global['OptionID'] ) == 0 ){
        dispatch( OPTIONID_LOGOUT );
        return;
    }
    add_element( "<b><font size=2>${gaLiterals['Alert Users']}</font></b><br><br>" );

    $arr = array();
    $flg_lookup = 0;
    $strURL  = getOptionURL(OPTIONID_ALERT_USER_ADMIN);
    $strMsg  = ''; 

    if ( isset($Global['form_action']) && $Global['form_action'] === 'delete' ){
        $strAff = runSQLReturnAffected( "DELETE dad_adm_alert_group_member FROM dad_adm_alert_group_member WHERE id_dad_adm_alertuser = ${Global['alertuser_id']}" );
        $strAff = runSQLReturnAffected( "DELETE dad_adm_alertuser FROM dad_adm_alertuser WHERE id_dad_adm_alertuser = ${Global['alertuser_id']}" );
        if( is_int($strAff) ){
            add_element( "<div class='response_text'>${gaLiterals['Deleted']} \"${Global['lastname']}, ${Global['firstname']}\"</div>" );
        }else{
            add_element( "<div class='response_text'>${gaLiterals['ERROR']} ${gaLiterals['Deleting']} \"${Global['lastname']}, ${Global['firstname']}\"</div>" );
        }
    }

    if ( isset($Global['form_action']) && $Global['form_action'] === 'saveasnew' ){
        if( isset($Global['lastname']) && preg_match( '/\S/', $Global['lastname'] ) ){
            /*NEED INPUT VALIDATION*/
            $strSQL = "INSERT INTO dad_adm_alertuser( firstname, lastname, employeeid, emailaddress, department, subdepartment, phone1, phone2, location, custom_entry, calleractive, timeactive)VALUES( '${Global['firstname']}', '${Global['lastname']}', " . (isset($Global['employeeid']) && $Global['employeeid'] > 0 ? $Global['employeeid'] : 0) . ", '${Global['emailaddress']}', '${Global['department']}', '${Global['subdepartment']}', '${Global['phone1']}', '${Global['phone2']}', '${Global['location']}', " . (isset($Global['custom_entry']) && $Global['custom_entry'] == 1 ? $Global['custom_entry'] : 0) . ", '${Global['txtUserName']}', unix_timestamp() )";
            $strID = runInsertReturnID( $strSQL );
            $Global['alertuser_id'] = $strID;
            if( is_int($strID) ){
                /*add groups*/
                $arr = explode('~~~',$Global['selectedgroups_list']);
                foreach( $arr as $a ){
                    if( isset($a) && $a >=1 ){
                        /*will check for the existance of this group membership, just in case the group appears twice in the submitted list*/
                        $strSQL = "SELECT id_dad_adm_alertgroup
                                   FROM dad_adm_alert_group_member
                                   WHERE id_dad_adm_alertuser = ${Global['alertuser_id']}
                                   AND id_dad_adm_alertgroup = $a";
                        if( runSQLReturnAffected( $strSQL ) == 0 ){
                            runSQLReturnAffected( "INSERT INTO dad_adm_alert_group_member( id_dad_adm_alertuser, id_dad_adm_alertgroup, calleractive, timeactive ) 
                                                   VALUES ( ${Global['alertuser_id']}, $a, '${Global['txtUserName']}',unix_timestamp() )"
                                                );
                        }
                    }
                }
                add_element( "<div class='response_text'>${gaLiterals['Added']} \"${Global['lastname']}, ${Global['firstname']}\"</div>" );
            }else{
                add_element( "<div class='response_text'>${gaLiterals['ERROR']} ${gaLiterals['Adding']} \"${Global['lastname']}, ${Global['firstname']}\"</div>" );
            }
            $flg_lookup = 1;
        }
    }

    if ( isset($Global['form_action']) && $Global['form_action'] === 'update' ){
        if( isset($Global['lastname']) && preg_match( '/\S/', $Global['lastname'] ) ){
            /*NEED INPUT VALIDATION*/
            $strAff = runSQLReturnAffected( "DELETE dad_adm_alertuser FROM dad_adm_alertuser WHERE id_dad_adm_alertuser = ${Global['alertuser_id']}" );
            $strAff = runSQLReturnAffected( "DELETE dad_adm_alert_group_member FROM dad_adm_alert_group_member WHERE id_dad_adm_alertuser = ${Global['alertuser_id']}" );
            if( is_int($strAff) && $stAff >= 0 ){
                $strSQL = "INSERT INTO dad_adm_alertuser( id_dad_adm_alertuser, firstname, lastname, employeeid, emailaddress, department, subdepartment, phone1, phone2, location, custom_entry, calleractive, timeactive)VALUES( ${Global['alertuser_id']}, '${Global['firstname']}', '${Global['lastname']}', " . (isset($Global['employeeid']) && $Global['employeeid'] >1 ? $Global['employeeid'] : '0') . ", '${Global['emailaddress']}', '${Global['department']}', '${Global['subdepartment']}', '${Global['phone1']}', '${Global['phone2']}', '${Global['location']}', " . (isset($Global['custom_entry']) && $Global['custom_entry'] == 1 ? $Global['custom_entry'] : '0') . ", '${Global['txtUserName']}', unix_timestamp() )";
                $strID = runInsertReturnID( $strSQL );
                if( is_int($strID) ){
                    /*add groups*/
                    $arr = explode('~~~',$Global['selectedgroups_list']);
                    foreach( $arr as $a ){
                        if( isset($a) && $a >=1 ){
                            /*will check for the existance of this group membership, just in case the group appears twice in the submitted list*/
                            $strSQL = "SELECT id_dad_adm_alertgroup
                                       FROM dad_adm_alert_group_member
                                       WHERE id_dad_adm_alertuser = ${Global['alertuser_id']}
                                       AND id_dad_adm_alertgroup = $a";
                            if( runSQLReturnAffected( $strSQL ) == 0 ){
                                runSQLReturnAffected( "INSERT INTO dad_adm_alert_group_member( id_dad_adm_alertuser, id_dad_adm_alertgroup, calleractive, timeactive ) 
                                                       VALUES ( ${Global['alertuser_id']}, $a, '${Global['txtUserName']}',unix_timestamp() )"
                                                    );
                            }
                        }
                    }
                    add_element( "<div class='response_text'>${gaLiterals['Updated']} \"${Global['lastname']}, ${Global['firstname']}\"</div>" );
                }else{
                    add_element( "<div class='response_text'>${gaLiterals['ERROR']} ${gaLiterals['Updating']} \"${Global['lastname']}, ${Global['firstname']}\". Can't insert new data</div>" );
                }
            }else{
                add_element( "<div class='response_text'>${gaLiterals['ERROR']} ${gaLiterals['Updating']} \"${Global['lastname']}, ${Global['firstname']}\". Can't remove old entry</div>" );
            }
            $flg_lookup = 1;
        }
    }

    if ( (isset($Global['form_action']) && $Global['form_action'] === 'lookup') || $flg_lookup ){
        $strSQL  = "SELECT id_dad_adm_alertuser, firstname, lastname, employeeid, emailaddress, department, subdepartment, phone1, phone2, location, custom_entry, calleractive, from_unixtime(timeactive) as timeactive FROM dad_adm_alertuser WHERE id_dad_adm_alertuser = ${Global['alertuser_id']} ";
        $arr = runQueryReturnArray( $strSQL );
        if( is_array($arr) ){
            $arr = array_shift($arr);
        }else{
            $arr = array();
        }
    }

    $strHTML .= "<SCRIPT ID='clientEventHandlersJS' LANGUAGE='javascript' TYPE='text/javascript' src='javascript/dad.js'></SCRIPT>
        <form id='alert_user_admin' action='$strURL' method='post'>
        <input type='hidden' name='form_action' id='form_action'>
        <input type='hidden' name='selectedgroups_list' id='selectedgroups_list'>
        <input type='hidden' name='custom_entry' id='custom_entry' value=" . (isset($arr['custom_entry']) ? $arr['custom_entry'] : '') .">
        <table>
          <colgroup valign=top></colgroup>
          <tr>
            <td rowspan=10><b>${gaLiterals['Users']}:</b><br>";
    $strHTML .= build_drop_down(
                    "SELECT id_dad_adm_alertuser, concat( lastname, ', ', firstname) as fullname FROM dad_adm_alertuser ORDER BY concat( lastname, ', ', firstname) ASC", 
                    'alertuser_id', 
                    $arr['id_dad_adm_alertuser'], 
                    "TABINDEX=1 SIZE=16 STYLE=\"width:100pt\" ondblclick=\"record_action_and_submit('lookup');\" onkeypress=\"select_keypress_record_action('lookup');\" " 
                );
    $strHTML .="
            </td>
            <td colspan=4>";
    if( isset($Global['alertuser_id']) ){
        $strHTML .="<INPUT type=button name=bt id=bt value='${gaLiterals['Update']}' onclick=\"record_action_and_submit('update');\">";
    }
    $strHTML .= "
            <INPUT type=button name=bt id=bt value='${gaLiterals['Save as New']}' onclick=\"record_action_and_submit('saveasnew',1);\">
            <INPUT type=button name=bt id=bt value='${gaLiterals['Delete']}' onclick=\"delete_bt_click(alertuser_id);\">
            <INPUT type=button name=bt id=bt value='${gaLiterals['New']}' onclick=\"window.navigate('$strURL');\">
            <INPUT type=button name=bt id=bt value='${gaLiterals['Edit']}' onclick=\"unlock_input_fields();custom_entry.value=1;\">
            <INPUT type=button name=bt id=bt value='${gaLiterals['Refresh']}' onclick=\"record_action_and_submit('lookup');\">
            </td>
          </tr><tr> 
            <td align='right' nowrap>" . $gaLiterals['First Name'] . ":</td><td><input type=text READONLY name=firstname id=firstname maxlength=30 value='" . ( isset($arr['firstname']) ? $arr['firstname'] : '') . "'></td>
            <td align='right'>" . $gaLiterals['Phone'] . " 1:</td><td><input type=text READONLY name=phone1 id=phone1 maxlength=30 value='" . (isset($arr['phone1']) ? $arr['phone1'] : '') . "'></td>
          </tr><tr>
            <td align='right' nowrap>" . $gaLiterals['Last Name'] . ":</td><td><input type=text READONLY name=lastname id=lastname maxlength=30 value='" . ( isset($arr['lastname']) ? $arr['lastname'] : '') . "'></td>
            <td align='right'>" . $gaLiterals['Phone'] . " 2:</td><td><input type=text READONLY name=phone2 id=phone2 maxlength=30 value='" . (isset($arr['phone2']) ? $arr['phone2'] : '') . "'></td>
          </tr><tr>
            <td align='right' nowrap>" . $gaLiterals['Email Address'] . ":</td><td><input type=text READONLY name=emailaddress id=emailaddress maxlength=45 value='" . (isset($arr['emailaddress']) ? $arr['emailaddress'] : '') . "'></td>
            <td align='right'>" . $gaLiterals['Employee ID'] . ":</td><td><input type=text READONLY name=employeeid id=employeeid maxlength=20 value='" . ( isset($arr['employeeid']) ? $arr['employeeid'] : '') . "'></td>  
          </tr><tr>
            <td align='right'>" . $gaLiterals['Department'] . ":</td><td><input type=text READONLY name=department id=department maxlength=100 value='" . ( isset($arr['department']) ? $arr['department'] : '') . "'></td>
            <td align='right' id=userid name=userid><font color='gray'>" . $gaLiterals['User ID'] . ":</font></td><td><font color='gray'>" . ( isset($arr['id_dad_adm_alertuser']) ? $arr['id_dad_adm_alertuser'] : '') . "</font></td>            
          </tr><tr>
            <td align='right' nowrap>" . $gaLiterals['Sub Department'] . ":</td><td><input type=text READONLY name=subdepartment id=subdepartment maxlength=100 value='" . ( isset($arr['subdepartment']) ? $arr['subdepartment'] : '') . "'></td>
            <td><font color='gray'>${gaLiterals['Last Changed By']}:</font></td><td><font color='gray'>${arr['calleractive']}</font></td>
          </tr><tr>
            <td align='right'>" . $gaLiterals['Location'] . ":</td><td><input type=text READONLY name=location id=location maxlength=45 value='" . (isset($arr['location']) ? $arr['location'] : '') . "'></td>
            <td><font color='gray'>${gaLiterals['Last Changed On']}:</font></td><td><font color='gray'>${arr['timeactive']}</font></td>
          </tr><tr>
            <td colspan=2>
            <b>${gaLiterals['All Groups']}</b>";
    $strHTML .= build_drop_down( 
                    "SELECT id_dad_adm_alertgroup, name FROM dad_adm_alert_group ORDER BY name ASC", 
                    'allgroups', 
                    '', 
                    "MULTIPLE style=\"width:100%\" ondblclick=\"copy_node(this,selectedgroups);record_list(selectedgroups,selectedgroups_list,'~~~');\" onkeypress=\"select_keypress_copy(this,selectedgroups,selectedgroups_list,'~~~');\" "
                );
    $strHTML .= "</td>
            <td colspan=2 nowrap>
            <b>${gaLiterals['Current Member Of']}</b><br>";
    $strSQL = "SELECT g.id_dad_adm_alertgroup, name 
               FROM dad_adm_alert_group as g
               INNER JOIN dad_adm_alert_group_member m ON g.id_dad_adm_alertgroup = m.id_dad_adm_alertgroup
               WHERE m.id_dad_adm_alertuser = ${Global['alertuser_id']} 
               ORDER BY name ASC";
    $strHTML .= build_drop_down( 
                    $strSQL, 
                    'selectedgroups',
                    '', 
                    "MULTIPLE style=\"width:100%\" ondblclick=\"remove_node(this);record_list(this,selectedgroups_list,'~~~');\" "
                );
    $strHTML .= "</td>
          </tr></table></form>";

    if( isset($arr['custom_entry']) && $arr['custom_entry'] == 1){
        $strHTML .= "\n<SCRIPT>unlock_input_fields();</SCRIPT>\n";
    }
    $strHTML .= "<SCRIPT>
                    window.alert_user_admin.alertuser_id.focus();
                    record_list('selectedgroups','selectedgroups_list','~~~');
                </SCRIPT>";
    add_element( $strHTML );
}



function alert_admin(){
    global $gaLiterals;
    global $Global;

    if( checkOptionPermission( $Global['UserID'], $Global['OptionID'] ) == 0 ){
        dispatch( OPTIONID_LOGOUT );
        return;
    }
    add_element( "<b><font size=2>${gaLiterals['Alert Admin']}</font></b><br><br>" );

    $strURL  = getOptionURL(OPTIONID_ALERT_ADMIN);
    $a    = '';
    $arr  = array();
    $arr2 = array();
    $arrMessage = array();
    $arrSupress = array();
    $flg_lookup = 0;
    $strCriteria = '';
    $strCriteriaHidden = '';

    if ( isset($Global['form_action']) && $Global['form_action'] === 'delete' ){
        $strAff = runSQLReturnAffected( "DELETE dad_adm_alert FROM dad_adm_alert WHERE id_dad_adm_alert = ${Global['alert_id']}" );
        $strAff = runSQLReturnAffected( "DELETE dad_adm_alert_criteria FROM dad_adm_alert_criteria WHERE id_dad_adm_alert = ${Global['alert_id']}" );
        $strAff = runSQLReturnAffected( "DELETE dad_adm_alert_supress FROM dad_adm_alert_supress WHERE id_dad_adm_alert = ${Global['alert_id']}" );
        $strAff = runSQLReturnAffected( "DELETE dad_adm_alert_message FROM dad_adm_alert_message WHERE id_dad_adm_alert_message = (SELECT id_dad_adm_alert_message FROM dad_adm_alert WHERE id_dad_adm_alert = ${Global['alert_id']}) AND template !=1" );
        if( is_int($strAff) ){
            add_element( "<div class='response_text'>${gaLiterals['Deleted']} \"${Global['description']}\"</div>" );
        }else{
            add_element( "<div class='response_text'>${gaLiterals['ERROR']} ${gaLiterals['Deleting']} \"${Global['description']}\"</div" );
        }
    }

    if ( isset($Global['form_action']) && $Global['form_action'] === 'saveasnew' ){
        if( isset($Global['description']) && preg_match( '/\S/', $Global['description'] ) ){
            /*save message details first, since we need the resultant ID in the next INSERT*/
            if( isset($Global['message_dirty']) && $Global['message_dirty'] == 1 ){
                $strSQL = "INSERT INTO dad_adm_alert_message( subject, body, template, calleractive, timeactive ) VALUES ( '${Global['message_subject']}', '${Global['message_body']}', 0, '${Global['txtUserName']}', unix_timestamp() )";
                $Global['message_template'] = runInsertReturnID( $strSQL );
            }

            $strSQL = "INSERT INTO dad_adm_alert( description, active, notes, calleractive, timeactive, supress_interval, id_dad_adm_action, id_dad_adm_computer_group, id_dad_adm_alert_group, id_dad_adm_alert_message ) 
                       VALUES ( 
                           '${Global['description']}', 
                           " . (isset($Global['cbactive']) && strtolower($Global['cbactive'])==='on' ? 1 : 0) . ", 
                           " . (isset($Global['notes']) ? "'${Global['notes']}'" : 'NULL') . ", 
                           '${Global['txtUserName']}', 
                           unix_timestamp(), 
                           " . (isset($Global['supress_interval']) && (preg_match( '/[\D]*\d[\D]*/', $Global['supress_interval'])===1) ? $Global['supress_interval'] : 'NULL') . ", 
                           " . (isset($Global['id_dad_adm_action']) && (preg_match( '/[\D]*\d[\D]*/', $Global['id_dad_adm_action'])===1) ? $Global['id_dad_adm_action'] : 'NULL') . ",
                           " . (isset($Global['computer_group']) && (preg_match( '/[\D]*\d[\D]*/', $Global['computer_group'])===1) ? $Global['computer_group'] : 'NULL') . ",
                           " . (isset($Global['alert_group']) && (preg_match( '/[\D]*\d[\D]*/', $Global['alert_group'])===1) ? $Global['alert_group'] : 'NULL') . ",
                           ${Global['message_template']}
                       )";
            $strID = runInsertReturnID( $strSQL );
            $Global['alert_id'] = $strID;
            if( isset($Global['criteria_list']) && preg_match( '/\S/', $Global['criteria_list'] ) ){
                $arr = explode('~~~',$Global['criteria_list']);
                if( is_array($arr) ){
                    foreach( $arr as $a ){
                        if( preg_match( '/\S/',$a ) ){
                            preg_match( '/(.*)\=~\/(.*)\//', $a, $arr2 );
                            $strAff = runSQLReturnAffected( "INSERT INTO dad_adm_alert_criteria( id_dad_adm_alert, field, criteria ) VALUES ( ${Global['alert_id']}, '${arr2[1]}', '${arr2[2]}' )" );
                        }
                    }
                }
            }

            /*split cb_supress values out... the text appended on the name of the checkbox is the info to be stored*/
            /*e.g. - cb_supress_field_13 and cb_supress_computer: 'field_13', 'computer'*/
            while( list($k,$v) = each($Global) ){
                $arr = explode('cb_supress_',$k);
                if( $arr[1] ){
                    $strSQL = "INSERT INTO dad_adm_alert_supress ( id_dad_adm_alert, field_name ) VALUES ( ${Global['alert_id']}, '$arr[1]' );";
                    runSQLReturnAffected( $strSQL );
                }
            }
            add_element("<div class='response_text'>${gaLiterals['Success']}</div>");
        }else{
            add_element("<div class='response_text'>${gaLiterals['Description is required']}</div>");
        }
        $flg_lookup = 1;
    }

    if ( isset($Global['form_action']) && $Global['form_action'] === 'update' ){
        if( isset($Global['description']) && preg_match( '/\S/', $Global['description'] ) ){
            /*out with the old...*/
            $strAff = runSQLReturnAffected( "DELETE dad_adm_alert FROM dad_adm_alert WHERE id_dad_adm_alert = ${Global['alert_id']}" );
            $strAff = runSQLReturnAffected( "DELETE dad_adm_alert_criteria FROM dad_adm_alert_criteria WHERE id_dad_adm_alert = ${Global['alert_id']}" );
            $strAff = runSQLReturnAffected( "DELETE dad_adm_alert_supress FROM dad_adm_alert_supress WHERE id_dad_adm_alert = ${Global['alert_id']}" );
            $strAff = runSQLReturnAffected( "DELETE dad_adm_alert_message FROM dad_adm_alert_message WHERE id_dad_adm_alert_message = (SELECT id_dad_adm_alert_message FROM dad_adm_alert WHERE id_dad_adm_alert = ${Global['alert_id']}) AND template !=1" );
            /*in with the new...*/
            
            /*save message details first, since we need the resultant ID in the next INSERT*/
            if( isset($Global['message_dirty']) && $Global['message_dirty'] == 1 ){
                $strSQL = "INSERT INTO dad_adm_alert_message( subject, body, template, calleractive, timeactive ) VALUES ( '${Global['message_subject']}', '${Global['message_body']}', 0, '${Global['txtUserName']}', unix_timestamp() )";
                $Global['message_template'] = runInsertReturnID( $strSQL );
            }

            /*INSERT alert details*/
            $strSQL = "INSERT INTO dad_adm_alert( id_dad_adm_alert, description, active, notes, calleractive, timeactive, supress_interval, id_dad_adm_action, id_dad_adm_computer_group, id_dad_adm_alert_group, id_dad_adm_alert_message ) 
                       VALUES ( 
                           " . (isset($Global['alert_id']) && (preg_match( '/[\D]*\d[\D]*/', $Global['alert_id'])===1) ? $Global['alert_id'] : 'NULL') . ", 
                           '${Global['description']}', 
                           " . (isset($Global['cbactive']) && strtolower($Global['cbactive'])==='on' ? 1 : 0) . ", 
                           " . (isset($Global['notes']) ? "'${Global['notes']}'" : 'NULL') . ", 
                           '${Global['txtUserName']}', 
                           unix_timestamp(), 
                           " . (isset($Global['supress_interval']) && (preg_match( '/[\D]*\d[\D]*/', $Global['supress_interval'])===1) ? $Global['supress_interval'] : 'NULL') . ", 
                           " . (isset($Global['id_dad_adm_action']) && (preg_match( '/[\D]*\d[\D]*/', $Global['id_dad_adm_action'])===1) ? $Global['id_dad_adm_action'] : 'NULL') . ",
                           " . (isset($Global['computer_group']) && (preg_match( '/[\D]*\d[\D]*/', $Global['computer_group'])===1) ? $Global['computer_group'] : 'NULL') . ",
                           " . (isset($Global['alert_group']) && (preg_match( '/[\D]*\d[\D]*/', $Global['alert_group'])===1) ? $Global['alert_group'] : 'NULL') . ",
                           ${Global['message_template']}
                       )";
                       //print $strSQL;
            $strID = runInsertReturnID( $strSQL );

            /*INSERT alert criteria*/
            if( isset($Global['criteria_list']) && preg_match( '/\S/', $Global['criteria_list'] ) ){
                $arr = explode('~~~',$Global['criteria_list']);
                if( is_array($arr) ){
                    foreach( $arr as $a ){
                        if( preg_match( '/\S/',$a ) ){
                            preg_match( '/(.*)\=~\/(.*)\//', $a, $arr2 );
                            $strAff = runSQLReturnAffected( "INSERT INTO dad_adm_alert_criteria( id_dad_adm_alert, field, criteria ) VALUES ( ${Global['alert_id']}, '${arr2[1]}', '${arr2[2]}' )" );
                        }
                    }
                }
            }

            /*split cb_supress values out... the text appended on the name of the checkbox is the info to be stored*/
            /*e.g. - cb_supress_field_13 and cb_supress_computer: 'field_13', 'computer'*/
            while( list($k,$v) = each($Global) ){
                $arr = explode('cb_supress_',$k);
                if( $arr[1] ){
                    $strSQL = "INSERT INTO dad_adm_alert_supress ( id_dad_adm_alert, field_name ) VALUES ( ${Global['alert_id']}, '$arr[1]' );";
                    runSQLReturnAffected( $strSQL );
                }
            }

            add_element("<div class='response_text'>${gaLiterals['Success']}</div>");
        }else{
            add_element("<div class='response_text'>${gaLiterals['Description is required']}</div>");
        }
        $flg_lookup = 1;
    }

    if ( (isset($Global['form_action']) && $Global['form_action'] === 'lookup') || $flg_lookup ){
        $strSQL  = "SELECT id_dad_adm_alert, id_dad_adm_action, description, notes, calleractive, from_unixtime(timeactive) as timeactive, supress_interval, active, id_dad_adm_computer_group, id_dad_adm_alert_group, id_dad_adm_alert_message FROM dad_adm_alert WHERE id_dad_adm_alert = ${Global['alert_id']} ";
        $arr = runQueryReturnArray( $strSQL );
        if( is_array($arr) ){
            $arr = array_shift($arr);
        }else{
            $arr = array();
        }

        /*build alert criteria OPTIONs that will be displayed*/
        $strSQL = "SELECT field, criteria FROM dad_adm_alert_criteria WHERE id_dad_adm_alert = ${Global['alert_id']} ORDER BY field DESC";
        $arr2 = runQueryReturnArray( $strSQL );
        if( is_array($arr2) ){
            foreach( $arr2 as $a ){
                $tmp = strtolower($a[0]) . '=~/' . $a[1] . '/';
                $strCriteria .= "<OPTION value=\"$tmp\">$tmp</OPTION>\n";
                $strCriteriaHidden .= '~~~' . $tmp;
            }
        }
        
        /*build an array of field names that should be selected for the Supress Duplicates checkboxes*/
        $arr2 = runQueryReturnArray( "SELECT field_name FROM dad_adm_alert_supress WHERE id_dad_adm_alert = ${Global['alert_id']}" );
        if( is_array($arr2) ){
            foreach( $arr2 as $a ){
                array_push( $arrSupress, $a[0] );
            }
        }
        
        /*look up message pieces*/
        $arr2 = runQueryReturnArray( "SELECT subject, body, template FROM dad_adm_alert_message WHERE id_dad_adm_alert_message = ${arr['id_dad_adm_alert_message']}" );
        if( is_array($arr2) ){
            $arrMessage = array_shift($arr2);
        }else{
            $arrMessage = array();
        }
        $a ='';
        $arr2 = '';
    }

    $strHTML = "
        <SCRIPT ID='clientEventHandlersJS' LANGUAGE='javascript' TYPE='text/javascript' src='javascript/dad.js'></SCRIPT>
        <SCRIPT>
            function add_criteria(){
                var page = document.forms[0].document.all;
                var cri_col;
                var cri_val    = page.criteria_match.value;
                var oNewNode   = document.createElement('OPTION');
                var oSelected  = page.criteria_col.children(page.criteria_col.selectedIndex);
                var str        = '';

                //oNewNode.value = 1; ////value is meanless for us here; we are using the innerHTML data instead.

                if( cri_val === '' || oSelected.innerHTML === '' ){
                    return;
                }
                cri_val = oSelected.innerHTML + '=~/' + cri_val + '/';
                oNewNode.innerHTML = cri_val;
                oNewNode.value     = cri_val;
                str = page.criteria_built.offsetWidth;
                page.criteria_built.appendChild(oNewNode);
                page.criteria_built.style.width = str;

                /*clean up fields*/
                record_list('criteria_built','criteria_list','~~~');
                page.criteria_col.selectedIndex = 0;
                page.criteria_match.value = '';
            }

            function criteria_match_keypress(){
                if( window.event.keyCode == 13 ){
                    add_criteria();
                }
            }

            function fetch_data(option,criteria,dest_name){
                var xmlhttp = new ActiveXObject('Microsoft.XMLHTTP');
                var dest = document.getElementById(dest_name);
                var session_id = '" . $Global['SessionID'] . "';
                var url = 'content.html?option_id=' + option + '&criteria=' + criteria + '&session=' + session_id;
                xmlhttp.onreadystatechange=function(){display_fetch_data(xmlhttp,dest);};
                xmlhttp.open('GET',url,false);
                xmlhttp.send(null);
                dest = null;
                dest_name = null;
                url = null;
                xmlhttp = null;
            }

            function display_fetch_data(oxmlhttp,odest){
                var flg = 0;
                if (oxmlhttp.readyState==4 ){
                    if ( oxmlhttp.status==200 ){
                        for( var prop in odest ){
                            if( prop.toLowerCase() == 'value' ){
                                odest[prop] = oxmlhttp.responseText;
                                flg = 1;
                            }
                        }
                        if( flg == 0 ){
                            for( var prop in odest ){
                                if( prop.toLowerCase() == 'innerhtml' ){
                                    odest[prop] = oxmlhttp.responseText;
                                    flg = 1;
                                }
                            }
                        }
                    }else{
                        alert('Problem retrieving data:'+ oxmlhttp.statusText)
                    }
                }
                flg      = null;
                odest    = null;
                oxmlhttp = null;
            }

            function edit_template_click(){
                var page = document.forms[0].document.all;
                page.message_body.readOnly = false;
                page.message_subject.readOnly = false;
                page.message_template.selectedIndex = 0;
                page.message_dirty.value = 1;
                page.message_subject.focus();
                
            }

            function template_select(){
                var page = document.forms[0].document.all;
                var session_id = '" . $Global['SessionID'] . "';
                var template_id = page.message_template[page.message_template.selectedIndex].value;
                var flg_complete = 0;
                page.message_dirty.value = 0;
                page.message_body.readOnly = true;
                page.message_subject.readOnly = true;
                if( template_id != '' ){
                    while( flg_complete == 0 ){
                        flg_complete = fetch_data('2', template_id ,'message_subject');
                        flg_complete = fetch_data('3', template_id ,'message_body');
                    }
                }else{
                    page.message_body.innerHTML = '';
                    page.message_subject.value = '';
                }
            }
            
            function select_keypress_call_function(func){
                var key = window.event.keyCode;
                if( key == 13 ){
                    function(){func;};
                }
            }
            
            function lookup_event(){
                var key = window.event.keyCode;
                if( key == 13 ){
                    fetch_data( 1, document.getElementById('event_number').value, 'event_details', 'event_table' );
                }
            }

        </SCRIPT>
        <form id='alert_admin' action='$strURL' method='post'>
        <input type='hidden' name='form_action' id='form_action'>
        <input type='hidden' name='criteria_list' id='criteria_list' value='$strCriteriaHidden'>
        <input type='hidden' name='message_dirty' id='message_dirty' value='" . ( isset($arrMessage['template']) && $arrMessage['template'] != 1 ? '1' : '') . "'>
        <table>
          <tr>
          <td valign=top>
        <table>
          <tr>
            <td colspan=6 valign='top'><b>${gaLiterals['Current Alerts']}</b><br>" . 
                build_drop_down( 
                    'SELECT id_dad_adm_alert, description FROM dad_adm_alert ORDER BY description ASC', 
                    'alert_id', 
                    $arr['id_dad_adm_alert'], 
                    "MULTIPLE class=\"wide\" ondblclick=\"record_action_and_submit('lookup');\"" 
                )
         . "</td>
          </tr><tr>
            <td colspan=5>";
    if( isset($Global['alert_id']) ){
        $strHTML .= "<INPUT type=button name=bt id=bt value='${gaLiterals['Update']}' onclick=\"record_action_and_submit('update');\">";
    }
    $strHTML .= "
              <INPUT type=button name=bt id=bt value='${gaLiterals['Save as New']}' onclick=\"record_action_and_submit('saveasnew',0);\">
              <INPUT type=button name=bt id=bt value='${gaLiterals['Delete']}' onclick=\"delete_bt_click(alert_id);\">
              <INPUT type=button name=bt id=bt value='${gaLiterals['New']}' onclick=\"window.navigate('$strURL');\">
              <INPUT type=button name=bt id=bt value='${gaLiterals['Refresh']}' onclick=\"record_action_and_submit('lookup');\">
              ${gaLiterals['Active']}: <input type=checkbox id=\"cbactive\" name=\"cbactive\" " . (isset($arr['active']) && $arr['active'] == 1 || $arr['id_dad_adm_action'] == '' ? 'CHECKED' : '') . ">
            </td>
          </tr><tr>
            <td align=right>${gaLiterals['Description']}:</td>
            <td colspan=3><input type=text name=description id=description size=45 maxlength=45 value='" . ( isset($arr['description']) ? $arr['description'] : '') . "'></td>
            <td nowrap><b>${gaLiterals['Suppress Duplicates']}</b></td>
          </tr><tr>
            <td align=right>${gaLiterals['Action']}:</td>
            <td>" . 
                build_drop_down(
                    'SELECT id_dad_adm_action, name FROM dad.dad_adm_action WHERE activeyesno = 1 ORDER BY name ASC',
                    'id_dad_adm_action',
                    ( isset($arr['id_dad_adm_action']) ? $arr['id_dad_adm_action'] : '')
                )
          . "</td>
            <td nowrap align='right' class='readonly'>${gaLiterals['Last Changed By']}:</td>
            <td class='readonly'>" . ( isset($arr['calleractive']) ? $arr['calleractive'] : '') . "</td>
            <td>
              ${gaLiterals['Interval']}:
              <input type='text' name='supress_interval' id='supress_interval' title='The number of minutes between each event' size=3 value='" . ( isset($arr['supress_interval']) ? $arr['supress_interval'] : '') . "'>
            </td>
          </tr><tr>
            <td align=right>${gaLiterals['Alert Group']}:</td>
            <td>" . 
              build_drop_down(
                  'SELECT id_dad_adm_alertgroup, name FROM dad_adm_alert_group ORDER BY name ASC',
                  'alert_group',
                  ( isset($arr['id_dad_adm_alert_group']) ? $arr['id_dad_adm_alert_group'] : '')
              )
          ."</td>
            <td nowrap align=right class=\"readonly\">${gaLiterals['Last Changed On']}:</td>
            <td class=\"readonly\">" . ( isset($arr['timeactive']) ? $arr['timeactive'] : '') . "</td>
            <td rowspan=5 nowrap>${gaLiterals['Duplicate Fields']}:
            " . 
              build_check_box_scroll( 
                 'SHOW COLUMNS FROM dad_sys_events', 
                 'cb_supress_',
                 $arrSupress,
                 'style="height:150pt"',
                 0,
                 0
                )
         . "</td>
          </tr><tr>
            <td align=right>${gaLiterals['Computer Group']}:</td>
            <td>" . 
              build_drop_down(
                  'SELECT id_dad_adm_computer_group, group_name FROM dad_adm_computer_group ORDER BY group_name ASC',
                  'computer_group',
                  ( isset($arr['id_dad_adm_computer_group']) ? $arr['id_dad_adm_computer_group'] : '')
              )
          ."</td>
            <td align=right>${gaLiterals['Notes']}:</td>
            <td><textarea id='notes' name='notes'>${arr['notes']}</textarea></td>
          </tr><tr>
            <td colspan=4><b>Criteria</b></td>
          </tr><tr>
            <td align=right>${gaLiterals['Field']}:</td>
            <td>" . 
                /*using field 0 in the returned SQL structure for both the displayed data and the values of the OPTIONs
                  since we cannot control what order the SHOW COLUMNS returns the data in*/
                build_drop_down( 
                    'SHOW COLUMNS FROM dad_sys_events',
                    'criteria_col',
                    '',
                    '',
                    0,
                    0
                )
          ."</td>
            <td align=right>${gaLiterals['Value']}:</td>
            <td><input type=text id='criteria_match' name='criteria_match' onkeypress=\"criteria_match_keypress();\"></td>
          </tr><tr>
              <td colspan=4>
                <input type='button' id='bt' name='bt' value=\"${gaLiterals['Add']}\" onclick='add_criteria();'>
                <input type='button' id='bt' name='bt' value=\"${gaLiterals['Remove']}\" onclick=\"remove_node(criteria_built);record_list(criteria_built,criteria_list,'~~~');\">
                <select id='criteria_built' name='criteria_built' size=5 MULTIPLE class=\"wide\" ondblclick=\"remove_node(this);record_list(this,criteria_list,'~~~');\">$strCriteria</select></td>
          </tr><tr>
            <td colspan=5 valign=\"top\" nowrap>
              <b>${gaLiterals['Message']}</b><br>
              ${gaLiterals['Subject']}: <input type='text' id='message_subject' name='message_subject' " . ( isset($arrMessage['template']) && $arrMessage['template'] < 1 ? '' : 'READONLY') . " size=\"100%\" value=\"${arrMessage['subject']}\">
            </td>
          </tr><tr>
            <td colspan=5 rowspan=2 valign=\"top\" nowrap>
              <div align=\"right\">
                ${gaLiterals['Templates']}: " .
              build_drop_down(
                  'SELECT id_dad_adm_alert_message, description FROM dad_adm_alert_message WHERE template = 1 ORDER BY description ASC',
                  'message_template',
                  (isset($arr[id_dad_adm_alert_message]) ? $arr[id_dad_adm_alert_message] : null),
                  "onchange='template_select();'"
              )
              ." 
                <input type=button value=\"${gaLiterals['Edit']}\" onclick=\"edit_template_click();\">
              </div>
              ${gaLiterals['Body']}:<br>
              <textarea id='message_body' name='message_body' " . ( isset($arrMessage['template']) && $arrMessage['template'] < 1 ? '' : 'READONLY') . " rows=10 cols=\"82%\" title=\"For variables, use a field name with a dollar sign on each side of it - e.g. \$field_2$. \">${arrMessage['body']}</textarea>
            </td>
          </tr>";
    $strHTML .="</table>
    </td>
      <td rowspan=1000 valign='top' class='readonly' width='225pt' nowrap>
        <b>${gaLiterals['Event Lookup']}:</b><br>
        <input type='text' id='event_number' size='20' onkeypress=\"lookup_event();\" onblur=\"fetch_data( 1, document.getElementById('event_number').value, 'event_details', 'event_table' )\">
        <div id='event_details'><div>
      </td>
    </tr>      
    <table></form>";
    
    add_element($strHTML);

}

?>
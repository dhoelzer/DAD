<?php



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
            add_element( "Deleted \"${Global['groupname']}\"" );
        }else{
            add_element( "<font color=red>ERROR deleting \"${Global['groupname']}\"</font>" );
        }
    }

    if ( isset($Global['form_action']) && $Global['form_action'] === 'saveasnew' ){
        if( isset($Global['groupname']) && preg_match( '/\S/', $Global['groupname'] ) ){
            /*NEED INPUT VALIDATION*/
            $strID = runInsertReturnID( "INSERT INTO dad_adm_alert_group( name, description, calleractive, timeactive)VALUES( '${Global['groupname']}', '${Global['descrip']}', '${Global['txtUserName']}', unix_timestamp() )" );
            if( $strID ){
                //ADD email address
                $arr = explode(',',$Global['selectedusers_list']);
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
                add_element( "Added \"${Global['groupname']}\"" );
            }else{
                add_element( "<font color=red>ERROR adding \"${Global['groupname']}\"</font>" );
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
                    $arr = explode(',',$Global['selectedusers_list']);
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
                    add_element( "Updated \"${Global['groupname']}\"" );
                }else{
                    if( isset($Global['alertgroup_id']) && $Global['alertgroup_id'] != '' ){
                        add_element( "<font color=red>ERROR updating \"${Global['groupname']}\". Can't insert new data</font>" );
                    }else{
                        add_element( "<font color=red>ERROR updating \"${Global['groupname']}\". Group does not exist</font>" );
                    }
                }
            }else{
                add_element( "<font color=red>ERROR updating \"${Global['groupname']}\". Can't remove old entry</font>" );
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
            <b>All Users</b>";
    $strHTML .= build_drop_down( "SELECT id_dad_adm_alertuser, concat(lastname, ', ', firstname) as fullname FROM dad_adm_alertuser ORDER BY concat(lastname, ', ', firstname) ASC", 'allusers', '', "MULTIPLE style=\"width:100%\" ondblclick=\"copy_node_to(this,selectedusers,selectedusers_list);\" onkeypress=\"select_keypress_copy(this,selectedusers,selectedusers_list);\" ");  
    $strHTML .= "</td>
            <td colspan=2>
            <b>Current Members</b>";
    $strSQL = "SELECT u.id_dad_adm_alertuser, concat(u.lastname, ', ', u.firstname) as fullname 
               FROM dad_adm_alertuser as u 
               INNER JOIN dad_adm_alert_group_member m ON u.id_dad_adm_alertuser = m.id_dad_adm_alertuser 
               WHERE m.id_dad_adm_alertgroup = ${Global['alertgroup_id']} 
               ORDER BY concat(lastname, ', ', firstname) ASC";
    $strHTML .= build_drop_down( $strSQL, 'selectedusers', '', "MULTIPLE style=\"width:100%\" ondblclick=\"remove_node(this);\"");
    $strHTML .= "</td>
          </tr></table>";
    $strHTML .= "</form>";
    //$strHTML .= "<SCRIPT>record_list(document.forms[0].selectedusers);</SCRIPT>";
    $strHTML .= "<script>record_list('selectedusers','selectedusers_list')</script>";

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
            add_element( "${gaLiterals['Deleted']} \"${Global['lastname']}, ${Global['firstname']}\"" );
        }else{
            add_element( "<font color=red>${gaLiterals['ERROR']} ${gaLiterals['Deleting']} \"${Global['lastname']}, ${Global['firstname']}\"</font>" );
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
                $arr = explode(',',$Global['selectedgroups_list']);
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
                add_element( "${gaLiterals['Added']} \"${Global['lastname']}, ${Global['firstname']}\"" );
            }else{
                add_element( "<font color=red>${gaLiterals['ERROR']} ${gaLiterals['Adding']} \"${Global['lastname']}, ${Global['firstname']}\"</font>" );
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
                    $arr = explode(',',$Global['selectedgroups_list']);
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
                    add_element( "${gaLiterals['Updated']} \"${Global['lastname']}, ${Global['firstname']}\"" );
                }else{
                    add_element( "<font color=red>ERROR updating \"${Global['lastname']}, ${Global['firstname']}\". Can't insert new data</font>" );
                }
            }else{
                add_element( "<font color=red>ERROR updating \"${Global['lastname']}, ${Global['firstname']}\". Can't remove old entry</font>" );
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
            <b>${gaLiterals['All']} ${gaLiterals['Groups']}</b>";
    $strHTML .= build_drop_down( 
                    "SELECT id_dad_adm_alertgroup, name FROM dad_adm_alert_group ORDER BY name ASC", 
                    'allgroups', 
                    '', 
                    "MULTIPLE style=\"width:100%\" ondblclick=\"copy_node_to(this,selectedgroups,selectedgroups_list);\" onkeypress=\"select_keypress_copy(this,selectedusers,selectedusers_list);\" "
                );
    $strHTML .= "</td>
            <td colspan=2>
            <b>${gaLiterals['Current']} ${gaLiterals['Member Of']}</b>";
    $strSQL = "SELECT g.id_dad_adm_alertgroup, name 
               FROM dad_adm_alert_group as g
               INNER JOIN dad_adm_alert_group_member m ON g.id_dad_adm_alertgroup = m.id_dad_adm_alertgroup
               WHERE m.id_dad_adm_alertuser = ${Global['alertuser_id']} 
               ORDER BY name ASC";
    $strHTML .= build_drop_down( 
                    $strSQL, 
                    'selectedgroups',
                    '', 
                    "MULTIPLE style=\"width:100%\" ondblclick=\"remove_node(this);\" "
                );
    $strHTML .= "</td>
          </tr></table></form>";

    if( isset($arr['custom_entry']) && $arr['custom_entry'] == 1){
        $strHTML .= "\n<SCRIPT>unlock_input_fields();</SCRIPT>\n";
    }
    $strHTML .= "<SCRIPT>window.alert_user_admin.alertuser_id.focus();</SCRIPT>";
    add_element( $strHTML );
}



function alert_admin(){
    global $gaLiterals;
    global $Global;

    if( checkOptionPermission( $Global['UserID'], $Global['OptionID'] ) == 0 ){
        dispatch( OPTIONID_LOGOUT );
        return;
    }
    add_element( "<b><font size=2>${gaLiterals['Alerts']}</font></b><br><br>" );

    $strURL  = getOptionURL(OPTIONID_ALERT_ADMIN);
    $a    = '';
    $arr  = array();
    $arr2 = array();
    $arrSupress = array();
    $flg_lookup = 0;
    $strCriteria = '';
    $strCriteriaHidden = '';

    if ( isset($Global['form_action']) && $Global['form_action'] === 'delete' ){
        $strAff = runSQLReturnAffected( "DELETE dad_adm_alert FROM dad_adm_alert WHERE id_dad_adm_alert = ${Global['alert_id']}" );
        $strAff = runSQLReturnAffected( "DELETE dad_adm_alert_criteria FROM dad_adm_alert_criteria WHERE id_dad_adm_alert = ${Global['alert_id']}" );
        $strAff = runSQLReturnAffected( "DELETE dad_adm_alert_supress FROM dad_adm_alert_supress WHERE id_dad_adm_alert = ${Global['alert_id']}" );
        if( is_int($strAff) ){
            add_element( "${gaLiterals['Deleted']} \"${Global['description']}\"" );
        }else{
            add_element( "<font color=red>${gaLiterals['ERROR']} ${gaLiterals['Deleting']} \"${Global['description']}\"</font>" );
        }
    }

    if ( isset($Global['form_action']) && $Global['form_action'] === 'saveasnew' ){
        if( isset($Global['description']) && preg_match( '/\S/', $Global['description'] ) ){
            $strSQL = "INSERT INTO dad_adm_alert( description, active, notes, calleractive, timeactive, supress_interval, id_dad_adm_action ) 
                       VALUES ( 
                           '${Global['description']}', 
                           " . (isset($Global['cbactive']) && strtolower($Global['cbactive'])==='on' ? 1 : 0) . ", 
                           " . (isset($Global['notes']) ? "'${Global['notes']}'" : 'NULL') . ", 
                           '${Global['txtUserName']}', 
                           unix_timestamp(), 
                           " . (isset($Global['supress_interval']) && (preg_match( '/[\D]*\d[\D]*/', $Global['supress_interval'])===1) ? $Global['supress_interval'] : 'NULL') . ", 
                           " . (isset($Global['id_dad_adm_action']) && (preg_match( '/[\D]*\d[\D]*/', $Global['id_dad_adm_action'])===1) ? $Global['id_dad_adm_action'] : 'NULL') . "
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
        }else{
            add_element('<font color=red><b>Description is required</b></font>');
        }
        $flg_lookup = 1;
    }

    if ( isset($Global['form_action']) && $Global['form_action'] === 'update' ){
        if( isset($Global['description']) && preg_match( '/\S/', $Global['description'] ) ){
            /*out with the old...*/
            $strAff = runSQLReturnAffected( "DELETE dad_adm_alert FROM dad_adm_alert WHERE id_dad_adm_alert = ${Global['alert_id']}" );
            $strAff = runSQLReturnAffected( "DELETE dad_adm_alert_criteria FROM dad_adm_alert_criteria WHERE id_dad_adm_alert = ${Global['alert_id']}" );
            $strAff = runSQLReturnAffected( "DELETE dad_adm_alert_supress FROM dad_adm_alert_supress WHERE id_dad_adm_alert = ${Global['alert_id']}" );
            /*in with the new...*/
            $strSQL = "INSERT INTO dad_adm_alert( id_dad_adm_alert, description, active, notes, calleractive, timeactive, supress_interval, id_dad_adm_action ) 
                       VALUES ( 
                           " . (isset($Global['alert_id']) && (preg_match( '/[\D]*\d[\D]*/', $Global['alert_id'])===1) ? $Global['alert_id'] : 'NULL') . ", 
                           '${Global['description']}', 
                           " . (isset($Global['cbactive']) && strtolower($Global['cbactive'])==='on' ? 1 : 0) . ", 
                           " . (isset($Global['notes']) ? "'${Global['notes']}'" : 'NULL') . ", 
                           '${Global['txtUserName']}', 
                           unix_timestamp(), 
                           " . (isset($Global['supress_interval']) && (preg_match( '/[\D]*\d[\D]*/', $Global['supress_interval'])===1) ? $Global['supress_interval'] : 'NULL') . ", 
                           " . (isset($Global['id_dad_adm_action']) && (preg_match( '/[\D]*\d[\D]*/', $Global['id_dad_adm_action'])===1) ? $Global['id_dad_adm_action'] : 'NULL') . "
                       )";
            $strID = runInsertReturnID( $strSQL );

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

        }else{
            add_element('<font color=red><b>Description is required</b></font>');
        }
        $flg_lookup = 1;
    }

    if ( (isset($Global['form_action']) && $Global['form_action'] === 'lookup') || $flg_lookup ){
        $strSQL  = "SELECT id_dad_adm_alert, id_dad_adm_action, description, notes, calleractive, from_unixtime(timeactive) as timeactive, supress_interval, active FROM dad_adm_alert WHERE id_dad_adm_alert = ${Global['alert_id']} ";
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
                page.criteria_built.appendChild(oNewNode);

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
            

        </SCRIPT>
        <form id='alert_admin' action='$strURL' method='post'>
        <input type='hidden' name='form_action' id='form_action'>
        <input type='hidden' name='criteria_list' id='criteria_list' value='$strCriteriaHidden'>
        <table>
          <tr>
            <td rowspan=10 valign='top'><b>${gaLiterals['Current Alerts']}</b><br>" . 
                build_drop_down( 
                    'SELECT id_dad_adm_alert, description FROM dad_adm_alert ORDER BY description ASC', 
                    'alert_id', 
                    $arr['id_dad_adm_alert'], 
                    "MULTIPLE size=18 class=\"long\" ondblclick=\"record_action_and_submit('lookup');\"" 
                )
         . "</td>
            <td colspan=4>";
    if( isset($Global['alert_id']) ){
        $strHTML .= "<INPUT type=button name=bt id=bt value='${gaLiterals['Update']}' onclick=\"record_action_and_submit('update');\">";
    }
    $strHTML .= "
              <INPUT type=button name=bt id=bt value='${gaLiterals['Save as New']}' onclick=\"record_action_and_submit('saveasnew',0);\">
              <INPUT type=button name=bt id=bt value='${gaLiterals['Delete']}' onclick=\"delete_bt_click(alert_id);\">
              <INPUT type=button name=bt id=bt value='${gaLiterals['New']}' onclick=\"window.navigate('$strURL');\">
              <INPUT type=button name=bt id=bt value='${gaLiterals['Refresh']}' onclick=\"record_action_and_submit('lookup');\">
              ${gaLiterals['Active']}: <input type=checkbox id=\"cbactive\" name=\"cbactive\" " . (isset($arr['active']) && $arr['active'] == 1 ? 'CHECKED' : '') . ">
            </td>
          </tr><tr>
            <td align=right>${gaLiterals['Description']}:</td>
            <td colspan=3><input type=text name=description id=description size=45 maxlength=45 value='" . ( isset($arr['description']) ? $arr['description'] : '') . "'></td>
          </tr><tr>
            <td align=right>${gaLiterals['Action']}:</td>
            <td>" . 
                build_drop_down(
                    'SELECT id_dad_adm_action, name FROM dad.dad_adm_action WHERE activeyesno = 1 ORDER BY name desc',
                    'id_dad_adm_action',
                    ( isset($arr['id_dad_adm_action']) ? $arr['id_dad_adm_action'] : '')
                )
          . "</td>
            <td nowrap align='right' class='readonly'>${gaLiterals['Last Changed By']}:</td>
            <td class='readonly'>" . ( isset($arr['calleractive']) ? $arr['calleractive'] : '') . "</td>
          </tr><tr>
            <td align=right>${gaLiterals['Notes']}:</td>
            <td><textarea id='notes' name='notes'>${arr['notes']}</textarea></td>
            <td nowrap align=right class=\"readonly\">${gaLiterals['Last Changed On']}:</td>
            <td class=\"readonly\">" . ( isset($arr['timeactive']) ? $arr['timeactive'] : '') . "</td>
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
            <td colspan=4><b>Supress Duplicate Alerts</b></td>
          </tr><tr>
            <td align='right' nowrap>${gaLiterals['Interval']}:</td>
            <td colspan=3><input type='text' name='supress_interval' id='supress_interval' title='The number of seconds between each event' value='" . ( isset($arr['supress_interval']) ? $arr['supress_interval'] : '') . "'></td>
          </tr><tr>
            <td nowrap colspan='4' valign='top'>${gaLiterals['Duplicate Fields']}:<br>" . 
               build_check_box_table ( 
                 'SHOW COLUMNS FROM dad_sys_events', 
                 5, 
                 1, 
                 'cb_supress_',
                 $arrSupress,
                 0,
                 0
               )
         . "</td>          
          </tr>";
    $strHTML .="</table></form>";
    
    add_element($strHTML);

}

?>
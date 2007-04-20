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

function edit_job() {

    global $gaLiterals;
    global $Global;

    if( checkOptionPermission( $Global['UserID'], $Global['OptionID'] ) == 0 ){
        dispatch( OPTIONID_LOGOUT );
        return;
    }
    add_element( "<b><font size=2>${gaLiterals['Jobs']}</font></b><br><br>" );
    $strURL  = getOptionURL(OPTIONID_JOBS);

    $strHTML  = "<SCRIPT ID='clientEventHandlersJS' LANGUAGE='javascript'>
                    function delete_bt_click(){
	                    var element = document.getElementById('id_dad_adm_job');
                        if( element.value < 1 ){
                            alert( 'Please select a job' );
                        }else{
    	        	        var TellMe = confirm( 'Are you sure you want to delete this job?' );
                            if ( TellMe ){
                               document.getElementById('form_action').value='delete';
                                window.edit_job.submit();
                            }
                        }
                    }
                    function saveasnew_bt_click(){
	                    var element = document.getElementById('form_action');
                        element.value = 'saveasnew';
                        window.edit_job.submit();
                    }
                    function select_job_click(){
                        document.getElementById('form_action').value='lookup';
                        document.edit_job.submit();
                    }
                </SCRIPT>";

    if( (isset( $Global['bt'] ) && $Global['bt'] === $gaLiterals['Update']) || (isset( $Global['form_action'] ) && $Global['form_action'] === 'saveasnew') ) {

        $flgBad = '';

        //check if first and last name exists; unique full name not required
        if( !isset( $Global['descrip'] ) || $Global['descrip'] == '' ) {
            add_element( "<font color=red>${gaLiterals['Description']} ${gaLiterals['Required']}</font><br>" );
            $flgBad = 1;
        }

        //if all the above checks pass, will go ahead and create the user
        if( $flgBad != 1 ){
        
            if( isset($Global['form_action']) && $Global['form_action'] === 'saveasnew' ){
                $Global['id_dad_adm_job'] = '';
            }

            $strSQL = "DELETE dad_adm_job FROM dad_adm_job WHERE id_dad_adm_job = '${Global['id_dad_adm_job']}'";
            $strAff = runSQLReturnAffected( $strSQL );
			// Right now there is almost NO validation of this information to ensure that it is a valid date!!!  TODO
			list($hour, $minute) = split(":",$Global['start_time']);
			list($year, $month, $day) = split("-", $Global['start_date']);
			$first_start_time = mktime($hour, $minute, 0, $month, $day, $year);
            $strSQL = "INSERT INTO dad_adm_job( 
                id_dad_adm_job,
                descrip,
                length,
                job_type,
                path,
                package_name,
                calleractive,
                next_start,
                user_name,
                distinguishedname,
                pword,
                times_to_run,
                times_ran,
                start_date,
                start_time,
                last_ran,
                min,
                hour,
                day,
                month,
				is_running,
				persistent
              ) VALUES ( 
                " . (isset($Global['id_dad_adm_job']) && $Global['id_dad_adm_job'] > 0 ? "'${Global['id_dad_adm_job']}'":'NULL') . ",
                '${Global['descrip']}',
                " . (isset($Global['length']) && $Global['length'] > 0 ? "'${Global['length']}'":'NULL') . ",
                '${Global['job_type']}',
                '${Global['path']}',
                '${Global['package_name']}',
                '${Global['calleractive']}',
                $first_start_time,
                '${Global['user_name']}',
                '${Global['distinguishedname']}',
                '${Global['pword']}',
                " . (isset($Global['times_to_run']) && $Global['times_to_run'] > 0 ? "'${Global['times_to_run']}'":'NULL') . ",
                '0',
                " . (isset($Global['start_date']) && strlen($Global['start_date']) > 1 ? "'${Global['start_date']}'":'NULL') . ",
                " . (isset($Global['start_time']) && strlen($Global['start_time']) > 1 ? "'${Global['start_time']}'":'NULL') . ",
                " . (isset($Global['last_ran']) && strlen($Global['last_ran']) > 1 ? "unix_timestamp('${Global['last_ran']}')":'NULL') . ",
                '${Global['min']}',
                '${Global['hour']}',
                '${Global['day']}',
                '${Global['month']}',
				FALSE, ".
				(isset($Global['persistent']) ? (($Global['persistent'] == 'on') ? "TRUE" : "FALSE") : "FALSE") . "
              )";

            $strID = runInsertReturnID( $strSQL );
            add_element( "<font color=red><b>Successfully added \"${Global['descrip']}\"</b></font>" );
            
            //LOGGING
            //logger( "JOB CREATION SUCCESS: UserID: $strUserID; UserName: ${Global['username']}; FirstName: ${Global['firstname']}'; LastName: ${Global['lastname']}; Email: ${Global['email']}; RoleID: ${Global['role']}; " );

        }

    }

    if( isset( $Global['form_action'] ) && $Global['form_action'] === 'delete' ) {
        $strSQL = "DELETE dad_adm_job FROM dad_adm_job WHERE id_dad_adm_job='${Global['id_dad_adm_job']}'";
        $strAff = runSQLReturnAffected( $strSQL );
        if( $strAff ){
            add_element( '<font color=red><b>DELETED</b></font>' );
        }else{
            add_element( '<font color=red><b>Error deleting job</b></font>' );
        }
    }

    if( isset( $Global['form_action'] ) && ($Global['form_action'] === 'lookup' || $Global['bt'] === $gaLiterals['Update'] || $Global['form_action'] === 'delete') ) {
        $strSQL = "SELECT id_dad_adm_job, descrip, length, job_type, path, package_name, calleractive, from_unixtime(next_start) as 'next_start', user_name, 
                     distinguishedname, pword, times_to_run, times_ran, start_date, start_time, from_unixtime(last_ran) as 'last_ran', min, hour, day, month, persistent 
                   FROM dad_adm_job WHERE id_dad_adm_job='${Global['id_dad_adm_job']}'";
        $arrDetails = runQueryReturnArray( $strSQL );
        $arrDetails = array_shift( $arrDetails );
    }

    $strSQL  = "SELECT id_dad_adm_job, descrip FROM dad_adm_job ORDER BY descrip ASC";
    $arrJobs = runQueryReturnArray( $strSQL );

    $strHTML .="
      <form name='edit_job' id='edit_job' action='$strURL' method='post'>\n
        <input type='hidden' name='form_action' id='form_action'>
        <table>
          <colgroup valign=top></colgroup>
          <tr>
            <td align='right'>${gaLiterals['Jobs']}:</td>
            <td colspan=3>
              <SELECT NAME='id_dad_adm_job' ID='id_dad_adm_job' onchange='select_job_click();'>
              <option></option>";
              if(isset($arrJobs)) foreach( $arrJobs as $job ){
                  $strHTML .= "<OPTION VALUE=${job['id_dad_adm_job']}";

                  if( isset( $arrDetails['id_dad_adm_job'] ) && $job['id_dad_adm_job'] == $arrDetails['id_dad_adm_job'] ) {
                      $strHTML .= ' SELECTED>';
                  } else {
                      $strHTML .= '>';
                  }

                  $strHTML .= "${job['descrip']}</OPTION>";
              }
    $strHTML .="
            </SELECT>
            <INPUT type=submit name=bt id=bt value='${gaLiterals['Update']}'>
            <INPUT type=button name=bt id=bt value='${gaLiterals['Save as New']}' onclick='saveasnew_bt_click();'>
            <INPUT type=button name=bt id=bt value='${gaLiterals['Delete']}' onclick='delete_bt_click();'>
            <INPUT type=button name=bt id=bt value='${gaLiterals['New']}' onclick=\"window.navigate('$strURL');\">
            <INPUT type=button name=bt id=bt value='${gaLiterals['Refresh']}' onclick=\"select_job_click();\">
            </td>
          </tr><tr>
          <td align='right'>Description: </td><td><INPUT TYPE='text' NAME='descrip' ID='descrip' VALUE='" . (isset($arrDetails['descrip'])?$arrDetails['descrip']:'')  . "'></td>
          <td align='right'>First Start Time: </td><td><INPUT TYPE='text' NAME='start_time' ID='start_time' Title='Format: HH:MM' VALUE='" . (isset($arrDetails['start_time'])?$arrDetails['start_time']:date("H:i",time())) . "'></td>
          <td align='right'><font color='gray'>Job ID:</font></td><td><font color='gray'>" . (isset($arrDetails['id_dad_adm_job'])?$arrDetails['id_dad_adm_job']:'')  . "</font></td>
          </tr><tr>
          <td align='right'>Job Type: </td><td><INPUT TYPE='text' NAME='job_type' ID='job_type' VALUE='" . (isset($arrDetails['job_type'])?$arrDetails['job_type']:'')  . "'></td>
          <td align='right'>First Start Date: </td><td><INPUT TYPE='text' NAME='start_date' ID='start_date' Title='Format: YYYY-MM-DD' VALUE='" . (isset($arrDetails['start_date'])?$arrDetails['start_date']:date("Y-m-d",time())) . "'></td>
          <td align='right'><font color='gray'>Times Ran:</font></td><td><INPUT TYPE='text' NAME='times_ran' ID='times_ran' READONLY VALUE='" . (isset($arrDetails['times_ran'])?$arrDetails['times_ran']:'')  . "' STYLE=\"color:gray;border:none;\"></td>
          </tr><tr>
          <td align='right'>Path to Script: </td><td><INPUT TYPE='text' NAME='path' ID='path' VALUE='" . (isset($arrDetails['path'])?$arrDetails['path']:'') . "'></td>
          <td align='right'>Times to Run: </td><td><INPUT TYPE='text' NAME='times_to_run' ID='times_to_run' VALUE='" . (isset($arrDetails['time_to_run'])?$arrDetails['time_to_run']:'')  . "'></td>
          <td align='right'><font color='gray'>Last Ran:</font></td><td><INPUT TYPE='text' NAME='last_ran' ID='last_ran' READONLY VALUE='" . (isset($arrDetails['last_ran'])?$arrDetails['last_ran']:'')  . "' STYLE=\"color:gray;border:none;\"></td>
          </tr><tr>
          <td align='right'>Repeat every:</td>
          <td colspan=4><INPUT TYPE='text' NAME='month' ID='month' SIZE='1' title='values: 0-12' VALUE='" . (isset($arrDetails['month'])?$arrDetails['month']:'0')  . "'> months,
			<INPUT TYPE='text' NAME='day' ID='day' SIZE='1' title='values: 0-31' VALUE='" . (isset($arrDetails['day'])?$arrDetails['day']:'0')  . "'> days, 
			<INPUT TYPE='text' NAME='hour' ID='hour' SIZE='1' title='values: 0-23' VALUE='" . (isset($arrDetails['hour'])?$arrDetails['hour']:'0')  . "'> hours, 
			<INPUT TYPE='text' NAME='min' ID='min' SIZE='1' title='values: 0-59' VALUE='" . (isset($arrDetails['min'])?$arrDetails['min']:'0')  . "'> minutes</td>
		</td>
		<td align='right'>Persistent: <input type='checkbox' name=persistent " . (isset($arrDetails['persistent']) ? ($arrDetails['persistent']==1 ? 'CHECKED' : '') : '') . ">
        </tr>
        </table>";

          
    if( isset( $arrVals['calleractive'] ) && $Global['calleractive'] != '' ) {
        $strHTML .="<tr><td align='right'>Who added: </td><td>${Global['calleractive']} on ${Global['next_run']}</td></tr>";
    }

    add_element( $strHTML );

}


?>

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
                    function dow_click(obj){
                        var prev = edit_job.d_of_w.value || 0;
                        if( obj.checked ){
                            edit_job.d_of_w.value = parseInt(prev) + parseInt(obj.value);
                        }else{
                            edit_job.d_of_w.value = parseInt(prev) - parseInt(obj.value);
                        }
                    }
                    function wom_click(obj){
                        var prev = edit_job.w_of_m.value || 0;
                        if( obj.checked ){
                            edit_job.w_of_m.value = parseInt(prev) + parseInt(obj.value);
                        }else{
                            edit_job.w_of_m.value = parseInt(prev) - parseInt(obj.value);
                        }
                    }
                    function moy_click(obj){
                        var prev = edit_job.m_of_y.value || 0;
                        if( obj.checked ){
                            edit_job.m_of_y.value = parseInt(prev) + parseInt(obj.value);
                        }else{
                            edit_job.m_of_y.value = parseInt(prev) - parseInt(obj.value);
                        }
                    }
                    function delete_bt_click(){
	                    var page = document.forms[0].document.all;
                        if( page.id_dad_adm_job.value < 1 ){
                            alert( 'Please select a job' );
                        }else{
    	        	        var TellMe = confirm( 'Are you sure you want to delete this job?' );
                            if ( TellMe ){
                                page.form_action.value = 'delete';
                                window.edit_job.submit();
                            }
                        }
                    }
                    function select_job_click(){
                        var page = document.forms[0].document.all;
                        page.form_action.value = 'lookup';
                        window.edit_job.submit();
                    }
                </SCRIPT>";


    if( isset( $Global['form_action'] ) && $Global['form_action'] === 'delete' ) {
        $strSQL = "DELETE dad_adm_job FROM dad_adm_job WHERE id_dad_adm_job='${Global['id_dad_adm_job']}'";
        $strAff = runSQLReturnAffected( $strSQL );
        if( $strAff ){
            add_element( '<font color=red><b>DELETED</b></font>' );
        }else{
            add_element( '<font color=red><b>Error deleting job</b></font>' );
        }
    }
    
    if( isset( $Global['form_action'] ) && $Global['form_action'] === 'lookup' ) {
        $strSQL = "SELECT id_dad_adm_job, descrip, length, job_type, path, package_name, calleractive, timeactive, user_name, distinguishedname, pword, 
                     frequency, times_to_run, start_date, start_time, d_of_w, w_of_m,m_of_y 
                   FROM dad_adm_job WHERE id_dad_adm_job='${Global['id_dad_adm_job']}'";
        $arrDetails = runQueryReturnArray( $strSQL );
        $arrDetails = array_shift( $arrDetails );
    }
    
    
    if( isset( $Global['bt'] ) && $Global['bt'] === $gaLiterals['Save'] ) {

        $flgBad = '';

        //check if first and last name exists; unique full name not required
        if( !isset( $Global['descrip'] ) || $Global['descrip'] == '' ) {
            add_element( "<font color=red>${gaLiterals['Description']} ${gaLiterals['Required']}</font><br>" );
            $flgBad = 1;
        }



        //if all the above checks pass, will go ahead and create the user
        if( $flgBad != 1 ){

            $strSQL = "DELETE dad_adm_job FROM dad_adm_job WHERE descrip = '${Global['descrip']}'";
            $strAff = runSQLReturnAffected( $strSQL );

            $strSQL = "INSERT INTO dad_adm_job( 
                      id_dad_adm_job,
                      descrip,
                      length,
                      job_type,
                      path,
                      package_name,
                      calleractive,
                      timeactive,
                      user_name,
                      distinguishedname,
                      pword,
                      frequency,
                      times_to_run,
                      start_date,
                      start_time,
                      d_of_w,
                      w_of_m,
                      m_of_y
                    ) VALUES (
                     " . (isset($Global['id_dad_adm_job']) && $Global['id_dad_adm_job'] > 0 ? "'${Global['id_dad_adm_job']}'":'NULL') . ",
                     '${Global['descrip']}',
                     " . (isset($Global['length']) && $Global['length'] > 0 ? "'${Global['length']}'":'NULL') . ",
                     '${Global['job_type']}',
                     '${Global['path']}',
                     '${Global['package_name']}',
                     '${Global['calleractive']}',
                     NOW(),
                     '${Global['user_name']}',
                     '${Global['distinguishedname']}',
                     '${Global['pword']}',
                     " . (isset($Global['frequency']) && $Global['frequency'] > 0 ? "'${Global['frequency']}'":'NULL') . ",
                     " . (isset($Global['times_to_run']) && $Global['times_to_run'] > 0 ? "'${Global['times_to_run']}'":'NULL') . ",
                     " . (isset($Global['start_date']) && strlen($Global['start_date']) > 1 ? "'${Global['start_date']}'":'NULL') . ",
                     " . (isset($Global['start_time']) && strlen($Global['start_time']) > 1 ? "'${Global['start_time']}'":'NULL') . ",
                     " . (isset($Global['d_of_w']) && $Global['d_of_w'] > 0 ? "'${Global['d_of_w']}'":'NULL') . ",
                     " . (isset($Global['w_of_m']) && $Global['w_of_m'] > 0 ? "'${Global['w_of_m']}'":'NULL') . ",
                     " . (isset($Global['m_of_y']) && $Global['m_of_y'] > 0 ? "'${Global['m_of_y']}'":'NULL') . " 
                   );";

            $strID = runInsertReturnID( $strSQL );

            add_element( "<font color=red><b>Successfully added \"${Global['descrip']}\"</b></font>" );
            
            //LOGGING
            //logger( "JOB CREATION SUCCESS: UserID: $strUserID; UserName: ${Global['username']}; FirstName: ${Global['firstname']}'; LastName: ${Global['lastname']}; Email: ${Global['email']}; RoleID: ${Global['role']}; " );

        }

    }

    if( isset($arrDetails) ){
        $arrVals = array( 
                'id_dad_adm_job' => $arrDetails['id_dad_adm_job'],
                'descrip'        => $arrDetails['descrip'],
                'length'         => $arrDetails['length'],
                'job_type'       => $arrDetails['job_type'],
                'path'           => $arrDetails['path'],
                'package_name'   => $arrDetails['package_name'],
                'user_name'      => $arrDetails['user_name'],
                'distinguishedname' => $arrDetails['distinguishedname'],
                //'pword'  => $arrDetails[''],
                'frequency'    => $arrDetails['frequency'],
                'times_to_run' => $arrDetails['times_to_run'],
                'times_ran'    => $arrDetails['times_ran'],
                'start_date'   => $arrDetails['start_date'],
                'start_time'   => $arrDetails['start_time'],
                'd_of_w'       => $arrDetails['d_of_w'],
                'w_of_m'       => $arrDetails['w_of_m'],
                'm_of_y'       => $arrDetails['m_of_y'],
                'last_ran'     => $arrDetails['last_ran'],
                'calleractive' => $arrDetails['calleractive'],
                'timeactive'   => $arrDetails['timeactive']
        );

    }else{
        $arrVals = array( 
                'id_dad_adm_job' => ( isset( $Global['id_dad_adm_job'] ) ? $Global['id_dad_adm_job'] : '' ),
                'descrip'        => ( isset( $Global['descrip'] ) ? $Global['descrip'] : '' ),
                'length'         => ( isset( $Global['length'] ) ? $Global['length'] : '' ),
                'job_type'       => ( isset( $Global['job_type'] ) ? $Global['job_type'] : '' ),
                'path'           => ( isset( $Global['path'] ) ? $Global['path'] : '' ),
                'package_name'   => ( isset( $Global['package_name'] ) ? $Global['package_name'] : '' ),
                'user_name'       => ( isset( $Global['user_name'] ) ? $Global['user_name'] : '' ),
                'distinguishedname'  => ( isset( $Global['distinguishedname'] ) ? $Global['distinguishedname'] : '' ),
                //'pword'  => ( isset( $Global['pword'] ) ? $Global['papwordth'] : '' ),
                'frequency'    => ( isset( $Global['frequency'] ) ? $Global['frequency'] : '' ),
                'times_to_run' => ( isset( $Global['times_to_run'] ) ? $Global['times_to_run'] : '' ),
                'times_ran'    => ( isset( $Global['times_ran'] ) ? $Global['times_ran'] : '' ),
                'start_date'   => ( isset( $Global['start_date'] ) ? $Global['start_date'] : '' ),
                'start_time'   => ( isset( $Global['start_time'] ) ? $Global['start_time'] : '' ),
                'd_of_w'       => ( isset( $Global['d_of_w'] ) ? $Global['d_of_w'] : '0' ),
                'w_of_m'       => ( isset( $Global['w_of_m'] ) ? $Global['w_of_m'] : '0' ),
                'm_of_y'       => ( isset( $Global['m_of_y'] ) ? $Global['m_of_y'] : '0' ),
                'last_ran'     => ( isset( $Global['last_ran'] ) ? $Global['last_ran'] : '' ),
                'calleractive' => ( isset( $Global['calleractive'] ) ? $Global['calleractive'] : '' ),
                'timeactive'   => ( isset( $Global['timeactive'] ) ? $Global['timeactive'] : '' )
        );
    }
    
    $strSQL  = "SELECT id_dad_adm_job, descrip FROM dad_adm_job ORDER BY descrip ASC";
    $arrJobs = runQueryReturnArray( $strSQL );

    $strHTML .="
      <form id='edit_job' action='$strURL' method='post'>\n
        <input type='hidden' name='d_of_w' id='d_of_w' value='${arrVals['d_of_w']}'>
        <input type='hidden' name='w_of_m' id='w_of_m' value='${arrVals['w_of_m']}'>
        <input type='hidden' name='m_of_y' id='m_of_y' value='${arrVals['m_of_y']}'>
        <input type='hidden' name='form_action' id='form_action'>
        <table>
          <colgroup valign=top></colgroup>
          <tr>
            <td align='right'>${gaLiterals['Jobs']}:</td>
            <td colspan=3>
              <SELECT NAME='id_dad_adm_job' ID='id_dad_adm_job' onchange='select_job_click();'>
              <option></option>";
              if($arrJobs) {
				foreach( $arrJobs as $job ){
                  $strHTML .= "<OPTION VALUE=${job['id_dad_adm_job']}";

                  if( isset( $arrVals['id_dad_adm_job'] ) && $job['id_dad_adm_job'] == $arrVals['id_dad_adm_job'] ) {
                      $strHTML .= ' SELECTED>';
                  } else {
                      $strHTML .= '>';
                  }

                  $strHTML .= "${job['descrip']}</OPTION>";
				}
			}
    $strHTML .="
            </SELECT>
            <INPUT type=submit name=bt id=bt value='${gaLiterals['Save']}'>
            <INPUT type=button name=bt id=bt value='${gaLiterals['Delete']}' onclick='delete_bt_click();'>
            <INPUT type=button name=bt id=bt value='${gaLiterals['New']}' onclick=\"window.navigate('$strURL');\">
            </td>
          </tr><tr>
          <td align='right'>Description: </td><td><INPUT TYPE='text' NAME='descrip' ID='descrip' VALUE='${arrVals['descrip']}'></td>
          <td align='right'>Start Time: </td><td><INPUT TYPE='text' NAME='start_time' ID='start_time' Title='Format: HH:MM' VALUE='" . (strlen($arrVals['start_time'])>1 ? $arrVals['start_time']:date("H:i",time())) . "'></td>
          </tr><tr>
          <td align='right'>Job Type: </td><td><INPUT TYPE='text' NAME='job_type' ID='job_type' VALUE='${arrVals['job_type']}'></td>
          <td align='right'>Start Date: </td><td><INPUT TYPE='text' NAME='start_date' ID='start_date' Title='Format: YYYY-MM-DD' VALUE='" . (strlen($arrVals['start_date'])>1 ? $arrVals['start_date']:date("Y-m-d",time())) . "'></td>
          </tr><tr>
          <td align='right'>Path to Script: </td><td><INPUT TYPE='text' NAME='path' ID='path' VALUE='${arrVals['path']}'></td>
          <td align='right'>Username: </td><td><INPUT TYPE='text' NAME='user_name' ID='user_name' VALUE='${arrVals['user_name']}'></td>
          </tr><tr>
          <td align='right'>Package Name: </td><td><INPUT TYPE='text' NAME='package_name' ID='package_name' TITLE='For Perl only' VALUE='${arrVals['package_name']}'></td>
          <td align='right'>DN: </td><td><INPUT TYPE='text' NAME='distinguishedname' ID='distinguishedname' VALUE='${arrVals['distinguishedname']}'></td>
          </tr><tr>
          <td align='right'>Path to Script: </td><td><INPUT TYPE='text' NAME='path' ID='path' VALUE='${arrVals['path']}'></td>
          <td align='right'>Password: </td><td><INPUT TYPE='password' NAME='pword' ID='pword' VALUE='${arrVals['pword']}'></td>
          </tr><tr>
          <td align='right'>Frequency: </td>
              <td><SELECT NAME='frequency' ID='frequency'  STYLE=\"width:6pc;\" onchange='form.submit();'>
                  <OPTION VALUE='1' " . ($arrVals['frequency']&1 ? "SELECTED":"") . ">Once</OPTION>
                  <OPTION VALUE='2' " . ($arrVals['frequency']&2 ? "SELECTED":"") . ">Continuous</OPTION>
                  <OPTION VALUE='4' " . ($arrVals['frequency']&4 ? "SELECTED":"") . ">Daily</OPTION>
                  <OPTION VALUE='8' " . ($arrVals['frequency']&8 ? "SELECTED":"") . ">Weekly</OPTION>
                  <OPTION VALUE='16' " . ($arrVals['frequency']&16 ? "SELECTED":"") . ">Monthly</OPTION>
                  <OPTION VALUE='32' " . ($arrVals['frequency']&32 ? "SELECTED":"") . ">Yearly</OPTION>
                </SELECT>
            </td></tr>";
        if( isset( $arrVals['frequency'] ) && $arrVals['frequency'] >= 8 ){
            $strHTML .= "<tr><td align='right'>Day of the week: </td>
                <td colspan=3>
                  <table><colgroup width=100><colgroup width=100><colgroup width=100><tr>
                  <td><INPUT TYPE='checkbox' NAME='dow_su' ID='dow_su' VALUE='1' onclick='dow_click(dow_su);' " . ($arrVals['d_of_w']&1 ? "CHECKED":"") . ">Sunday</td>
                  <td><INPUT TYPE='checkbox' NAME='dow_mo' ID='dow_mo' VALUE='2' onclick='dow_click(dow_mo);' " . ($arrVals['d_of_w']&2 ? "CHECKED":"") . ">Monday</td>
                  <td><INPUT TYPE='checkbox' NAME='dow_tu' ID='dow_tu' VALUE='4' onclick='dow_click(dow_tu);' " . ($arrVals['d_of_w']&4 ? "CHECKED":"") . ">Tuesday</td>
                  </tr><tr>
                  <td><INPUT TYPE='checkbox' NAME='dow_we' ID='dow_we' VALUE='8' onclick='dow_click(dow_we);' " . ($arrVals['d_of_w']&8 ? "CHECKED":"") . ">Wednesday</td>
                  <td><INPUT TYPE='checkbox' NAME='dow_th' ID='dow_th' VALUE='16' onclick='dow_click(dow_th);' " . ($arrVals['d_of_w']&16 ? "CHECKED":"") . ">Thursday</td>
                  <td><INPUT TYPE='checkbox' NAME='dow_fr' ID='dow_fr' VALUE='32' onclick='dow_click(dow_fr);' " . ($arrVals['d_of_w']&32 ? "CHECKED":"") . ">Friday</td>
                  </tr><tr>
                  <td><INPUT TYPE='checkbox' NAME='dow_sa' ID='dow_sa' VALUE='64' onclick='dow_click(dow_sa);' " . ($arrVals['d_of_w']&64 ? "CHECKED":"") . ">Saturday</td>
                  </tr></table>
            </td></tr>";
        }
        if( isset( $arrVals['frequency'] ) && $arrVals['frequency'] >= 16 ){
            $strHTML .= "<tr><td align='right'>Week of the month: </td>
                <td colspan=3>
                  <table><colgroup width=100></colgroup><colgroup width=100></colgroup><colgroup width=100></colgroup><tr>
                  <td><INPUT TYPE='checkbox' NAME='wom_1' ID='wom_1' VALUE='1' onclick='wom_click(wom_1);' " . ($arrVals['w_of_m']&1 ? "CHECKED":"") . ">First</td>
                  <td><INPUT TYPE='checkbox' NAME='wom_2' ID='wom_2' VALUE='2' onclick='wom_click(wom_2);' " . ($arrVals['w_of_m']&2 ? "CHECKED":"") . ">Second</td>
                  <td><INPUT TYPE='checkbox' NAME='wom_3' ID='wom_3' VALUE='4' onclick='wom_click(wom_3);' " . ($arrVals['w_of_m']&4 ? "CHECKED":"") . ">Third</td>
                  </tr><tr>
                  <td><INPUT TYPE='checkbox' NAME='wom_4' ID='wom_4' VALUE='8' onclick='wom_click(wom_4);' " . ($arrVals['w_of_m']&8 ? "CHECKED":"") . ">Forth</td>
                  <td><INPUT TYPE='checkbox' NAME='wom_5' ID='wom_5' VALUE='16' onclick='wom_click(wom_5);' " . ($arrVals['w_of_m']&16 ? "CHECKED":"") . ">Fifth</td>
                  </tr></table>
            </td></tr>";
        }
        if( isset( $arrVals['frequency'] ) && $arrVals['frequency'] >= 32 ){
            $strHTML .= "<tr><td align='right'>Month of the Year: </td>
                <td colspan=3>
                  <table><colgroup width=100></colgroup><colgroup width=100></colgroup><colgroup width=100></colgroup><tr>
                  <td><INPUT TYPE='checkbox' NAME='moy_1' ID='moy_1' VALUE='1' onclick='moy_click(moy_1);' " . ($arrVals['m_of_y']&1 ? "CHECKED":"") . ">January</td>
                  <td><INPUT TYPE='checkbox' NAME='moy_2' ID='moy_2' VALUE='2' onclick='moy_click(moy_2);' " . ($arrVals['m_of_y']&2 ? "CHECKED":"") . ">February</td>
                  <td><INPUT TYPE='checkbox' NAME='moy_3' ID='moy_3' VALUE='4' onclick='moy_click(moy_3);' " . ($arrVals['m_of_y']&4 ? "CHECKED":"") . ">March</td>
                  </tr><tr>
                  <td><INPUT TYPE='checkbox' NAME='moy_4' ID='moy_4' VALUE='8' onclick='moy_click(moy_4);' " . ($arrVals['m_of_y']&8 ? "CHECKED":"") . ">April</td>
                  <td><INPUT TYPE='checkbox' NAME='moy_5' ID='moy_5' VALUE='16' onclick='moy_click(moy_5);' " . ($arrVals['m_of_y']&16 ? "CHECKED":"") . ">May</td>
                  <td><INPUT TYPE='checkbox' NAME='wom_6' ID='wom_6' VALUE='32' onclick='moy_click(wom_6);' " . ($arrVals['m_of_y']&32 ? "CHECKED":"") . ">June</td>
                  </tr><tr>
                  <td><INPUT TYPE='checkbox' NAME='moy_7' ID='moy_7' VALUE='64' onclick='moy_click(moy_7);' " . ($arrVals['m_of_y']&64 ? "CHECKED":"") . ">July</td>
                  <td><INPUT TYPE='checkbox' NAME='moy_8' ID='moy_8' VALUE='128' onclick='moy_click(moy_8);' " . ($arrVals['m_of_y']&128 ? "CHECKED":"") . ">August</td>
                  <td><INPUT TYPE='checkbox' NAME='moy_9' ID='moy_9' VALUE='256' onclick='moy_click(moy_9);' " . ($arrVals['m_of_y']&256 ? "CHECKED":"") . ">September</td>
                  </tr><tr>
                  <td><INPUT TYPE='checkbox' NAME='moy_10' ID='moy_10' VALUE='512' onclick='moy_click(moy_10);' " . ($arrVals['m_of_y']&512 ? "CHECKED":"") . ">October</td>
                  <td><INPUT TYPE='checkbox' NAME='moy_11' ID='moy_11' VALUE='1024' onclick='moy_click(moy_11);' " . ($arrVals['m_of_y']&1024 ? "CHECKED":"") . ">November</td>
                  <td><INPUT TYPE='checkbox' NAME='moy_12' ID='moy_12' VALUE='2048' onclick='moy_click(moy_12);' " . ($arrVals['m_of_y']&2048 ? "CHECKED":"") . ">December</td>
                  </tr><tr>
                  </tr></table>
            </td></tr>";
        }
        
          
    if( isset( $arrVals['calleractive'] ) && $Global['calleractive'] != '' ) {
        $strHTML .="<tr><td align='right'>Who added: </td><td>${Global['calleractive']} on ${Global['timeactive']}</td></tr>";
    }

    add_element( $strHTML );

}


?>

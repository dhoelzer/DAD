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

function manage_carver() {

    global $gaLiterals;
    global $Global;
//PrintGlobal();
    if( checkOptionPermission( $Global['UserID'], $Global['OptionID'] ) == 0 ){
        dispatch( OPTIONID_LOGOUT );
        return;
    }
    add_element( "<b><font size=2>Manage Carving Rules</font></b><br><br>" );
    $strURL  = getOptionURL(OPTIONID_MANAGE_CARVER);

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
                        window.manage_carvers.submit();
                    }
                    function select_carver_click(){
                        document.getElementById('form_action').value='lookup';
                        document.manage_carvers.submit();
                    }
                </SCRIPT>";

    if( (isset( $Global['bt'] ) && $Global['bt'] === $gaLiterals['Update']) || (isset( $Global['form_action'] ) && $Global['form_action'] === 'saveasnew') ) {

        $flgBad = '';

        //check if first and last name exists; unique full name not required
        if( !isset( $Global['match_rule'] ) || $Global['match_rule'] == '' ) {
            add_element( "<font color=red>Match Rule Required</font><br>" );
            $flgBad = 1;
        }
        if( !isset( $Global['carve_rule'] ) || $Global['carve_rule'] == '' ) {
            add_element( "<font color=red>Carving Rule Required</font><br>" );
            $flgBad = 1;
        }

        //if all the above checks pass, will go ahead and create the user
        if( $flgBad != 1 ){
        
            if( isset($Global['form_action']) && $Global['form_action'] === 'saveasnew' ){
                $Global['dad_adm_carvers_id'] = '';
            }

            $strSQL = "DELETE FROM dad_adm_carvers WHERE dad_adm_carvers_id = '${Global['dad_adm_carvers_id']}'";
            $strAff = runSQLReturnAffected( $strSQL );
			// Right now there is almost NO validation of this information to ensure that it is a valid date!!!  TODO
            $strSQL = "INSERT INTO dad_adm_carvers( 
				dad_adm_carvers_id,
				match_rule,
				carve_rule,
				creator_id,
				rule_name
              ) VALUES ( 
                " . (isset($Global['dad_adm_carvers_id']) && $Global['dad_adm_carvers_id'] > 0 ? "'${Global['dad_adm_carvers_id']}'":"NULL") . ",
                '${Global['match_rule']}', '${Global['carve_rule']}', '${Global['UserID']}', '${Global['rule_name']}'
              )";
            $strID = runInsertReturnID( $strSQL );
            add_element( "<font color=red><b>Successfully updated \"${Global['match_rule']}\"</b></font>" );
            
            //LOGGING
            //logger( "JOB CREATION SUCCESS: UserID: $strUserID; UserName: ${Global['username']}; FirstName: ${Global['firstname']}'; LastName: ${Global['lastname']}; Email: ${Global['email']}; RoleID: ${Global['role']}; " );

        }

    }

    if( isset( $Global['form_action'] ) && $Global['form_action'] === 'delete' ) {
        $strSQL = "DELETE FROM dad_adm_carvers WHERE dad_adm_carvers_id='${Global['dad_adm_carvers_id']}'";
        $strAff = runSQLReturnAffected( $strSQL );
        if( $strAff ){
            add_element( '<font color=red><b>DELETED</b></font>' );
        }else{
            add_element( '<font color=red><b>Error deleting carving rule</b></font>' );
        }
    }
	if( isset( $Global['bt'] ) && $Global['bt'] == "Test" )
	{
		$sample_data = $Global['txtSampleData'];
		$match_rule = $Global['match_rule'];
		$carve_rule = $Global['carve_rule'];
		$match_rule = preg_replace('/[\\\]{2}/', '\\', $match_rule);
		$carve_rule = preg_replace('/[\\\]{2}/', '\\', $carve_rule);

		$file = fopen("/dad/sample_data", 'w');
		fwrite($file, $sample_data);
		fclose($file);
		//exec("c:/perl/bin/perl.exe \"/dad/jobs/Log Parser/log_carver.pl\" test test ../../sample_data", $Output);
		exec("perl \"../../jobs/Log Parser/log_carver.pl\" \"${match_rule}\" \"${carve_rule}\" /dad/sample_data", $Output);
		if(isset($Output))
		{$Sample_Output = "Sample Results:<p>";
			foreach ($Output as $line)
			{
				$Sample_Output .= "${line}\n";
			}
		}
	}
    if( isset( $Global['form_action'] ) && ($Global['form_action'] === 'lookup' || $Global['bt'] == "Test" || $Global['bt'] === $gaLiterals['Update'] || $Global['form_action'] === 'delete') ) {
        $strSQL = "SELECT dad_adm_carvers_id, match_rule, carve_rule, rule_name FROM dad_adm_carvers WHERE dad_adm_carvers_id='${Global['dad_adm_carvers_id']}'";
        $arrDetails = runQueryReturnArray( $strSQL );
        if(is_array($arrDetails)){$arrDetails = array_shift( $arrDetails );} else { $arrDetails=null;}
    }

    $strSQL  = "SELECT dad_adm_carvers_id, match_rule, carve_rule, rule_name FROM dad_adm_carvers ORDER BY match_rule ASC";
    $arrCarvers = runQueryReturnArray( $strSQL );

    $strHTML .="
      <form name='manage_carvers' id='manage_carvers' action='$strURL' method='post'>\n
        <input type='hidden' name='form_action' id='form_action'>
        <table>
          <colgroup valign=top></colgroup>
          <tr>
            <td align='right'>Manage Carvers:</td>
            <td>
              <SELECT NAME='dad_adm_carvers_id' ID='dad_adm_carvers_id' onchange='select_carver_click();'>
              <option></option>";
              if(isset($arrCarvers)) foreach( $arrCarvers as $Carver ){
                  $strHTML .= "<OPTION VALUE=${Carver['dad_adm_carvers_id']}";

                  if( isset( $arrDetails['dad_adm_carvers_id'] ) && $Carver['dad_adm_carvers_id'] == $arrDetails['dad_adm_carvers_id'] ) {
                      $strHTML .= ' SELECTED>';
                  } else {
                      $strHTML .= '>';
                  }

                  $strHTML .= "${Carver['rule_name']}</OPTION>";
              }
    $strHTML .="
            </SELECT>
            <INPUT type=submit name=bt id=bt value='${gaLiterals['Update']}'>
            <INPUT type=button name=bt id=bt value='${gaLiterals['Save as New']}' onclick='saveasnew_bt_click();'>
            <INPUT type=button name=bt id=bt value='${gaLiterals['Delete']}' onclick='delete_bt_click();'>
            <INPUT type=button name=bt id=bt value='${gaLiterals['Refresh']}' onclick=\"select_job_click();\">
            </td>
          </tr>
		  <tr>
			<td align='right'>Rule Name: </td>
			<td><INPUT TYPE='text' NAME='rule_name' size=40 ID='rule_name' VALUE='" . (isset($arrDetails['rule_name']) ? $arrDetails['rule_name'] : '') . "'></td>
		  <tr>
			<td align='right'>Selection Rule: </td>
			<td><INPUT TYPE='text' NAME='match_rule' size=80 ID='match_rule' VALUE='" . (isset($arrDetails['match_rule'])?$arrDetails['match_rule']:'')  . "'></td>
		  </tr>
		  <tr>
			<td align='right'>Carve Rule: </td>
			<td><INPUT TYPE='text' NAME='carve_rule' size=80 ID='carve_rule' Title='Use backreferences to select data to store in the database.' VALUE='" . (isset($arrDetails['carve_rule'])?$arrDetails['carve_rule']:"") . "'></td>
		  </tr>
		  <tr>
			<td colspan=2 align='left'><textarea name='txtSampleData' rows=15 cols=80>" . (isset($Global{'txtSampleData'}) ? $Global{'txtSampleData'} : "Paste your sample data here.") . "</textarea></td>
          </tr>
		  <tr>
			<td align='right'>Sample Output:</td><td>${Sample_Output}</td>
		  </tr>
        </table>
		<center><INPUT type=submit name=bt id=bt value='Test'></center>";


    add_element( $strHTML );

}


?>

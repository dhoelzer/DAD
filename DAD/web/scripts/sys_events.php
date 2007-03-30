<?php

function FileAuditSearch() {

    global $gaLiterals;
    global $Global;

    if( checkOptionPermission( $Global['UserID'], $Global['OptionID'] ) == 0 ){
        dispatch( OPTIONID_LOGOUT );
        return;
    }

    $strURL  = getOptionURL(OPTIONID_FILE_AUDIT_SEARCH);
    $strSQL  = '';
    $strHTML = '';
    $strTime = '';

    //if the Create button was click, will do the following code
    if( isset( $Global['bt'] ) && $Global['bt'] === $gaLiterals['Search'] ) {
//        if( $Global['path'] != '' ){
            //field_20 = username, field_7 = server, field_12 = path
            $strTime = dad_microtime_float();
            $strSQL = "SELECT DISTINCT from_unixtime(timegenerated), Computer, field_10, field_2, field_7
                       FROM dad_sys_events
                       WHERE EventID = 560 ";
            if( isset( $Global['path'] ) && $Global['path'] != '' ){
                $tmp = $Global['path'];
                $tmp = preg_replace('/[\\\]+/','\\\\\\\\\\\\\\',$tmp);
                //$strSQL .= "AND field_2 like '$tmp' ";
                $strSQL .= "AND idxID_Code like '560 $tmp' ";
            }
            if( isset( $Global['server'] ) && $Global['server'] != '' ){
                $strSQL .= "AND Computer = '${Global['server']}' ";
            }
            if( isset( $Global['username'] ) && $Global['username'] != '' ){
                $strSQL .= "AND field_10 = '${Global['username']}' ";
            }
            if( isset( $Global['file_ext'] ) && $Global['file_ext'] != '' ){
                $strSQL .= "AND field_25 = '${Global['file_ext']}' ";
            }
            if( isset( $Global['starttime'] ) && $Global['starttime'] != '' ){
                $strSQL .= "AND TimeGenerated >= '" . strtotime($Global['starttime']) . "' ";
            }
            if( isset( $Global['endtime'] ) && $Global['endtime'] != '' ){
                $strSQL .= "AND TimeGenerated <= '" . strtotime($Global['endtime']) . "' ";
            }
            if( isset( $Global['filesonly'] ) && $Global['filesonly'] === 'on' ){
                $strSQL .= "AND field_25 != '' ";
            }
            $strSQL .= 'ORDER BY TimeGenerated ';
            $strSQL .= 'LIMIT 10000 ';
//print $strSQL;
            $arrFiles = runQueryReturnArray( $strSQL );
            $strTime2 = dad_microtime_float();
            $strTime = round( ($strTime2 - $strTime), 3 );
//        }else{
//            add_element( "<font color='red'>Sorry. Need some path to look for.</font><br>" );
//        }
    }

    $Global['path'] = preg_replace('/\\\\\\\\/', '\\', $Global['path']);
    
    $strHTML = "<b><font size=2>${gaLiterals['Search File Access']}</font></b><br><br>";
    $strHTML.= "<form name='fileauditsearch' id='fileauditsearch' action='$strURL' method='post'>\n
                <table>
                  <tr>
                    <td>${gaLiterals['Server']}:</td>
                    <td><input type='text' width='30' name='server' value='" . (isset( $Global['server'] ) ? $Global['server'] : '') . "'></td>
                  </tr><tr>
                    <td>${gaLiterals['Path']}:</td>
                    <td><input type='text' width='30' name='path' title='Start path with D:\ \nCan use wild cards' value='" . (isset( $Global['path'] ) ? $Global['path'] : '') . "'></td>
                  </tr><tr>
                    <td>${gaLiterals['File Extention']}:</td>
                    <td><input type='text' width='30' name='file_ext' title='Do not use leading period' value='" . (isset( $Global['file_ext'] ) ? $Global['file_ext'] : '') . "'></td>
                  </tr><tr>
                    <td>${gaLiterals['User Name']}:</td>
                    <td><input type='text' width='30' name='username' value='" . (isset( $Global['username'] ) ? $Global['username'] : '') . "'></td>
                  </tr><tr>
                    <td>${gaLiterals['Start']} ${gaLiterals['Time']}:</td>
                    <td><input type='text' width='30' name='starttime' title='Find events after this timestamp\ne.g. 2006-10-06 13:00:01' value='" . (isset( $Global['starttime'] ) ? $Global['starttime'] : '') . "'></td>
                    <td><input type='button' value='<-Current Time' onclick=\"document.forms[0].document.all.starttime.value='" . dad_formatted_time() ."'\"></td>
                  </tr><tr>
                    <td>${gaLiterals['End']} ${gaLiterals['Time']}:</td>
                    <td><input type='text' width='30' name='endtime' title='Find events before this timestamp\ne.g. 2006-10-06 13:00:01' value='" . (isset( $Global['endtime'] ) ? $Global['endtime'] : '') . "'></td>
                    <td><input type='button' value='<-Current Time' onclick=\"document.forms[0].document.all.endtime.value='" . dad_formatted_time() ."'\"></td>
                  </tr>
                  <tr>
                    <td>${gaLiterals['Files Only']}:</td>
                    <td><input type='checkbox' name='filesonly'" .($Global['filesonly']&'on' ? "CHECKED":"") ."></td>
                  </tr>
                  <tr>
                    <td><input type='submit' name='bt' value='Search'></td>
                    <td name='querytime' id='querytime'>" . (count($arrFiles)>0 ? count($arrFiles) . " returned in $strTime s" : '') . "</td>
                  </tr>
                </table>";

    if( count( $arrFiles )>0 ){
        $strHTML .= "<table border=on style='font-size:75%'>";
        foreach( $arrFiles as $file ){
            $strHTML .= "<tr><td>${file[0]}</td><td>${file['Computer']}</td><td>${file['field_10']}</td><td>${file['field_2']}</td></tr>\n";
        }
        //$strHTML .= "<script ID='clientEventHandlersJS' language='JavaScript'>document.forms[0].document.all.querytime.innerText='jason'</script>";
    }

    $strHTML .= "</form>";
    add_element( $strHTML );
}

function dad_microtime_float(){
   list($usec, $sec) = explode(" ", microtime());
   return ((float)$usec + (float)$sec);
}

function dad_formatted_time(){
    return date("Y-m-d H:i:s");
}

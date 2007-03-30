<?php

function system_log_display() {

    global $gaLiterals;
    global $Global;

    $strURL  = getOptionURL(OPTIONID_SYSTEM_LOGS);
    $strHTML = '';
    $flg     = 0;

    if( checkOptionPermission( $Global['UserID'], $Global['OptionID'] ) == 0 ){
        dispatch( OPTIONID_LOGOUT );
        return;
    }

//  ---- MAYBE WE'LL ALLOW TWO LEVEL OF RIGHTS ON THIS PAGE - ONE THAT CAN SEE THE EVENTS, ANOTHER THAT CAN ACKNOWLEDGE THE EVENTS

    if( isset($Global['bt']) && $Global['bt'] == $gaLiterals['Acknowledge'] ){

        $SQLtmp = '';

        while( (list($k, $v) = each($Global) ) ){
            if( preg_match( '/^cb(\d+)$/', $k, $matches ) ){
                $SQLtmp =  "id_dad_adm_log = " . $matches[1] . " OR " . $SQLtmp;
                $flg = 1;
            }
        }

        if( $flg ){

            $SQLtmp = substr( $SQLtmp, 0, strlen - 3 );

            $SQL = "UPDATE dad_adm_log SET acknowledged = 1 WHERE " . $SQLtmp;
            runSQLReturnAffected( $SQL );

        }

        $SQLtmp = '';
        $flg    = 0;

    }

    $strHTML .= '<h1>System Events</h1>';
    $strHTML .= '<script language=javascript>
                     function check_all(){
                         var frm = document.formsystemlog;//.document.all;
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

    $strHTML .= "<form name=formsystemlog id=formsystemlog action='$strURL' method='post'>";
    $strHTML .= '<table border=1>';
    $strHTML .= '<COLGROUP>';
    $strHTML .= '  <COL align=right width="2%">';    //checkbox
    $strHTML .= '  <COL align=left width="6%">';     //Type
    $strHTML .= '  <COL align=left width="23%">';    //Event Time
    $strHTML .= '  <COL align=left width="50%">';    //Message
    $strHTML .= '  <COL align=left width="20%">';    //Source
    $strHTML .= "</COLGROUP>\n";
    $strHTML .= '<tr bordercolor=white><td colspan=2><input type=submit name=bt id=bt value=' . $gaLiterals['Acknowledge'] . '></td><td></td><td></td><td></td></tr>';
    $strHTML .= '<tr><td style="border-bottom-color:gray"><input type=checkbox name=cball id=cball onclick="check_all();"></td><td style="border-bottom-color:gray"><b>Type</b></td><td nowrap style="border-bottom-color:gray"><b>Event Time</b></td><td style="border-bottom-color:gray"><b>Message</b></td><td style="border-bottom-color:gray"><b>Source</b></td></tr>';

    $strSQL = "SELECT l.id_dad_adm_log, t.description AS `Type`, l.eventtime, l.message, l.eventsource, TIMEDIFF(l.jobstoptime, l.jobstarttime), l.id_dad_adm_logtype
               FROM dad_adm_log AS l
                 INNER JOIN dad_adm_logtype AS t
                   ON l.id_dad_adm_logtype = t.id_dad_adm_logtype
               WHERE acknowledged = 0
                 -- AND l.id_dad_adm_logtype = 2
               ORDER BY l.id_dad_adm_logtype DESC, l.eventtime DESC
               LIMIT 50";
    $rows = runQueryReturnArray( $strSQL );

    $type = $rows[0][0];

    foreach( $rows as $row ){

        $strHTML .= "<tr valign=top bordercolor=gray><td><input type=checkbox name=cb${row[0]} id=cb${row[0]}></td><td>${row[1]}</td><td>${row[2]}</td><td>${row[3]}";
        if( $row[6] == 2 ){
            if( $row[5] != NULL ){
                $strHTML .= "; Time to complete: ${row[5]}";
            }else{
                $strHTML .= "; <font color=red>Did not complete</font>";
            }
        }
        $strHTML .= "</td><td>${row[4]}</td></tr>";

    }


    $strHTML .= '</table></form>';

    add_element( $msg );
    add_element( $strHTML );
}



?>
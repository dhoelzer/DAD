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

/*-----------------------------------------------------
 * $html = buid_check_box_table ( $strSQL[,$strCols][,$strDirection,][ $arrChecked );
 *-----------------------------------------------------
 *  Will build a table of checkboxes
 *  $strSQL        - string - SQL string, where col 1 is the index to be used, and col 2 is the data to be displayed
 *  $strCols       - int - the maximum number of cols to display
 *                   optional
 *                   default - 3
 *  $strDirection  - int - where displayed data flows top to bottom or left to right
 *                   optional
 *                   1 - default - top to bottom
 *                   2 - left to right
 *  $strNamePrefix - this value will be used in the name and id of each check box; will be suffixed by col 2 of SQL return, (spaces removed)
 *  $arrChecked    - array - will marked selected checkboxes as checked
 *                   values of array need to correspond to values in col 1 of sql
 *  $strColDisplay - int    - column number of select statement to be used for displayed data in each <option> 
 *                            default: 1
 *  $strColValue   - int    - column number of select statement to be used for value of each <option>
 *                            default: 0
 *  NOTE: usually, the only time to use $strColDisplay and $strColValue is when you cannot control the column order, such 
 *        as in a SHOW COLUMNS, etc.
 */
function build_check_box_table ( $strSQL, $strCols=3, $strDirection=1, $strNamePrefix='', $arrChecked=array("cappuccino"), $strColDisplay=1, $strColValue=0 ){
    if( is_null($arrChecked) ){
        $arrChecked = array();
    }
    $checked = '';
    $i = 0;
    $strHTML  = '<table>';

    $arr = runQueryReturnArray( $strSQL );

    if( !is_array($arr) ){
        $strHTML .= '</table>';
        return $strHTML;
    }
    
    if( $strDirection == 1 ){
        /*text flows top to bottom*/
        $arrHTML = array();
        $i = 1;
        $strCols = ceil(count($arr)/$strCols);
        foreach( $arr as $row ){
            if( in_array($row[$strColValue], $arrChecked) ){
                $checked = 'checked';
            }
            $arrHTML[$i] .= "<td><input type=\"checkbox\" $checked id=\"$strNamePrefix" . $row[$strColValue] . "\" name=\"$strNamePrefix" . $row[$strColValue] . "\">" . $row[$strColDisplay] . "</td> ";
            if( $i % $strCols === 0){
                $i=0; /*start with column one again*/
            }
            $i++;
            $checked = '';
        }
        $arr = NULL;
        for( $i=1; $i<=$strCols; $i++ ){
            $strHTML .= '<tr>' . $arrHTML[$i] . '</tr>';
        }
    }elseif( $strDirection == 2){
        /*text flows left to right*/
        $strHTML2 = '';
        $i = 1;
        foreach( $arr as $row ){
            if( in_array($row[$strColValue], $arrChecked) ){
                $checked = 'checked';
            }
            $strHTML2 .= "<td><input type=\"checkbox\" $checked id=\"$strNamePrefix" . $row[$strColValue] . "\" name=\"$strNamePrefix" . $row[$strColValue] . "\">" . $row[$strColDisplay] . "</td> ";
            if( $i % $strCols === 0 ){
                /*new row*/
                $strHTML .= "<tr>$strHTML2</tr>";
                $strHTML2 = '';
            }
            $i++;
            $checked='';
        }
        $arr = NULL;
        if( $strHTML2 ){
            $strHTML .= "<tr>$strHTML2</tr>";
            $strHTML2 = '';
        }
        $i = 0;
    }else{
        $arr = NULL;
        $strHTML .= 'ERROR: incorrect value for text direction in build_check_box_table()';
    }

    $strHTML .= '</table>';
    return $strHTML;
}


/*-----------------------------------------------------
 * $html = build_drop_down ( $strSQL, $strNamePrefix, $strSelected, $strOptions, $strColDisplay, $strColValue );
 *-----------------------------------------------------
 *  Will build a <SELECT> dropdown list
 *  $strSQL        - string - SQL string, where col 1 is the index to be used, and col 2 is the data to be displayed 
 *                            (see $strColDisplay, $strColValue)
 *  $strNamePrefix - string - the name of the object
 *  $strSelected   - int    - will marked a specific item as 'selected'
 *                            values needs to correspond to values in col 1 of sql
 *  $strOptions    - string - HTML options to be passed to the object
 *  $strColDisplay - int    - column number of select statement to be used for displayed data in each <option> 
 *                            default: 1
 *  $strColValue   - int    - column number of select statement to be used for value of each <option>
 *                            default: 0
 *  NOTE: usually, the only time to use $strColDisplay and $strColValue is when you cannot control the column order, such 
 *        as in a SHOW COLUMNS, etc.
 */
function build_drop_down ( $strSQL, $strNamePrefix, $strSelected=NULL, $strOptions=NULL, $strColDisplay=1, $strColValue=0 ){
    if( $strSQL == NULL ){
        return "ERROR: first paramenter for build_drop_down() is required";
    }elseif( $strNamePrefix == NULL ){
        return "ERROR: second paramenter for build_drop_down() is required";
    }
    // if( $strColDisplay == NULL ){
        // $strColDisplay = 1;
    // }
    // if( $strColValue == NULL ){
        // $strColValue = 0;
    // }
    $strHTML  = "<SELECT NAME=\"$strNamePrefix\" ID=\"$strNamePrefix\" " .( isset($strOptions) ? $strOptions : '') . '>';
    if( preg_match( "/multiple/i", $strOptions ) == 0 ){
        $strHTML .= "<OPTION></OPTION>";
    }

    $arr = runQueryReturnArray( $strSQL );
    if( is_array($arr) ){
        foreach( $arr as $row ){
            $strHTML .= "<OPTION VALUE=${row[$strColValue]}";

            if( isset( $row[$strColValue] ) && $row[$strColValue] == $strSelected ) {
                $strHTML .= ' SELECTED>';
            } else {
                $strHTML .= '>';
            }

            $strHTML .= $row[$strColDisplay] . "</OPTION>";
        }
    }
    $strHTML .= "</SELECT>";

    return $strHTML;
}



/*-----------------------------------------------------
 * $html = build_check_box_scroll ( $strSQL, $strNamePrefix, $arrSelected, $strOptions, $strColDisplay, $strColValue );
 *-----------------------------------------------------
 *  Will build a list of check boxes wrapped in DIV tags, which will allow them to be displayed in a scrolling box
 *  $strSQL        - string - SQL string, where col 1 is the index to be used, and col 2 is the data to be displayed 
 *                            (see $strColDisplay, $strColValue)
 *  $strNamePrefix - string - the name of the object
 *  $arrChecked    - array  - will marked selected checkboxes as checked
 *                   values of array need to correspond to values in col 1 of sql
 *  $strOptions    - string - HTML options to be passed to the object
 *  $strColDisplay - int    - column number of select statement to be used for displayed data in each <option> 
 *                            default: 1
 *  $strColValue   - int    - column number of select statement to be used for value of each <option>
 *                            default: 0
 *  NOTE: usually, the only time to use $strColDisplay and $strColValue is when you cannot control the column order, such 
 *        as in a SHOW COLUMNS, etc.
 */
 function build_check_box_scroll ( $strSQL, $strNamePrefix='', $arrChecked=array("cappuccino"), $strOptions=NULL, $strColDisplay=1, $strColValue=0 ){
    if( $strSQL == NULL ){
        return "ERROR: first paramenter for build_drop_down() is required";
    }elseif( $strNamePrefix == NULL ){
        return "ERROR: second paramenter for build_drop_down() is required";
    }

	if( preg_match( '/height:/i', $strOptions ) > 0 ){
        $strHTML = "<DIV style='overflow:scroll;' $strOptions>";
    }else{
        $strHTML = "<DIV style='height:100pt;' style='overflow:scroll;'>";
    }

    $arr = runQueryReturnArray( $strSQL );
    if( is_array($arr) ){
        foreach( $arr as $row ){
            if( in_array($row[$strColValue], $arrChecked) ){
                $checked = 'checked';
            }
            $strHTML .= "<input type=\"checkbox\" $checked id=\"$strNamePrefix" . $row[$strColValue] . "\" name=\"$strNamePrefix" . $row[$strColValue] . "\">" . $row[$strColDisplay] . "<br>";
            $checked='';
        }
    }
    $strHTML .= "</DIV>";

    return $strHTML;
}

?>

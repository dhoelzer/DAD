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

function clean_string_xml( $strIn ) {
    $patterns[0] = "/&/";
    $patterns[1] = "/>/";
    $patterns[2] = "/</";
    $patterns[3] = "/\"/";
    $patterns[4] = "/\'/";

    $replacements[0] = "&amp;";
    $replacements[1] = "&gt;";
    $replacements[2] = "&lt;";
    $replacements[3] = "&quot;";
    $replacements[4] = "&apos;";

    $strOut = preg_replace($patterns, $replacements, $strIn);

    return $strOut;

}


function clean_string_sql( $strIn ) {
    $patterns[0] = '/\%/';
    $patterns[1] = '/\+/';
    $patterns[2] = '/\//';
    $patterns[3] = '/\?/';
    $patterns[4] = '/\#/';
    $patterns[5] = '/\&/';

    $replacements[0] = '%25';
    $replacements[1] = '%2B';
    $replacements[2] = '%2F';
    $replacements[3] = '%3F';
    $replacements[4] = '%23';
    $replacements[5] = '%26';

    $strOut = preg_replace($patterns, $replacements, $strIn);

    return $strOut;

}

/*-----------------------------------------------------
 * $arr = bitmask_to_array ( $bitmask );
 *-----------------------------------------------------
 *    will return an array of numbers in the bitmask that are 'on', to be used for looping through
 */
function bitmask_to_array( $bitmask, $arrBits ){
    $arr = array();
    $bit = 0;
    $bitmask = intval($bitmask);
    foreach( $arrBits as $bit ){
        if( $bitmask & $bit ){
            array_push( $arr, $bit );
        }
    }
    return $arr;
}



?>

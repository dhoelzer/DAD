<?php

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

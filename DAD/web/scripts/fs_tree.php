<?php


function DisplayFS() {
    global $Global;

    if( checkOptionPermission( $Global['UserID'], OPTIONID_FILE_SYSTEM ) == 0 ){
        dispatch( OPTIONID_LOGOUT );
        return;
    }

    $strHTML  = '<script language="Javascript" src="javascript/WebLIBSmartTree.js"></script>' . "\n";
    $strHTML .= '<script language="Javascript">' . "\n";
    $strHTML .= '    function initialize() {' . "\n";
    $strHTML .= '        displaySmartTree("fs_XMLGenerateTree.php?session=' . $Global['SessionID'] . '", "objSmartTree", "", true);' . "\n";
    $strHTML .= '    }' . "\n";
    $strHTML .= '</script>' . "\n";
    $strHTML .= '<body onload="initialize();">' . "\n";
    $strHTML .= '<div id="objSmartTree"></div>' . "\n";

    add_element( $strHTML );

}



?>


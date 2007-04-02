<?php

require_once "../config/OptionIDs.php";
require_once "../lib/database.php";
require_once "../lib/strings.php";
require "../lib/globalizer.php";

global $Global;

$Global['SessionID'] = $_GET['session'];                 //have to use $_GET since this was not loaded through index.php, nor are we going to mimic all that stuff; this file needs to be fast since it is feeding user's clicks....
//validateSessionID( $Global['SessionID'] );
//PopulateUserGlobals( $Global['SessionID'] );
//Global


if ( $_REQUEST['strParentKey']=="" ) { 

    $sql  = "SELECT id_dad_fs_path, parent_id, name FROM DAD.dad_fs_path WHERE depth=0 AND activeyesno=1 ORDER BY name";
    $rows = runQueryReturnArray( $sql );

} else {

    $parent = $_REQUEST['strParentKey'];
    $sql = "SELECT id_dad_fs_path, parent_id, name FROM DAD.dad_fs_path WHERE parent_id=$parent AND activeyesno=1 ORDER BY name";

    $rows = runQueryReturnArray($sql);

}

print "<?xml version=\"1.0\" ?><nodes>";

foreach( $rows as $row ) {

    $parent_id = $row['parent_id'];
    $name      = clean_string_xml( $row['name'] );
    $key       = $row['id_dad_fs_path'];

    $xml .= "<node>\n";
    $xml .= "<parent>$parent_id</parent>\n";
    $xml .= "<key>$key</key>\n";
    $xml .= "<text>$name</text>\n";
    $xml .= "<tip>$name</tip>\n";
    $xml .= "<url><![CDATA[javascript:window.open( 'index.php?option=" . (OPTIONID_FS_DETAIL_SHOW) . "&folder=$key&session=". ($Global['SessionID']) . "&compact=1', '', 'height=420,width=600,status=yes,toolbar=no,menubar=no,location=no,scrollbars=yes,resizable=yes');window.back]]></url>";
    $xml .= "<script></script>\n";
    $xml .= "<frame></frame>\n";
    $xml .= "<collapsed>_CLOSEDFOLDER</collapsed>\n";
    $xml .= "<expanded>_OPENFOLDER</expanded>\n";
    $xml .= "<leaf>_DOCUMENT</leaf>\n";
    $xml .= "<children>1</children>\n";
    $xml .= "</node>\n";

} 

$xml .= "</nodes>";

print $xml;


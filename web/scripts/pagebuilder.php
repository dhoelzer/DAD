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
/*-----------------------------------------------------------------------------
 * Pagebuilder - 6/21/05
 *
 * This script file contains all of the
 * functions to build a page.
 *-----------------------------------------------------------------------------
 */

// This is temporary!
require_once "../lib/globalizer.php";
require_once "../lib/html_formatter.php";
/*-----------------------------------------------------------------------------
 * Module Globals:
 * ---------------
 * The pagebuilder module uses three globals to track page contents:
 * page_header, page_body, page_footer and added_elements.  They should
 * not be modified directly.
 *
 */
global $gbTrusted;
$gbTrustContents = true;
add_global("page_header", "", $gbTrustContents);
add_global("page_body", "", $gbTrustContents);
add_global("page_footer", "", $gbTrustContents);
add_global("added_elements", "", $gbTrustContents);

/*
 * Popup($Output)
 */
function Popup($Title, $Contents,$Width=640, $Height=480, $Top=5, $Left=5)
{
	$Contents = preg_replace("/^\s+$/sm","",$Contents);
	$Contents = preg_replace("/[\n]+/","<br>",$Contents);
	$Contents = preg_replace("/[\\x00]/", ":", $Contents);
	$Contents = preg_replace("/\\\\/", "/", $Contents);
	$Contents = preg_replace("/[^a-zA-Z0-9\\\. \%&;\-=\/<>:$]/", "", $Contents);
	$Window_Name = preg_replace("/[^a-zA-Z]/","_", $Title);
	$output = <<<END
		<script language="javascript">  
		<!--  
		$Window_Name = window.open("", "$Window_Name", "top=$Top,left=$Left,width=$Width,height=$Height,scrollbars=1,menubar=1,location=0,status=0,resizable=1");
		$Window_Name.document.write("<html><head><title>$Title</title></head><body><font size=-1>$Contents</font></body></html>");
		// --> 
		</script>
END;
	add_element($output);
}

/*-----------------------------------------------------------------------------
 * showpage()
 *-----------------------------------------------------------------------------
 * This function takes the current page and paints it to the browser.  This
 * function will also use the $Global array to identify where in the web app
 * the user is so that the appropriate headers and footers can be generated
 * with the correct menu and tab options on the page.  Show page also grabs
 * all of the menu and tab information out of the database and arranges to
 * have it painted.
 *
 */
function showpage() {

  global $Global;
  global $gbTrustContents;
  
  $UserIDForQuery = empty($Global["UserID"]) ? 0 : $Global["UserID"];
  
  $strSQL = "SELECT DISTINCT 
                   mo.MenuOptionID,
                   mo.OptionName,
                   mo.SequenceNum OptionSequenceNum,
                   m.MenuID,
                   m.ParentMenuOptionID,
                   m.LevelNum,
                   m.SequenceNum MenuSequenceNum,
                   m.MenuName,
                   mo.ContentPathName,
                   0 SelectedFlag
              FROM userrole ur
              JOIN rolemenuoption rmo ON rmo.RoleID = ur.RoleID
              JOIN menuoption mo ON mo.MenuOptionID = rmo.MenuOptionID
              JOIN menu m ON m.MenuID = mo.MenuID
             WHERE ur.UserID = $UserIDForQuery
          ORDER BY m.ParentMenuOptionID, m.LevelNum, m.SequenceNum, mo.SequenceNum";

   $aOptions = runQueryReturnArray($strSQL, KEY_COLUMN1);
   add_global("CurrentTab", GetCurrentTab($aOptions), $gbTrustContents);
   add_global("CurrentTabID", GetCurrentTabID($aOptions), $gbTrustContents);
   add_global("TabList", getTabList($aOptions), $gbTrustContents);
   add_global("CurrentMenu", GetCurrentMenu($aOptions), $gbTrustContents);
   $strSectionMenuList = getTabMenuOptionRow($aOptions, 1);
   $LanguageCode = $Global['LanguageCode'];
   $Expiration = time() + 360000;
   if (headers_sent($filename, $linenum))
   {
     logger("ERROR: Headers sent from $filename on line $linenum");
   }
   if($Global['ValidSession'])
   {
      set_cookie("Language", $LanguageCode, $Expiration);
	if(isset($Global["SessionID"]))
	{
		setcookie("SessionID", $Global["SessionID"]);
	}
   }
   print _header();
   print _body();
   print _footer();
}

function GetCurrentTab($Options)
{
   global $Global;
   $ParentOption = (int)$Options[(int)$Global["OptionID"]]["ParentMenuOptionID"];
   if($ParentOption == 0) { $ParentOption = (int)$Global["OptionID"]; }
   return($Options[$ParentOption]["OptionName"]);

}

function GetCurrentTabID($Options)
{
   global $Global;
   $ParentOption = (int)$Options[(int)$Global["OptionID"]]["ParentMenuOptionID"];
   if($ParentOption == 0) { $ParentOption = (int)$Global["OptionID"]; }
   return($ParentOption);

}

/*-----------------------------------------------------------------------------
 * string build_table(assoc[,width[,cellpadding[,cellspacing[,border[,bgcolor[,bgcolor2]]]]]])
 *-----------------------------------------------------------------------------
 * This function takes an associative array as an argument and returns
 * a table where the keys in the array are the column headers and the
 * body of the table contains the values for the respective columns.
 * The return value of this function is the string form of the table itself
 * that can be added to the page using add_element().  The associative array
 * should have keys that point to values that are arrays in order to get
 * anything more than a two row table.
 *
 */
function build_table($assocTableData, $width="100%", $cellpadding="5", $cellspacing="5", $border="3", $background="#ffffff", $background2="undefined")
{
   if($background2=="undefined")
      {
         $background2 = $background;
      }
   $table = "<table WIDTH='$width' CELLPADDING='$cellpadding' CELLSPACING='$cellspacing' BORDER='$border'><tr>";
   $headers = array_keys($assocTableData);
   foreach($headers as $header)
      {
         $table .= "<th>$header</th>";
      }
   $elements = count($assocTableData[$header]);
   for($i = 0; $i != $elements; $i++)
      {
         $table .= "<tr BGCOLOR='" . ($i % 2 ? $background2 : $background) . "'>";
         foreach($headers as $key)
            {
				if(is_string($assocTableData[$key][$i]))
				{
				  $table .= "<td>".$assocTableData[$key]."</td>";
				}
				else
				{
                  $table .= "<td>".$assocTableData[$key][$i]."</td>";
				}
            }
         $table .= "</TR>";
      }
   $table .= "</TABLE>\n";
   return $table;
}

/*-----------------------------------------------------------------------------
 * string build_table_from_query(assoc[,width[,cellpadding[,cellspacing[,border[,bgcolor[,bgcolor2]]]]]])
 *-----------------------------------------------------------------------------
 * This function takes an associative array as an argument and returns
 * a table where the keys in the array are the column headers and the
 * body of the table contains the values for the respective columns.
 * The return value of this function is the string form of the table itself
 * that can be added to the page using add_element().  The associative array
 * should have keys that point to values that are arrays in order to get
 * anything more than a two row table.
 *
 */
function build_table_from_query($Result, $width="100%", $cellpadding="5", $cellspacing="5", $border="3", $background="#ffffff", $background2="undefined", $TableClass="default", $Start=1)
{
global $Global;

	// This URL is to handle context based results
    $strURL  = getOptionURL(OPTIONID_EXISTING_QUERIES);


   if($background2=="undefined")
      {
         $background2 = $background;
      }
   $table = "<table class='$TableClass' width='$width' cellpadding='$cellpadding' cellspacing='$cellspacing' border='$border'><tr>";
if(!count($Result)) 
{ 
	$table .= "<td><h3>No results found</h3></td></tr>";
	$table .= "</table>";
    return $table;
 }
   $headers = $Global["LAST_QUERY_FIELD_NAMES"];
   foreach($headers as $header)
      {
         $table .= "<th>$header</th>";
      }
	$table .= "</tr>";
$i = 0;
   foreach($Result as $row)
      {
        $table .= "<tr bgcolor='" . ($i++ % 2 ? $background2 : $background) . "'>";
		if(!count($row)) 
		{ 
			$table .= "<tr><td><h3>No results found</h3></td></tr>";
			$table .= "</table>\n";
			return $table;
		}
#		foreach($row as $value)
#		{
#			$table .= "<td>$value</td>";
#		}
         foreach($headers as $key)
            {
			  $table .= "<td><font size=-1>";
			  $words = split(" ", $row[$key]);
			  $position = 0;
			  if ($key != "Time") 
			  {
				foreach($words as $word)
				  {
					$table .= "<a title='Field $position' href='$strURL&ContextQuery=$word&Start=".($Start-10)."'>$word </a>";
					$position++;
				  }
				}
				if($key == "Time")
				{
					$table .= "<a title='EST:\nGMT:\nHKST:'>$row[$key]</a>";
				}
			  $table .= "</font></td>";
            }
         $table .= "</tr>";
      }
   $table .= "</table>";
   return $table;
}

/*-----------------------------------------------------------------------------
 * set_cookie(string name [, string value [, int expire [, string path [, string domain [, int secure]]]]])
 *-----------------------------------------------------------------------------
 * Allows the programmer to set a cookie for the page to be sent.  Everything after the
 * name is optional.  Sending only a name will try to delete the named cookie from the client.
 *
 */
function set_cookie($strCookieName, $strCookieValue=0, $intCookieExpires=0, $strCookiePath="/", $strCookieDomain="", $intCookieSSL=0)
{
   global $_SERVER;
   if(!isset($strCookieDomain) || $strCookieDomain == "")
   {
     $strCookieDomain = $_SERVER["SERVER_NAME"];
   }
   if(!setcookie($strCookieName, $strCookieValue, $intCookieExpires, $strCookiePath, $strCookieDomain, $intCookieSSL))
   {
     logger("INFO: Set cookie failed. Did output already begin?");
   }
}

/*-----------------------------------------------------------------------------
 * add_element(string html)
 *-----------------------------------------------------------------------------
 * Add_element is used to add raw HTML elements directly to the page that will
 * be painted.  This is perfect for painting a form or a table that has been
 * generated elsewhere in the code.
 *
 */
function add_element($strStuffToAdd)
{
   global $Global;
   global $gbTrustContents;
   $_added_elements = $Global["added_elements"];
   $_added_elements .= $strStuffToAdd;
   modify_global("added_elements", $_added_elements, $gbTrustContents);
}

/*-----------------------------------------------------------------------------
 * _header()
 *-----------------------------------------------------------------------------
 * The _header function produces the header that should be printed on every
 * web page.  This function should only be called from showpage().
 *
 */
function _header()
{
   global $gaLiterals;
   global $gbTrustContents;
   global $Global;
   
   $_header = "<!DOCTYPE HTML PUBLIC \"-//W3C//DTD XHTML 1.0 Transitional//EN\" \"http://www.w3c.org/TR//xhtml1/DTD/xhtml1-transitional.dtd\">\n";
   $_header .= "<html xmlns=\"http://www.w3.org/1999/xhtml\">\n";
   $_header .= "<head>\n";
   $_header .= "<title>". $gaLiterals['DAD']. "</title>\n";
   $_header .= "<meta http-equiv=\"Content-Type\" content=\"text/html; charset=utf-8\" />\n";
   $_header .= "<link rel=\"stylesheet\" type=\"text/css\" href=\"css/DAD.css\" />\n";
   $_header .= "</head>\n";
   modify_global("page_header", $_header, $gbTrustContents);
   return $Global["page_header"];
}

/*-----------------------------------------------------------------------------
 * _body()
 *-----------------------------------------------------------------------------
 * The _body function should not be called externally.  This function builds the actual
 * body of the page and paints in items added with add_element.  This function
 * should only be called from showpage().
 * If URL option compact=1 is passed, will not show left menu or tabs.
 *
 */
function _body()
{
   global $Global;
   
   global $gaLiterals;
   global $gbTrustContents;
   global $strCurrentTabName;
   global $strHelpURL;

   $strHelpURL = getOptionURL(OPTIONID_HELP);
   if( !isset($Global['compact']) ){
       $Global['compact'] = '';
   }


   $_html_body = $Global["page_body"];

   //if URL query contains compact=1 will only have one column on page instead of two
   if( $Global['compact'] != 1 ){
       $intNumberOfColumns = ($Global["NumberOfMenuItems"] > 0 ? 2 : 1);
   } else {
       $intNumberOfColumns = 1;
   }

   $_html_body .= "<body class=\"cols-$intNumberOfColumns\">\n";
   $_html_body .= "<div id=\"header\">\n";
   $_html_body .= "<h1 id=\"sitename\"><span class=\"sitename-sm\">" . $gaLiterals['DADLine1'] . " <img align=right src='images/UStatus.gif'></span><br />\n";
   $_html_body .= $gaLiterals['DADLine2'] . "</h1>\n";
   $_html_body .= "<ul id=\"sitelinks\">\n";
   $_html_body .= "<li><a href=\"". $strHelpURL . "\">" . $gaLiterals['Help'] . "</a></li>\n";
   $strLogoutURL = getOptionURL(OPTIONID_LOGOUT);
   $_html_body .= "<li><a href=\"" . $strLogoutURL . "\">" . $gaLiterals['Log Out'] ."</a></li>\n";
   $_html_body .= "</ul>\n";

   $_html_body .= "<div id=\"sitemenu\">\n";
   //if URL query contains compact=1, will not show tabs or left side menu
   if( $Global['compact'] != 1 ){
       //display individual tabs according to credentials
       if($Global["OptionID"] == OPTIONID_LOGINPAGE || $Global["OptionID"] == OPTIONID_LOGINUSER)
       {
         // No tab list
       } else {   
          $_html_body .= $Global["TabList"];  
       }
   }

   $_html_body .= "</div>\n";
   $_html_body .= "</div>\n";
   $_html_body .= "<div id=\"sectionname\">\n";

   //if URL query contains compact=1, will not show tabs or left side menu
   if( $Global['compact'] != 1 ){
       $_html_body .= "<h1>" . $Global["CurrentTab"] . "</h1>\n";
   }

   $_html_body .= "</div>\n";
   $_html_body .= "<div id=\"sectionmenu\">\n";

   //if URL query contains compact=1, will not show tabs or left side menu
   if( $Global['compact'] != 1 ){
       //display menu according to credentials
       $_html_body .= $Global["CurrentMenu"];
   }

   $_html_body .= "</div>\n";
   //if URL query contains compact=1, will not show tabs or left side menu
   if( $Global['compact'] != 1 ){
       $_html_body .= "<div id=\"content\">\n";
   } else {
       //force a different margin on CONTENT DIV tag... I can't quite get another CSS option to work
       $_html_body .= "<div id=\"content\"  style=\"margin-left: 12px;\">\n";
   }

   $_html_body .= $Global["added_elements"];
   //if($aMenuOptions[$intCurrentOptionID]['ContentPathName']) {
   //include $aMenuOptions[$intCurrentOptionID]['ContentPathName'];
   //   }

   $_html_body .= "</div>\n";
   modify_global("page_body", $_html_body, $gbTrustContents);
   return $Global["page_body"];
}

/*-----------------------------------------------------------------------------
 * _footer()
 *-----------------------------------------------------------------------------
 * The footer function is an internal function and should not be called directly.
 * This function produces a standard footer that should be printed at the bottom of
 * every web page.  This function should only be called by showpage().
 *
 */
function _footer()
{
   global $Global;
   global $gbTrustContents;
   
   modify_global("page_footer", "</body></html>", $gbTrustContents);
   return $Global["page_footer"];
}

// These functions added from Saul's code
/*------------------------------------------------------------------------------
 * GetCurrentMenu($MenuOptions)
 *------------------------------------------------------------------------------ 
 * Returns string of an html unordered list containing non tab level menuoptions
 * for the selected option. So this function could be called from any html page.
 * Untested but should go down all levels for selected tab.  This function
 * assumes that $Global["CurrentTab"] has been set.
 * Assumes $aMenuOptions is sorted as follows:
 *    m.ParentMenuOptionID, m.LevelNum, m.SequenceNum, mo.SequenceNum
 *
 */
function GetCurrentMenu(&$aMenuOptions) {  

   global $Global;
   global $gbTrustContents;
   
   $blnFirstMenuName = true;
   $intMenuItems = 0;
   $strLastMenuName = '';
   $strMenuList = '';

   if($aMenuOptions){
	foreach($aMenuOptions as $aOption) {
      if ($aOption['LevelNum'] <= 1 || (int)$aOption['ParentMenuOptionID'] != (int)$Global["CurrentTabID"] || (int)$aOption["OptionSequenceNum"] == 0) {
         continue;
      }
      if ($aOption["MenuName"] != $strLastMenuName) {
         // If new menu, close the last one first
         if (! $blnFirstMenuName) {
            $strMenuList .= "</ul>\n";
         }
         $blnFirstMenuName = false;
         $strMenuList .= "<p class=\"h1\">" . getLit($aOption["MenuName"]) . "</p>\n";
         $strMenuList .= "<ul>\n";
         $intMenuItems++;
      }
      $strMenuList .= "<li><a href=\"" . getOptionURL($aOption['MenuOptionID']) . "\">". getLit($aOption["OptionName"]) . "</a></li>\n";
      $strLastMenuName = $aOption["MenuName"];
	  }
	}
   if ($intMenuItems > 0) {
      $strMenuList .= "</ul>\n";
   }
   add_global("NumberOfMenuItems", $intMenuItems, $gbTrustContents);
   return $strMenuList;
}


/*------------------------------------------------------------------------------
 * getTabList(&$MenuOptions)
 *------------------------------------------------------------------------------
 *  Returns string of an html unordered list containing tab menuoptions. 
 *
 */
function getTabList(&$aMenuOptions) {

   global $Global;
   $strTab = '<ul>';
   
   // This array is passed around by reference ...
   if(!is_array($aMenuOptions))
   {
     return("");
   }
   reset($aMenuOptions);
   foreach($aMenuOptions as $rTab) {
      if ($rTab["LevelNum"] == 1) {
         $strClass = ($rTab["MenuOptionID"] == $Global["CurrentTabID"]) ? ' class="selectedtab"' : "";
         $strTab .= "<li$strClass>";
         $strTab .= '<a href="' . getOptionURL($rTab['MenuOptionID']) . '">' . getLit($rTab["OptionName"]) . '</a>';
         $strTab .= '</li>';
      }
   }
   $strTab .= '</ul>';
   return $strTab;
}

/*------------------------------------------------------------------------------
 * string getTabMenuOptionRow($MenuOptions, $CurrentOptionID)
 *------------------------------------------------------------------------------
 * Returns MenuOption row of the select tab. Should work even if selected
 * $intCurrentOptionID is more than 1 level down.
 */
function getTabMenuOptionRow(&$aMenuOptions, $intCurrentOptionID) {
   while(isset($aMenuOptions[$intCurrentOptionID]['LevelNum'])) {
      if($aMenuOptions[$intCurrentOptionID]['LevelNum'] == 1) {
         return $aMenuOptions[$intCurrentOptionID];
      }
       $intCurrentOptionID=$aMenuOptions[$intCurrentOptionID]['ParentMenuOptionID'];
   }
   return NULL;
}

/*------------------------------------------------------------------------------
 * string getOptionURL($Option)
 *------------------------------------------------------------------------------
 * This function will generate a URL including the correct option and the
 * session token, returning it as a string.
 */
function getOptionURL($strOption) {
   global $Global;

	return ("index.html?".ARG_OPTION."=$strOption");
}

?>

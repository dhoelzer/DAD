<?php
/*------------------------------------------------------------------------
 * Language Preferences Module 6/27/05
 *
 * This module implements the forms necessary to set up a language
 * preference for a user.
 *------------------------------------------------------------------------
 */
 
function showLanguagePrefs()
{
  global $Global;
  $sql = "SELECT LanguageID,LanguageCode,LanguageName FROM
            DAD.Language";
  $aResults = runQueryReturnArray($sql);
  $strOptionList = "<select name='LanguagePref'>";
  foreach($aResults as $row)
  {
    $LanguageID = $row['LanguageID'];
    $LanguageName = $row['LanguageName'];
    $LanguageCode = $row['LanguageCode'];
    $Selected = "";
    if($LanguageCode == $Global['LanguageCode'])
    {
      $Selected = "selected";
    }
    $strOptionList .= "<option $Selected value=$LanguageID>$LanguageName</option>";
  }
  $strOptionList .= "</select>";
  $URL = getOptionURL(OPTIONID_LANGPREFSUBMIT);
  $HTML = "<form name='LanguagePrefForm' action='$URL' method='post' style='position:relative; top:25px;'>".
    "$strOptionList <input type=submit name=btnSubmit value='Select Language'></form>";
  add_element($HTML);
}

function setLanguagePrefs()
{
  global $Global;
  
  $SubmittedLanguagePref = (isset($Global['LanguagePref']) ? $Global['LanguagePref'] : 1);
  $sql = "SELECT LanguageID,LanguageCode,LanguageName FROM
            DAD.Language WHERE LanguageID='$SubmittedLanguagePref'";
  $aResults = runQueryReturnArray($sql);
  $LanguageName = $aResults[0]['LanguageName'];
  $LanguageID = $aResults[0]['LanguageID'];
  $LanguageCode = $aResults[0]['LanguageCode'];
  $UserID = (isset($Global['UserID']) ? $Global['UserID'] : 0);
  if(!$UserID)
  {
    logger("CRITICAL ERROR:  Called set language prefs with no user ID set!");
   add_element(getLit("Unable to change language preference at this time."));
    return;
  }
  add_global("LanguageCode", $aResults[0]["LanguageCode"]);
  add_global("LanguageName", $aResults[0]["LanguageName"]);
  getAllLiteralsForUserLang();
  $sql = "UPDATE DAD.User SET LanguageID='$LanguageID' WHERE UserID='$UserID'";
  $result = runSQLReturnAffected($sql);
  if($result)
  {
    add_element(getLit("Language preference changed successfully!"));
    return;
  }
  add_element(getLit("Unable to change language preference at this time."));
}

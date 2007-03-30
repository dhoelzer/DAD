<?php
/* 
 * Language.php
 *
*/ 


getAllLiteralsForUserLang();

function getAllLiteralsForUserLang() {
   global $Global;

   $strLanguageCode = (isset($Global["LanguageCode"]) ? $Global["LanguageCode"] : "E");
   IncludeCorrectTranslations();
}

function getLit($strText) {
   global $gaLiterals;
   if (isset($gaLiterals[$strText])) {
      return $gaLiterals[$strText];
   } else {
      return "No translation found";
   }
}
function TraverseAndInclude($Directory)
{
  global $Global;
  $dh = opendir($Directory);
  while (false !== ($file = readdir($dh)))
  { 
    if ($file != "." && $file != "..") 
	{
      if(is_dir("$Directory/$file"))
	  { 
	    $LanguageCode = (isset($Global["LanguageCode"]) ? $Global["LanguageCode"] : "E");
		if($file == $LanguageCode)
		{
		  IncludeFilesHere("$Directory/$file");
		}
		else
		{
		  TraverseAndInclude("$Directory/$file");
		}
      }		
    }
  }
  closedir($dh); 
}

function IncludeFilesHere($Directory)
{
  global $gaLiterals;
  
  foreach(glob("$Directory/*.php") as $filename)
  {
	require($filename);
  }
}

function IncludeCorrectTranslations()
{
  $StartingPoint = "../scripts";
  TraverseAndInclude($StartingPoint);
}



?>
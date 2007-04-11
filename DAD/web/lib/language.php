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

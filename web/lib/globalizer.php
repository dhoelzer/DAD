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
/*---------------------------------------------------------------------
 * Globalizer - 6/21/2005
 *
 * Builds a set of safe global values stored in an associative array.
 * As items are added into the global array, they are sanitized for a
 * to remove characters based on a filter set defined in the database
 * entry for the language set.  If a language set is not defined, a
 * predefined (ASCII) set is used to do a base filter (which will badly break
 * any foreign character sets that are used for entry).
 *---------------------------------------------------------------------
 */
require_once("../lib/logging.php");
global $Global;
global $strRegexFilter;
set_globalizer_filter("a-zA-Z0-9 .\\");

/*---------------------------------------------------------------------
 * PrintMapping
 *---------------------------------------------------------------------
 * This debug function allows you to place the contents of any
 * array, associative or indexed, into the output stream as a set
 * of unordered nested lists.  The array may contain other arrays
 * and these sub-arrays will be nested under the proper elements.
 */
function PrintMapping($array)
{
   add_element("<ul>");
   foreach($array as $key => $value)
   {
     if(!is_array($value)) { add_element("<li>array[$key] => $value</li>"); }
	 else
	 {
	   add_element("<li>array[$key] =>");
	   PrintMapping($value);
	   add_element("</li>");
     }
   }
   add_element("</ul>");
}

/*---------------------------------------------------------------------
 * print_backtrace()
 *---------------------------------------------------------------------
 * This is a debug function that allows you to print out the current
 * call tree for the function that you call this from and a table of
 * all of the global variables.
 */
function print_backtrace()
{
	     $t = debug_backtrace();
		 $trace = "Function Backtrace: ";
		 foreach($t as $step)
		 { $trace .= "->".$step["function"]; }
         add_element($trace."<br>");
		 add_element(PrintGlobal());
}

/*---------------------------------------------------------------------
 * PrintGlobal()
 *---------------------------------------------------------------------
 * This function will add a table to the output page that displays
 * all of the values stored in the $Global array in a table.
 */
function PrintGlobal()
{
global $Global;
  //Debug code only
  PrintMapping($Global);
   //End debug
}
/*---------------------------------------------------------------------
 * string sanitize(string string_to_filter, [string permitted_specials])
 *---------------------------------------------------------------------
 * The sanitize function takes an arbitrary length string (string_to_filter)
 * and returns a sanitized version of the string, dropping out all characters
 * not defined using set_globalizer_filter().  An optional string listing
 * special characters that should be permitted for a single call can be
 * included.  This will allow you to permit additional characters that would
 * normally be filtered (eg, when specifying a password).
 *
 */
function sanitize($strFilterMe, $strSpecials="")
{
   // This function really needs some validation to make sure that the
   // specials sent are quoted properly. -DSH, 6/05
   global $strRegexFilter;
  $LocalFilter =  $strRegexFilter . "$strSpecials]/";
   return(preg_replace($LocalFilter, "", $strFilterMe));
}

/*---------------------------------------------------------------------
 * set_globalizer_filter(string filter_expression)
 *---------------------------------------------------------------------
 * The set_globalizer_filter function allows you to set the string that will be
 * used as the regular expression filter for the sanitize function.  The string
 * must be a regular expression set.  Expect that whatever you send will be placed
 * between square brackets.  (eg, set_globalizer_filter("a-zA-Z") will result in
 * a filter of "[a-zA-Z]")
 *
 */
function set_globalizer_filter($strNewFilter)
{
   global $strRegexFilter;
   $strRegexFilter="/[$strNewFilter";
}

/*---------------------------------------------------------------------
 * assoc add_global(assoc var_to_add)
 * assoc add_global(string var_name_to_add, string value_to_add)
 *---------------------------------------------------------------------
 * The add_global function allows you to add a value to the global associative
 * array that is used to track global variables.  The function takes at least one
 * argument, var_to_add, which is the name of an associative array containing a list
 * of names and values to add.  (eg, add_global($_REMOTE);)
 *
 * add_global may also be used to create a new global variable on the fly by sending
 * a string value to represent the name of the global to create and a string value
 * to associate with it (eg, add_global("username", "sam");).
 *
 * Either way, the function will return an associative array containing the global
 * variables.  You do not have to take this copy since the global array remains
 * a separate copy, but you should NEVER make changes to this copy that you need
 * to keep since they will not affect the global array.  Instead, please use
 * modify_global().
 */
function add_global($mixedVarToAdd, $strValueToAdd="")
{
   global $Global;

   if(is_array($mixedVarToAdd))
      {
         foreach($mixedVarToAdd as $Key => $Value)
            {
               $Global[$Key] = $Value;
            }
         return $Global;
      }
   if(is_string($mixedVarToAdd))
      {
	     if(is_bool($strValueToAdd))
		 {
		   $strValueToAdd = ($strValueToAdd ? "1":"0");
		 }
         $Global[$mixedVarToAdd] = $strValueToAdd;
         return $Global;
      }

   add_element("Something's wrong... $mixedVarToAdd isn't a string or an array in globalizer.");
   showpage();
   exit();
}
               
/*---------------------------------------------------------------------
 * assoc modify_global(string var_name, string new_value)
 *---------------------------------------------------------------------
 * The modify_global function allows you to change the value of a variable stored
 * in the global associative array.  This function must be used to make changes to
 * the global array since the return value of this and add_global are merely copies
 * of the actual array.
 *
 */
function modify_global($strKey, $strValue)
{
   global $Global;
   if(is_bool($strValue))
   {
     $strValue = ($strValue ? "1":"0");
   }
   $Global[$strKey] = (string)$strValue;
   return $Global;
}
?>
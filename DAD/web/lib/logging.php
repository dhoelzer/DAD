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
 * Logging Library
 *-----------------------------------------------------------------------------
 * The logging library allows a PHP web application to create log entries
 * in a standard format that are sent out as comma delimited text to syslog.
 * Syslog is being used rather than a database insert because it is not only
 * faster, but the logs themselves will very rarely be looked at.  When there
 * is a desire to analyze the logs, they can be easily imported into Excel
 * or even a databse to perform queries.
 *
 * The logging library also handles error reporting and contains the
 * custom error handler.
 *
 * All library level logging functions should reside in this file.
 * DSH - 6/24/05
 */
 
//error_reporting( E_NOTICE | E_WARNING | E_CORE_WARNING | E_USER_ERROR | E_USER_WARNING);
//error_reporting( E_USER_ERROR );
//set_error_handler("error_handler");
 
 function error_handler($Error, $ErrorText, $ErrorFile, $ErrorLine, $SymbolTable)
 {
   logger("ERROR: #$Error - $ErrorText occured in $ErrorFile on line $ErrorLine  ");
 }
 
/*-----------------------------------------------------------------------------
 * void logger($custom_error_message)
 *-----------------------------------------------------------------------------
 * The log function will automatically generate a log entry that reflects the
 * current user, session ID, function that the log message was generated from,
 * a timestamp, the current menu option ID and any custom message that the
 * calling function wishes to include. NEVER put a call to log within the
 * log function unless you want very bad things to happen.
 *
 * The format of the messages logged is as follows:
 * Using the LOG_INFO syslog priority, the fields are in this order:
 *		A marker field "DAD_WEBAPP:"
 *		Timestamp in seconds
 *		Call tree/Execution path
 *		Current option ID
 *		Current User ID
 *		Current Username
 *		Current Session ID
 *		Arbitrary message created by function calling logger
 */
function Logger($message)
{
  global $Global;
  
  //First we grab the backtrace
  $backtrace = debug_backtrace();
  $CallingFunction = "CallPath";
  $NumCalls = count($backtrace);
  for($i = $NumCalls - 1;  $i != 0; $i --)
  {
    $CallingFunction .= "=>".$backtrace[$i]["function"];
  }
  if($NumCalls <= 1)
  {
    $CallingFunction .= "=>(Not called from within a function)";
  }
  $CurrentUserID = (isset($Global["UserID"]) ? $Global["UserID"] : 0);
  $CurrentUser = (isset($Global["txtUserName"]) ? $Global["txtUserName"] : "Not logged in");
  $CurrentOptionID = (isset($Global["OptionID"]) ? $Global["OptionID"] : "No Option ID");
  $CurrentSessionID = (isset($Global["SessionID"]) ? $Global["SessionID"] : "No valid session");
  $CurrentTime = time();
  add_element("DAD_WEBAPP:$CurrentTime,$CallingFunction,$CurrentOptionID,$CurrentUserID,$CurrentUser,$CurrentSessionID,$message");
  syslog(LOG_INFO, "DAD_WEBAPP:$CurrentTime,$CallingFunction,$CurrentOptionID,$CurrentUserID,$CurrentUser,$CurrentSessionID,$message");
}
?>

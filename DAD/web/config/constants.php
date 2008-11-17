<?php 
#   Constants definitions for DAD Log Analysis Suite
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

// ERRORS
// System wide settings
define('ERR_NOTICES', true); // ignore notices
define('ERR_SCREEN_ERRORS', true); // do print
//define('ERR_LOG_ERRORS', true);

define('D_LOG', '../');

/* 
   These used tags in you calls to trigger_error($strMessage) calls by prepending 
   any combination of tags to the $strMessage parameter.
   ie. trigger_error(ERR_NOSCREEN_TAG.ERR_SYSTEM_LOG.'your message');
 */
define('ERR_NOSCREEN_TAG', ':NOSCREEN_TAG:'); //don't print to screen
define('ERR_NOBACKTRACE_TAG', ':NOBACKTRACE_TAG:');
define('ERR_SYSTEM_LOG', "system/system.@date.log");
define('ERR_SECURITY_LOG', "security/security.@date.log");
define('ERR_SERVICE_LOG', "service/service.@date.log");
//define('ERR_TEST_LOG', "test/test.@date.log");
//define('ERR_BLAH_LOG', "blah/blah.@date.log");

// PAGES
define('D_PAGE_ROOT', 'pages/');
define('PAGE_MAIN', 'main');

// SESSIONS
define('SESSION_DURATION', 9000);

// SYSTEM
define('DEBUG_MODE', true);

// URL
define('ARG_OPTION', 'option');
define('ARG_SESSION', 'session');
define('ARG_USERINFO', 'user');

// Please keep these sorted alphabetically!

define('RETURN_SUCCESS', 0);
define('RETURN_FAILURE', -1);
define('RETURN_LOGIN', -2);
define('MYSQL_DRIVE', "/");
//define('MYSQL_BOTH', 1);
//define('MYSQL_ASSOC', 2);


?>

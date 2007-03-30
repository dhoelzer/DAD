<?php 

// ERRORS
// System wide settings
define('ERR_NOTICES', true); // ignore notices
define('ERR_SCREEN_ERRORS', true); // do print
//define('ERR_LOG_ERRORS', true);

define('D_LOG', '/var/www/log/');

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


?>
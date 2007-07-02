-- MySQL dump 10.11
--
-- Host: 127.0.0.1    Database: dad
-- ------------------------------------------------------
-- Server version	5.0.37-community-nt

/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8 */;
/*!40103 SET @OLD_TIME_ZONE=@@TIME_ZONE */;
/*!40103 SET TIME_ZONE='+00:00' */;
/*!40014 SET @OLD_UNIQUE_CHECKS=@@UNIQUE_CHECKS, UNIQUE_CHECKS=0 */;
/*!40014 SET @OLD_FOREIGN_KEY_CHECKS=@@FOREIGN_KEY_CHECKS, FOREIGN_KEY_CHECKS=0 */;
/*!40101 SET @OLD_SQL_MODE=@@SQL_MODE, SQL_MODE='NO_AUTO_VALUE_ON_ZERO' */;
/*!40111 SET @OLD_SQL_NOTES=@@SQL_NOTES, SQL_NOTES=0 */;

--
-- Table structure for table `dad_adm_job`
--

DROP TABLE IF EXISTS `dad_adm_job`;
CREATE TABLE `dad_adm_job` (
  `id_dad_adm_job` int(10) unsigned NOT NULL auto_increment,
  `descrip` varchar(256) default NULL,
  `length` int(10) unsigned default NULL,
  `job_type` varchar(15) default NULL,
  `path` varchar(2048) default NULL,
  `package_name` varchar(100) default NULL,
  `calleractive` varchar(45) default NULL,
  `next_start` int(10) unsigned default NULL,
  `user_name` varchar(45) default NULL,
  `distinguishedname` varchar(256) default NULL,
  `pword` varchar(100) default NULL,
  `times_to_run` int(10) unsigned default NULL,
  `times_ran` smallint(6) unsigned default NULL,
  `start_date` date default NULL,
  `start_time` time default NULL,
  `last_ran` int(10) unsigned default NULL,
  `min` int(10) unsigned default NULL,
  `hour` int(10) unsigned default NULL,
  `day` int(10) unsigned default NULL,
  `month` int(10) unsigned default NULL,
  `is_running` tinyint(1) NOT NULL default '0',
  `persistent` tinyint(1) NOT NULL default '0',
  PRIMARY KEY  (`id_dad_adm_job`)
) ENGINE=MyISAM AUTO_INCREMENT=12 DEFAULT CHARSET=latin1;

--
-- Dumping data for table `dad_adm_job`
--

LOCK TABLES `dad_adm_job` WRITE;
/*!40000 ALTER TABLE `dad_adm_job` DISABLE KEYS */;
INSERT INTO `dad_adm_job` VALUES (1,'Generate Statistics',NULL,'DAD Internals','C:\\\\dad\\\\jobs\\\\log parser\\\\run_stats.bat','','',1183130181,'','','',NULL,0,'2007-04-16','00:00:00',1183129581,10,0,0,0,0,0),(3,'Prune events from database',NULL,'DAD Internals','C:\\\\dad\\\\jobs\\\\log parser\\\\run_groomer.bat','','',1183442400,'','','',NULL,0,'2007-04-16','23:00:00',1182837600,0,0,7,0,0,0),(4,'Alert on Domain Joins',NULL,'Alert','C:\\\\dad\\\\jobs\\\\alerts\\\\DomainJoins.bat',NULL,NULL,1183129898,NULL,NULL,NULL,NULL,NULL,'2007-04-16',NULL,1183129598,5,NULL,NULL,NULL,0,0),(5,'Alert on Audit Log Cleared',NULL,'Alert','C:\\\\dad\\\\jobs\\\\alerts\\\\AuditLogCleared.bat',NULL,NULL,1183129777,NULL,NULL,NULL,NULL,NULL,'2007-04-16',NULL,1183129477,5,NULL,NULL,NULL,0,0),(6,'Alert on Remote Desktop connections',NULL,'Alert','C:\\\\dad\\\\jobs\\\\alerts\\\\RemoteDesktop.bat',NULL,NULL,1183129920,NULL,NULL,NULL,0,NULL,'2007-04-16',NULL,1183129320,10,0,0,0,0,0),(7,'Start Aggregator',NULL,'DAD Internals','C:\\\\dad\\\\jobs\\\\log parser\\\\run_aggregator.bat','','',1177026720,'','','',NULL,0,'2007-04-19','16:52:00',0,0,0,0,0,1,1),(9,'Run Log Carver',NULL,'DAD Internals','c:\\\\dad\\\\jobs\\\\log parser\\\\run_carver.bat','','',1183129800,'','','',NULL,0,'2007-04-20','20:00:00',1183129500,5,0,0,0,0,0),(8,'DAD Update Status',NULL,'DAD Internals','c:\\\\dad\\\\jobs\\\\alerts\\\\updates.bat','','',1183130160,'','','',NULL,0,'2007-04-19','22:31:00',1183129260,15,0,0,0,0,0),(10,'Run Syslog Service',NULL,'DAD Internals','c:\\\\dad\\\\jobs\\\\start_syslog.bat','','',1177300140,'','','',NULL,0,'2007-04-20','19:59:00',0,5,0,0,0,1,1),(11,'Check logon types',NULL,'Alert','c:\\\\dad\\\\jobs\\\\alerts\\\\LogonType.bat','','',1183129860,'','','',NULL,0,'2007-04-25','11:51:00',1183129260,10,0,0,0,0,0);
/*!40000 ALTER TABLE `dad_adm_job` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `dad_adm_carvers`
--

DROP TABLE IF EXISTS `dad_adm_carvers`;
CREATE TABLE `dad_adm_carvers` (
  `dad_adm_carvers_id` int(10) unsigned NOT NULL auto_increment,
  `match_rule` varchar(768) NOT NULL default '',
  `carve_rule` varchar(768) NOT NULL default '',
  `creator_id` int(10) unsigned NOT NULL default '0',
  `last_edited_by` int(10) unsigned NOT NULL default '0',
  `creation_date` int(10) unsigned NOT NULL default '0',
  `last_edit_date` int(10) unsigned NOT NULL default '0',
  `rule_name` varchar(45) NOT NULL default '',
  PRIMARY KEY  (`dad_adm_carvers_id`)
) ENGINE=MyISAM AUTO_INCREMENT=4 DEFAULT CHARSET=latin1 COMMENT='Contains matching and carving rules for log extraction';

--
-- Dumping data for table `dad_adm_carvers`
--

LOCK TABLES `dad_adm_carvers` WRITE;
/*!40000 ALTER TABLE `dad_adm_carvers` DISABLE KEYS */;
INSERT INTO `dad_adm_carvers` VALUES (1,'.*postfix.*from=','.*postfix.*from=([<>a-zA-Z0-9._@]+) .*',1,0,0,0,'Sample Postfix Rule'),(2,'.*MAC.*SRC.*DST','.*SRC=([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}) DST=([0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}\\.[0-9]{1,3}) .*TTL=([0-9]+).*PROTO=([0-9A-Za-z]+) SPT=([0-9]+) DPT=([0-9]+)',1,0,0,0,'IPTables Blocked Packets'),(3,'[0-9]+','([0-9]+)',1,0,0,0,'test rule');
/*!40000 ALTER TABLE `dad_adm_carvers` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `dad_adm_action`
--

DROP TABLE IF EXISTS `dad_adm_action`;
CREATE TABLE `dad_adm_action` (
  `id_dad_adm_action` mediumint(8) unsigned NOT NULL auto_increment,
  `abbreviation` char(1) default NULL,
  `name` varchar(50) NOT NULL default '',
  `description` text,
  `activeyesno` tinyint(1) unsigned NOT NULL default '0',
  `timeactive` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`id_dad_adm_action`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Dumping data for table `dad_adm_action`
--

LOCK TABLES `dad_adm_action` WRITE;
/*!40000 ALTER TABLE `dad_adm_action` DISABLE KEYS */;
/*!40000 ALTER TABLE `dad_adm_action` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `dad_adm_computer_group`
--

DROP TABLE IF EXISTS `dad_adm_computer_group`;
CREATE TABLE `dad_adm_computer_group` (
  `id_dad_adm_computer_group` int(10) unsigned NOT NULL auto_increment,
  `group_name` varchar(45) default NULL,
  `description` varchar(100) default NULL,
  `calleractive` varchar(45) default NULL,
  `timeactive` int(11) default NULL,
  PRIMARY KEY  (`id_dad_adm_computer_group`)
) ENGINE=MyISAM AUTO_INCREMENT=2 DEFAULT CHARSET=latin1;

--
-- Dumping data for table `dad_adm_computer_group`
--

LOCK TABLES `dad_adm_computer_group` WRITE;
/*!40000 ALTER TABLE `dad_adm_computer_group` DISABLE KEYS */;
INSERT INTO `dad_adm_computer_group` VALUES (1,'Test Group','','',1182408885);
/*!40000 ALTER TABLE `dad_adm_computer_group` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `dad_sys_services`
--

DROP TABLE IF EXISTS `dad_sys_services`;
CREATE TABLE `dad_sys_services` (
  `Service_ID` int(10) unsigned NOT NULL auto_increment,
  `Service_Name` varchar(45) NOT NULL default '',
  `Contact_Information` varchar(80) NOT NULL default '',
  `log_these_id` int(11) default NULL,
  PRIMARY KEY  (`Service_ID`)
) ENGINE=MyISAM AUTO_INCREMENT=2029 DEFAULT CHARSET=latin1 COMMENT='Tracks services reported on';

--
-- Dumping data for table `dad_sys_services`
--

LOCK TABLES `dad_sys_services` WRITE;
/*!40000 ALTER TABLE `dad_sys_services` DISABLE KEYS */;
INSERT INTO `dad_sys_services` VALUES (1988,'newsyslog','',NULL),(1989,'sshd','',NULL),(1990,'mysqld','',NULL),(1991,'shutdown','',NULL),(1992,'saslauthd','',NULL),(1993,'su','',NULL),(1994,'CIS-WEBAPP','',NULL),(1995,'sudo','',NULL),(1996,'syslogd','',NULL),(1997,'last','',NULL),(1998,'inetd','',NULL),(1999,'Security','',2),(2000,'System','',4),(2001,'Application','',1),(2005,'CIS-XFER','',NULL),(2004,'watch','',NULL),(2006,'CIS-WEB','',NULL),(2007,'DNS Server','',8),(2008,'DHCP Server','',16),(2009,'Directory Service','',32),(2010,'File Replication Service','',64),(2011,'PDT','',NULL),(2012,'postfixsmtpd','',NULL),(2013,'postfixcleanup','',NULL),(2014,'spamd','',NULL),(2015,'postfixpickup','',NULL),(2016,'postfixpipe','',NULL),(2017,'postfixlocal','',NULL),(2018,'postfixsmtp','',NULL),(2019,'CRON','',NULL),(2020,'USRSBINCRON','',NULL),(2021,'named','',NULL),(2022,'--','',NULL),(2023,'checkpc','',NULL),(2024,'squid','',NULL),(2025,'exiting','',NULL),(2026,'kernel','',NULL),(2027,'spamc','',NULL),(2028,'crontab','',NULL);
/*!40000 ALTER TABLE `dad_sys_services` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `dad_event_log_types`
--

DROP TABLE IF EXISTS `dad_event_log_types`;
CREATE TABLE `dad_event_log_types` (
  `Event_Log_Type_ID` int(10) unsigned NOT NULL auto_increment,
  `Log_Type` varchar(45) NOT NULL,
  `Log_Type_Value` int(10) unsigned NOT NULL,
  PRIMARY KEY  (`Event_Log_Type_ID`)
) ENGINE=MyISAM AUTO_INCREMENT=8 DEFAULT CHARSET=utf8 COMMENT='Used to map event log types to binary values';

--
-- Dumping data for table `dad_event_log_types`
--

LOCK TABLES `dad_event_log_types` WRITE;
/*!40000 ALTER TABLE `dad_event_log_types` DISABLE KEYS */;
INSERT INTO `dad_event_log_types` VALUES (1,'Application',1),(2,'Security',2),(3,'System',4),(4,'DNS Server',8),(5,'DHCP Server',16),(6,'Directory Service',32),(7,'File Replication Service',64);
/*!40000 ALTER TABLE `dad_event_log_types` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `dad_sys_events_aging`
--

DROP TABLE IF EXISTS `dad_sys_events_aging`;
CREATE TABLE `dad_sys_events_aging` (
  `Aging_ID` int(10) unsigned NOT NULL auto_increment,
  `Event_ID` int(10) unsigned NOT NULL,
  `Explanation` varchar(255) NOT NULL,
  `Retention_Time` int(10) unsigned NOT NULL,
  PRIMARY KEY  (`Aging_ID`)
) ENGINE=MyISAM AUTO_INCREMENT=12 DEFAULT CHARSET=latin1 COMMENT='Aging schedule for various Windows events';

--
-- Dumping data for table `dad_sys_events_aging`
--

LOCK TABLES `dad_sys_events_aging` WRITE;
/*!40000 ALTER TABLE `dad_sys_events_aging` DISABLE KEYS */;
INSERT INTO `dad_sys_events_aging` VALUES (1,0,'Default',3888000),(2,560,'Object Access Events',604800),(3,592,'Process Tracking Events',172800),(4,632,'Group Changes',60480000),(5,633,'Group Changes',60480000),(6,636,'Group Changes',60480000),(7,637,'Group Changes',60480000),(8,660,'Group Changes',60480000),(9,661,'Group Changes',60480000),(10,565,'Audited Object Access',86400),(11,576,'Rights Assigned',0);
/*!40000 ALTER TABLE `dad_sys_events_aging` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `dad_sys_filtered_events`
--

DROP TABLE IF EXISTS `dad_sys_filtered_events`;
CREATE TABLE `dad_sys_filtered_events` (
  `Filtered_ID` int(10) unsigned NOT NULL auto_increment,
  `Event_ID` int(10) unsigned NOT NULL,
  `Description` varchar(45) NOT NULL,
  PRIMARY KEY  (`Filtered_ID`)
) ENGINE=MyISAM AUTO_INCREMENT=10 DEFAULT CHARSET=latin1 COMMENT='Event IDs that are filtered from incoming logs';

--
-- Dumping data for table `dad_sys_filtered_events`
--

LOCK TABLES `dad_sys_filtered_events` WRITE;
/*!40000 ALTER TABLE `dad_sys_filtered_events` DISABLE KEYS */;
INSERT INTO `dad_sys_filtered_events` VALUES (1,562,'Object access auditing:  Handle Closed'),(2,565,'Object access auditing:  Undetermined.  Relat'),(3,592,'Process Tracking:  Process Created'),(4,593,'Process Tracking:  Process Destroyed'),(5,600,'Process Tracking:  Process assigned primary t'),(6,673,'Kerberos:  Service Ticket Granted'),(7,674,'Kerberos:  Ticket Granted Renewed'),(8,677,'Kerberos:  Service ticket request failed'),(9,576,'Rights Assigned:  Only noted at login, not us');
/*!40000 ALTER TABLE `dad_sys_filtered_events` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `dad_sys_linked_queries`
--

DROP TABLE IF EXISTS `dad_sys_linked_queries`;
CREATE TABLE `dad_sys_linked_queries` (
  `Query_ID` int(10) unsigned NOT NULL auto_increment,
  `SQL` varchar(768) NOT NULL,
  `Role_ID` int(10) unsigned NOT NULL COMMENT 'Eventually to be used to limit who can query what...  Maybe this should be handled somewhere else?  Here too...',
  `Query_Desc` varchar(255) NOT NULL,
  PRIMARY KEY  (`Query_ID`)
) ENGINE=MyISAM AUTO_INCREMENT=2 DEFAULT CHARSET=latin1 COMMENT='These queries are linked to by other queries, never called d';

--
-- Dumping data for table `dad_sys_linked_queries`
--

LOCK TABLES `dad_sys_linked_queries` WRITE;
/*!40000 ALTER TABLE `dad_sys_linked_queries` DISABLE KEYS */;
INSERT INTO `dad_sys_linked_queries` VALUES (1,'SELECT Field_10 as \'count_User\',Field_15 as \'IP Address\' FROM dad_sys_events WHERE  Field_8=\'675\' AND Field_14=\'0x18\') and field_15 = \'~0\'',0,'Takes an IP address and returns all usernames reported in authentication failures from that IP address');
/*!40000 ALTER TABLE `dad_sys_linked_queries` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `dad_sys_queries`
--

DROP TABLE IF EXISTS `dad_sys_queries`;
CREATE TABLE `dad_sys_queries` (
  `Query_ID` int(10) unsigned NOT NULL auto_increment,
  `Query` varchar(1024) NOT NULL,
  `Description` varchar(1024) NOT NULL,
  `Name` varchar(45) NOT NULL,
  `Category` varchar(45) NOT NULL,
  `Roles` varchar(256) NOT NULL default '',
  PRIMARY KEY  (`Query_ID`)
) ENGINE=MyISAM AUTO_INCREMENT=65 DEFAULT CHARSET=latin1 COMMENT='Used for stored queries';

--
-- Dumping data for table `dad_sys_queries`
--

LOCK TABLES `dad_sys_queries` WRITE;
/*!40000 ALTER TABLE `dad_sys_queries` DISABLE KEYS */;
INSERT INTO `dad_sys_queries` VALUES (2,'SELECT Service_ID,Service_Name FROM dad_sys_services ORDER BY Service_Name','Produces a list of all services currently understood by the log aggregator.','Show Services','DAD','1,2'),(3,'SELECT FROM_UNIXTIME(dad_sys_events.TimeGenerated) as Time, dad_sys_events.Computer,dad_sys_events.Field_0 as \'Username Attempted\',Field_1 as \'Domain\' FROM dad_sys_events WHERE dad_sys_events.idxID_Code=\'529 2\'  ORDER BY TimeGenerated','Produces a list of all login failures (Event 529) from all Windows computers.','Failed Interactive','General Windows','1,2'),(5,'SELECT FROM_UNIXTIME(dad_sys_events.TimeGenerated) as Time, dad_sys_events.Computer,dad_sys_events.Field_0 as \"Username Attempted\", dad_sys_events.EventID FROM dad.dad_sys_events WHERE dad_sys_events.TimeGenerated>(UNIX_TIMESTAMP(NOW())-86400) AND dad_sys_events.idxID_Code=\'529 7\'  ORDER BY dad_sys_events.TimeGenerated','Reports all failed attempts to unlock a workstation that have occured in the past 24 hours.','Failed unlock 24','General Windows','1,2'),(6,'SELECT FROM_UNIXTIME(dad_sys_events.TimeGenerated) as Time, dad_sys_events.Computer,dad_sys_events.Field_0 as \"Username Attempted\", Field_1 as \'Domain\' FROM dad.dad_sys_events WHERE dad_sys_events.TimeGenerated>(UNIX_TIMESTAMP(NOW())-86400) AND idxID_Code=\'529 2\'  ORDER BY dad_sys_events.TimeGenerated','Reports all failed interactive login attempts that have occured in the past 24 hours.','Failed Interactive 24','General Windows','1,2'),(33,'SELECT FROM_UNIXTIME(TimeGenerated) as Time, Field_0 as \'User ID\',Computer,Field_5 as \'IP Address\'  FROM dad_sys_events  WHERE  idxID_Kerb=\'675 0x25\' ORDER BY TimeGenerated','Reports all authentication attempts where the clock skew on the client was too high.  Usually followed by a success since the correct time is returned with the error','Time Skew Too Great','Kerberos','1,2'),(34,'SELECT FROM_UNIXTIME(TimeGenerated) as Time, Field_0 as \'User ID\',Computer,Field_5 as \'IP Address\'  FROM dad_sys_events  WHERE  idxID_Kerb=\'675 0x19\' ORDER BY TimeGenerated','Reports all authentication attempts that are refused because pre-authentication is required.  This also throws the same error internally as a bad password','Pre-Auth required/Bad Password','Kerberos','1,2'),(32,'SELECT FROM_UNIXTIME(TimeGenerated) as Time, Field_0 as \'User ID\',Computer,Field_5 as \'IP Address\'  FROM dad_sys_events  WHERE  idxID_Kerb=\'675 0xE\' ORDER BY TimeGenerated','Reports all instances where the KDC refused to authenticate because the encryption type presented was not supported','Encryption Not Supported','Kerberos','1,2'),(12,'SELECT FROM_UNIXTIME(TimeGenerated) as Time, Computer, Field_1 as \'Username Attempted\' FROM dad.dad_sys_events WHERE Field_3=\'3221225578\'  ORDER BY TimeGenerated','Reports all failed NTLM authentications where a bad password was attempted.','Bad Password','NTLM','1,2'),(13,'SELECT FROM_UNIXTIME(TimeGenerated) as Time, Computer as \'Reported By\', Field_2 as \'From System\', Field_1 as \'Username Attempted\' FROM dad_sys_events WHERE idxID_NTLM=\'681 3221225572\' ORDER BY TimeGenerated','WARNING: This is easily a 15 minute query! Reports all NTLM authentication failures where a bad username was attempted.','Failed Username','NTLM','1,2'),(14,'SELECT FROM_UNIXTIME(TimeGenerated) as Timestamp, Computer,  Field_1 as \'User Name\' FROM dad_sys_events  WHERE idxID_NTLM=\'680 3221226036\' OR idxID_NTLM=\'681 3221226036\' ORDER BY TimeGenerated','Reports all NTLM authentication attempts where a locked out account was attempting to authenticate.','Locked Out','NTLM','1,2'),(15,'SELECT FROM_UNIXTIME(TimeGenerated) as Timestamp, Computer,  Field_1 as \'User Name\', EventID FROM dad_sys_events  WHERE idxID_NTLM=\'681 3221225586\' OR idxID_NTLM=\'680 3221225586\' ORDER BY TimeGenerated','Reports all NTLM authentication attempts where the account being used has been disabled.','Disabled','NTLM','1,2'),(16,'SELECT FROM_UNIXTIME(TimeGenerated) as Timestamp, Computer as \'Authenticating Server\', Field_1 as \'User Name\', Field_2 as \'Originating Workstation\' FROM dad_sys_events  WHERE idxID_NTLM=\'680 3221225583\' OR idxID_NTLM=\'681 3221225583\'','Reports all failed NTLM authentications where the account being used may have been legal but the attempt was in violation of login hours restrictions.','Out of Hours','NTLM','1,2'),(17,'SELECT FROM_UNIXTIME(TimeGenerated) as Timestamp, Computer,  Field_1, Field_0, EventID FROM dad_sys_events  WHERE  idxID_NTLM=\'680 3221225584\' OR idxID_NTLM=\'681 3221225584\' ORDER BY TimeGenerated','Reports all NTLM authentication failures where the account in use is restricted from logging into the workstation used.','Workstation Restriction','NTLM','1,2'),(18,'SELECT FROM_UNIXTIME(TimeGenerated) as Timestamp, Computer,  Field_1 as \'User Name\', EventID FROM dad_sys_events  WHERE  idxID_NTLM=\'680 3221225875\' OR idxID_NTLM=\'681 3221225875\' ORDER BY TimeGenerated','Reports all NTLM authentication failures where the account being used has expired.','Expired','NTLM','1,2'),(19,'SELECT FROM_UNIXTIME(TimeGenerated) as Timestamp, Computer, Field_1 as \'User Name\', EventID FROM dad_sys_events  WHERE idxID_NTLM=\'680 3221225585\' OR idxID_NTLM=\'681 3221225585\' ORDER BY TimeGenerated','Reports all NTLM authentication failures where the password for the account being used has expired.','Password Expired','NTLM','1,2'),(20,'SELECT FROM_UNIXTIME(TimeGenerated) as Timestamp, Computer,  Field_1 as \'User Name\', EventID FROM dad_sys_events  WHERE idxID_NTLM=\'680 3221226020\' OR idxID_NTLM=\'681 3221226020\' ORDER BY TimeGenerated','Reports all NTLM authentication events where the next logon will require a password change.','Password Change','NTLM','1,2'),(21,'SELECT FROM_UNIXTIME(TimeGenerated) as Timestamp, Field_0 as \'User ID\', Computer,Field_5 as \'IP Address\'  FROM dad_sys_events  WHERE  idxID_Kerb=\'675 0x18\' AND TimeGenerated>(UNIX_TIMESTAMP(NOW())-604800) ORDER BY TimeGenerated','Reports all Kerberos authentication attempts where a bad password was attempted that have occured in the past 7 days','Bad Password 7 Days','Kerberos','1,2'),(22,'SELECT FROM_UNIXTIME(TimeGenerated) as Timestamp, Field_0 as \'User ID\', Computer, Field_5 as \'IP Address\'  FROM dad_sys_events  WHERE  idxID_Kerb=\'675 0x12\' ORDER BY TimeGenerated','Reports all Kerberos authentication events where the account in question is either disabled, expired or locked out.','Account Disabled/Unavailable','Kerberos','1,2'),(23,'SELECT FROM_UNIXTIME(TimeGenerated) as Timestamp, Field_0 as \'User ID\', Computer, Field_5 as \'IP Address\'  FROM dad_sys_events  WHERE idxID_Kerb=\'675 0xC\' ORDER BY TimeGenerated','Reports all Kerberos authentication attempts where the account in question is either attempting to violate login time restrictions or has workstation restrictions applied.','Workstation Restriction','Kerberos','1,2'),(24,'SELECT FROM_UNIXTIME(TimeGenerated) as Timestamp, Field_0 as \'User ID\', Computer, Field_5 as \'IP Address\'  FROM dad_sys_events  WHERE  idxID_Kerb=\'675 0x17\' ORDER BY TimeGenerated','Reports all Kerberos authentication events where the password for the account used has expired.','Expired Password','Kerberos','1,2'),(25,'SELECT FROM_UNIXTIME(TimeGenerated) as Timestamp, Field_0 as \'User ID\', Computer, Field_5 as \'IP Address\'  FROM dad_sys_events  WHERE  idxID_Kerb=\'675 0x6\' ORDER BY TimeGenerated','Reports all Kerberos authentication attempts where a bad username was supplied.','Bad Username','Kerberos','1,2'),(26,'SELECT FROM_UNIXTIME(MIN(TimeGenerated)) as Timestamp, Field_10 as \'User ID\', Field_7 as \'Server\',  Field_2 as \'Filename\' FROM dad_sys_events  WHERE EventID=\'560\' AND (Field_25=\'mpg\' OR Field_25=\'mp3\' OR Field_25=\'avi\' OR Field_25=\'wmv\') GROUP BY Field_2 ORDER BY TimeGenerated','Reports the first instance of all AVI, MP3, MPG and WMV files that turn up in 560 events.','Interesting Files','General Windows','1,2'),(27,'SELECT FROM_UNIXTIME(TimeGenerated) as Timestamp, Field_0 as \'User ID\', Computer, Field_5 as \'IP Address\'  FROM dad_sys_events  WHERE  idxID_Kerb=\'675 0x18\' AND TimeGenerated>(UNIX_TIMESTAMP(NOW())-86400) ORDER BY TimeGenerated','Reports all Kerberos authentication events where a bad password was attempted that have occured in the past 24 hours.','Bad Password 24','Kerberos','1,2'),(28,'SELECT FROM_UNIXTIME(MIN(TimeGenerated)) as Timestamp, Field_10 as \'User ID\', Field_7 as \'Server\', Field_2 as \'Filename\' FROM dad_sys_events WHERE EventID=\'560\' AND (Field_25=\'mpg\' OR Field_25=\'mp3\' OR Field_25=\'avi\' OR Field_25=\'wmv\') AND TimeGenerated>(UNIX_TIMESTAMP(NOW())-86400) GROUP BY Field_2 ORDER BY TimeGenerated','Reports the first instance of all AVI, MP3, MPG and WMV files that turn up in 560 events over the past 24 hours.','Interesting Files 24','General Windows','1,2'),(29,'SELECT FROM_UNIXTIME(TimeGenerated) as Timestamp, Computer, EventID FROM dad_sys_events  WHERE (idxID_NTLM=\'680 3221225572\' OR idxID_NTLM=\'681 3221225572\') AND TimeGenerated>(UNIX_TIMESTAMP(NOW())-86400) ORDER BY TimeGenerated','Reports all NTLM authentication failures from the past 24 hours where a bad username was attempted.','Failed Username 24','NTLM','1,2'),(30,'SELECT Priority,System_Name as \'System Name\' FROM dad_sys_event_import_from ORDER BY System_Name','Reports all of the systems from which Windows Event Logs are being actively polled.','Windows Event Log Polling','DAD','1,2'),(31,'SELECT FROM_UNIXTIME(TimeGenerated) as Timestamp, Computer, Field_1 as \'Username Attempted\' FROM dad.dad_sys_events WHERE (idxID_NTLM=\'680 3221225578\' OR idxID_NTLM=\'681 3221225578\')  AND TimeGenerated>(UNIX_TIMESTAMP(NOW())-86400) ORDER BY TimeGenerated','Reports all failed NTLM authentications where a bad password was used in the past 24 hours','Bad Password 24','NTLM','1,2'),(35,'SELECT count(distinct Field_0) as \'Number of Accounts\',Field_5 as \'IP Address\' FROM dad_sys_events WHERE idxID_Kerb=\'675 0x18\' AND TimeGenerated>(UNIX_TIMESTAMP(NOW())-86400) group by field_5 having count( distinct field_0) > 2 ORDER BY Field_5','Identifies all IP addresses where more than two accounts have failed to log on in the past 24 hours','Multiple Login Failures by IP Address','Kerberos','1,2'),(36,'SELECT FROM_UNIXTIME(TimeGenerated) as \'Time\', Computer as \'Server\', Field_1 as \'Domain\', Field_0 as \'User\', if(EventID=\'528\',\'Logon\',\'Logoff\') as \'Action\', Field_2 as \'Logon ID\' FROM dad_sys_events  WHERE idxID_NTLM=\'540 2\' OR idxID_NTLM=\'538 2\' OR idxID_NTLM=\'529 2\' OR idxID_NTLM=\'528 2\' OR idxID_NTLM=\'539 2\' ORDER BY Field_3,TimeGenerated','Identifies and correlates all recorded logon and logoff entries by Logon ID','Correlated Logon/Logoff','General Windows','1,2'),(37,'SELECT FROM_UNIXTIME(TimeGenerated) as \'Time\', Computer as \'Server\', Field_1 as \'Domain\', Field_0 as \'User\', if(EventID=\'528\',\'Logon\',\'Logoff\') as \'Action\', Field_2 as \'Logon ID\' FROM dad_sys_events  WHERE (idxID_NTLM=\'540 2\' OR idxID_NTLM=\'538 2\' OR idxID_NTLM=\'529 2\' OR idxID_NTLM=\'528 2\' OR idxID_NTLM=\'539 2\') AND TimeGenerated>(UNIX_TIMESTAMP(NOW())-86400) ORDER BY Field_2,TimeGenerated','Identifies and correlates all recorded logon and logoff entries by Logon ID that have occured in the past 24 hours','Correlated Logon/Logoff 24','General Windows','1,2'),(38,'SELECT FROM_UNIXTIME(dad_sys_events.TimeGenerated) as Time, dad_sys_events.Computer,dad_sys_events.Field_0 as \"Username Attempted\", dad_sys_events.EventID FROM dad.dad_sys_events WHERE dad_sys_events.idxID_Code=\'529 7\'  ORDER BY dad_sys_events.TimeGenerated','Reports all recorded faliures to unlock workstations or servers','Failed Unlock','General Windows','1,2'),(39,'SELECT FROM_UNIXTIME(MIN(TimeGenerated)) as Timestamp, Field_11 as \'User ID\', Field_13 as \'Logon ID\', Computer,  Field_9 as \'Domain\', Field_2 as \'Filename\' FROM dad_sys_events  WHERE EventID=\'560\' AND Field_1=\'File\' GROUP BY Field_2 ORDER BY TimeGenerated','Report all activity involving monitored resources','Monitored Resources','General Windows','1,2'),(40,'select EventID, count(EventID) as \'Event Count\' FROM dad_sys_events group by EventID','Report current event IDs and counts','Event Count','DAD','1,2'),(41,'select FROM_UNIXTIME(TimeGenerated) as Time, Computer as \'Attempt to login to\', Field_0 as \'Username attempted\', Field_5 as \'Source\' from dad_sys_events WHERE idxID_Code=\'529 3\' AND idxID_NTLM=\'529 NtLmSsp\' ORDER BY TimeGenerated','Report failed network logon attempts','Failed Network Logons','General Windows','1,2'),(42,'select FROM_UNIXTIME(TimeGenerated) as Time, Computer as \'Attempt to login to\', Field_0 as \'Username attempted\', Field_5 as \'Source\' from dad_sys_events WHERE idxID_Code=\'529 3\' AND idxID_NTLM=\'529 NtLmSsp\' AND TimeGenerated>(UNIX_TIMESTAMP(NOW())-86400) ORDER BY TimeGenerated','Report failed network logon attempts that have occured in the past 24 hours','Failed Network Logons 24','General Windows','1,2'),(43,'select FROM_UNIXTIME(TimeGenerated) as Time, Computer, Field_0 as \'NTP Message\' WHERE EventID=\'3\' AND Source=\'NTP\' AND TimeGenerated>(UNIX_TIMESTAMP(NOW())-3600) ORDER BY TimeGenerated','Display recent NTP events','NTP Events 60','General Windows','1,2'),(44,'SELECT FROM_UNIXTIME(TimeGenerated) as Time, Computer as Server, Field_2 as \'User Name\', Field_1 as \'File Printed\', Field_3 as \'Printer\',  Field_5 as \'Bytes\', Field_6 as \'Pages\' FROM dad_sys_events WHERE EventID=\'10\' AND Source=\'Print\' ORDER BY TimeGenerated','Display recently printed documents','Printed','General Windows','1,2'),(45,'SELECT FROM_UNIXTIME(TimeGenerated) as Time, Computer as Server, Field_2 as \'User Name\', Field_1 as \'File Printed\', Field_3 as \'Printer\',  Field_5 as \'Bytes\', Field_6 as \'Pages\' FROM dad_sys_events WHERE EventID=\'10\' AND Source=\'Print\' AND TimeGenerated>(UNIX_TIMESTAMP(NOW())-86400) ORDER BY TimeGenerated','Display documents printed in the past 24 hours','Printed 24','General Windows','1,2'),(46,'select FROM_UNIXTIME(TimeGenerated) as Time, Computer, Field_0 as \'Date Applied\', Field_1 as \'Time Applied\', Field_2 as \'Updates Applied\' from dad.dad_sys_events WHERE EventID=\'18\' AND EventType=\'4\' ORDER BY Computer,TimeGenerated','Reports patches applied through Update Services','Updates','General Windows','1,2'),(47,'select FROM_UNIXTIME(TimeGenerated) as Time, Computer, Field_0 as \'Date Applied\', Field_1 as \'Time Applied\', Field_2 as \'Updates Applied\' from dad.dad_sys_events WHERE EventID=\'18\' AND EventType=\'4\' AND TimeGenerated>(UNIX_TIMESTAMP(NOW())-86400) ORDER BY Computer,TimeGenerated','Reports patches applied through Update Services in the past 24 hours','Updates 24','General Windows','1,2'),(48,'select FROM_UNIXTIME(TimeGenerated) as Time, Computer, Field_0 as Error, Field_1 as \'Error Detail\' from dad.dad_sys_events WHERE EventID=\'26\' ORDER BY TimeGenerated','Reports recent application errors reported at system consoles','Errors','General Windows','1,2'),(49,'select FROM_UNIXTIME(TimeGenerated) as Time, Computer, Field_0 as Error, Field_1 as \'Error Detail\' from dad.dad_sys_events WHERE EventID=\'26\' AND TimeGenerated>(UNIX_TIMESTAMP(NOW())-86400) ORDER BY TimeGenerated','Reports application errors reported at consoles within the past 24 hours','Errors 24','General Windows','1,2'),(50,'select EventID, count(EventID) as \'Event Count\' FROM dad_sys_events group by EventID ORDER BY Count(EventID) DESC','Reports current event IDs and counts sorted by count','Event Count Sorted','DAD','1,2'),(52,'select Computer, count(SystemID) as \'Event Count\' FROM dad_sys_events group by Computer','Produces a list of all systems monitored and the number of events generated by each of those systems','Event Count by System','DAD','1,2'),(51,'SELECT FROM_UNIXTIME(TimeGenerated) as Timestamp, Computer,  Field_1 as \'Domain\', Field_0 as \'User ID\', Field_2 as \'Logon Type\', Field_6 as \'Calling User\', Field_8 as \'Logon ID\' FROM dad_sys_events  WHERE  idxID_NTLM=\'534 seclogon\' ORDER BY TimeGenerated','Reports login failures based on logon type','Logon Type Failed','General Windows','1,2'),(53,'SELECT FROM_UNIXTIME(dad_sys_events.TimeGenerated) as Time, Computer, EventID as \'Event ID\', Field_0 as \'Username\', Field_1 as \'Domain\'  from dad_sys_events WHERE EventID=\'529\' OR EventID=\'530\' OR EventID=\'531\' OR EventID=\'532\' OR EventID=\'533\' OR EventID=\'534\' OR EventID=\'535\' OR EventID=\'536\' OR EventID=\'537\' OR EventID=\'539\'','Reports all types of logon failures that have occured','All Logon Failures','General Windows','1,2'),(54,'SELECT FROM_UNIXTIME(dad_sys_events.TimeGenerated) as Time, dad_sys_systems.System_Name as \"Reporting system\", Computer as \"Reset from\", Field_0 as \'Primary User\', Field_1 as \'Primary Domain\', Field_2 as \'Primary Logon\', Field_3 as \'Client User\', Field_4 as \'Client Domain\', Field_5 as \'Client Logon\' FROM dad_sys_events, dad_sys_systems WHERE EventID=\'517\' AND dad_sys_events.SystemID=dad_sys_systems.System_ID ORDER BY dad_sys_events.TimeGenerated ','Reports any events indicating that the event log was cleared.','Audit Log Cleared','General Windows','1,2'),(55,'SELECT FROM_UNIXTIME(dad_sys_events.TimeGenerated) as Time, dad_sys_events.Computer, Field_0 as \'Domain\', Field_1 as \'Domain ID\', Field_2 as \'User\', Field_3 as \'Domain\', Field_4 as \'Logon\' FROM dad_sys_events WHERE EventID=\'610\' ORDER BY dad_sys_events.TimeGenerated','Reports any events that record the creation of a domain trust.','Domain Trust Established','General Windows','1,2'),(56,'SELECT FROM_UNIXTIME(dad_sys_events.TimeGenerated) as Time, dad_sys_events.Computer, Field_0 as \'Domain\', Field_1 as \'Domain ID\', Field_2 as \'User\', Field_3 as \'Domain\', Field_4 as \'Logon\' FROM dad_sys_events WHERE EventID=\'611\' ORDER BY dad_sys_events.TimeGenerated','Reports any events that record the elimination of a domain trust.','Domain Trust Removed','General Windows','1,2'),(57,'SELECT FROM_UNIXTIME(dad_sys_events.TimeGenerated) as Time, dad_sys_events.Computer, Field_0 as \'New User\', Field_1 as \'Domain\', Field_2 as \'SID\', Field_3 as \'Created By\', Field_4 as \'Domain\', Field_5 as \'Logon\' FROM dad_sys_events WHERE EventID=\'624\' ORDER BY dad_sys_events.TimeGenerated','Reports the creation of new accounts within the domain.','Account Created','General Windows','1,2'),(58,'SELECT FROM_UNIXTIME(TimeGenerated) as \'Time\', Computer as \'Reported by\', Field_3 as \'User\', Field_0 as \'Computer Added\', Field_1 as \'Domain\' FROM dad_sys_events WHERE EventID=\'645\' ORDER BY TimeGenerated','Reports all events indicating that a machine has been joined to the domain.  Includes the user ID used to join the computer to the domain and the Domain Controller that processed the request.','Domain Joins','General Windows','1,2'),(59,'SELECT Priority, System_Name as \"System\", FROM_UNIXTIME(Next_Run) as \"Next Polls at\" FROM dad_sys_event_import_from ORDER BY Priority','Displays the times at which all monitored systems will next be re-polled.','Next Polling Time','DAD','1,2'),(60,'UPDATE dad_sys_event_import_from SET Next_Run=\'0\'','Force all systems to be re-polled now.','Force Repolling','DAD','1,2'),(61,'SELECT FROM_UNIXTIME(TimeGenerated) as \'Time\', Field_0 as \'User\',Field_1 as \'Domain\', Computer as \'Connected To\', Field_3 as \'Connection\', Field_4 as \'From Computer\', Field_5 as \'Source IP Address\' FROM dad_sys_events WHERE EventID=\'682\'','Reports all remote desktop connections that have been established.','Remote Desktop Connections','General Windows','1,2'),(62,'SELECT descrip as \"Job\", FROM_UNIXTIME(next_start) as \"Next Start Time\", FROM_UNIXTIME(last_ran) as \"Last ran\", is_running as \"Running\" FROM dad_adm_job ORDER BY next_start','Reports all currently scheduled jobs, the status of each job and the next time that each job will start.','Scheduled Jobs','DAD','1,2'),(63,'SELECT FROM_UNIXTIME(Alert_Time) as \"Alerted at\", FROM_UNIXTIME(Event_Time) as \"Event Timestamp\", Event_Data as \"Alert\", Severity from dad_alerts WHERE Acknowledged=FALSE ORDER BY Alert_Time,Event_Time','Reports all current events that have not been acknowledged.','Pending Alerts','DAD','1,2'),(64,'SELECT TimeGenerated as \'Time\', Field_0 as \'User name\', Field_1 as \'Domain\', Field_2 as \'Logon type\', Computer FROM dad_sys_events WHERE EventID=\'534\'','This will report all 534 events where the logon type is not permitted for the specified user ID.','Logon type not permitted','General Windows','1,2');
/*!40000 ALTER TABLE `dad_sys_queries` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `language`
--

DROP TABLE IF EXISTS `language`;
CREATE TABLE `language` (
  `LanguageID` int(10) unsigned NOT NULL auto_increment,
  `LanguageCode` char(3) collate utf8_unicode_ci NOT NULL default '',
  `LanguageName` char(40) collate utf8_unicode_ci NOT NULL default '',
  `LatestChangeStamp` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  PRIMARY KEY  (`LanguageID`)
) ENGINE=MyISAM AUTO_INCREMENT=7 DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

--
-- Dumping data for table `language`
--

LOCK TABLES `language` WRITE;
/*!40000 ALTER TABLE `language` DISABLE KEYS */;
INSERT INTO `language` VALUES (1,'E','English','2005-06-28 17:08:24'),(2,'S','Spanish','2005-06-30 14:11:26'),(3,'DE','German','2007-03-15 02:35:26'),(4,'FR','French','2007-03-15 02:35:26'),(5,'J','Japanese','2007-03-15 02:35:26'),(6,'RU','Russian','2007-03-15 02:35:26');
/*!40000 ALTER TABLE `language` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `menu`
--

DROP TABLE IF EXISTS `menu`;
CREATE TABLE `menu` (
  `MenuID` int(10) unsigned NOT NULL auto_increment,
  `MenuName` char(40) collate utf8_unicode_ci NOT NULL default '',
  `LevelNum` tinyint(3) unsigned NOT NULL default '0',
  `SequenceNum` tinyint(3) unsigned NOT NULL default '0',
  `ParentMenuOptionID` int(10) unsigned NOT NULL default '0',
  `LatestChangeStamp` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  PRIMARY KEY  (`MenuID`)
) ENGINE=MyISAM AUTO_INCREMENT=9 DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

--
-- Dumping data for table `menu`
--

LOCK TABLES `menu` WRITE;
/*!40000 ALTER TABLE `menu` DISABLE KEYS */;
INSERT INTO `menu` VALUES (1,'Tabs',1,1,0,'2005-06-28 17:34:05'),(2,'Users',2,1,2,'2005-06-29 20:27:39'),(3,'Maintenance',2,1,10,'2005-06-30 12:34:24'),(5,'Preferences',2,2,5,'2005-07-05 12:32:49'),(6,'Resources',2,1,3,'2005-07-27 15:12:24'),(7,'Directory Service',2,1,4,'2005-10-24 19:55:52'),(8,'Log Analysis',2,1,57,'2006-05-29 12:28:12');
/*!40000 ALTER TABLE `menu` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `menuoption`
--

DROP TABLE IF EXISTS `menuoption`;
CREATE TABLE `menuoption` (
  `MenuOptionID` int(10) unsigned NOT NULL auto_increment,
  `OptionName` char(40) collate utf8_unicode_ci NOT NULL default '',
  `MenuID` int(10) unsigned NOT NULL default '0',
  `SequenceNum` smallint(5) unsigned NOT NULL default '0',
  `ContentPathName` char(128) collate utf8_unicode_ci NOT NULL default '',
  `FunctionName` char(40) collate utf8_unicode_ci NOT NULL default '',
  `LatestChangeStamp` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  PRIMARY KEY  (`MenuOptionID`)
) ENGINE=MyISAM AUTO_INCREMENT=71 DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

--
-- Dumping data for table `menuoption`
--

LOCK TABLES `menuoption` WRITE;
/*!40000 ALTER TABLE `menuoption` DISABLE KEYS */;
INSERT INTO `menuoption` VALUES (1,'Home',1,1,'home.php','showHomePage','2005-07-27 14:16:12'),(2,'Users',1,7,'','','2005-07-27 14:53:47'),(3,'Resources',1,2,'','','2005-10-24 19:56:55'),(4,'Directory Service',1,4,'','','2005-10-24 19:52:52'),(5,'Preferences',1,5,'','','2005-06-28 17:36:32'),(6,'Login Page',0,0,'login.php','showLoginPage','2005-07-27 14:16:12'),(7,'Submit Login Page',0,0,'login.php','loginUser','2005-07-27 14:16:12'),(8,'User Creation',2,1,'useradmin.php','CreateUserForm','2005-07-27 14:05:04'),(12,'User Deletion',2,2,'useradmin.php','DeleteUserForm','2005-07-27 14:05:19'),(10,'Maintenance',1,6,'','','2005-06-30 12:33:43'),(11,'Manage Menus',3,3,'MenuAdmin.php','ShowMenuOptions','2005-10-20 15:45:15'),(13,'Change Own Password',2,3,'useradmin.php','ChangeOwnPasswordForm','2005-07-27 14:05:52'),(14,'Reset User Password',2,4,'useradmin.php','ResetUserPasswordForm','2005-07-27 14:06:02'),(20,'LogoutUser',0,0,'login.php','LogoutUser','2005-07-27 14:17:01'),(21,'Change User Role',2,5,'useradmin.php','ChangeUserRoleForm','2005-07-27 14:06:15'),(22,'Change User Details',2,6,'useradmin.php','ChangeUserDetailsForm','2005-07-27 14:06:32'),(23,'Language Preference',5,1,'languagepref.php','showLanguagePrefs','2005-07-27 14:06:45'),(24,'Change Language Pref',5,0,'languagepref.php','setLanguagePrefs','2005-07-27 14:06:57'),(25,'Add Menu Option',3,2,'MenuAdmin.php','CreateNewOptionPage','2005-10-20 15:45:30'),(26,'Submit New Menu Option',3,0,'MenuAdmin.php','SubmitNewOption','2005-07-27 14:07:38'),(46,'fs_detail_edit',6,0,'fs_detail.php','fs_detail_edit','2005-08-11 19:10:40'),(54,'New Public Folder Entries',6,22,'pf_detail.php','pf_new_show','2005-10-24 19:13:07'),(53,'Public Folder<bold>',6,20,'pf_detail.php','pf_detail_show','2005-10-24 19:10:32'),(52,'New File System Entries',6,12,'fs_detail.php','fs_new_show','2005-10-24 18:57:33'),(50,'DAD System Events',3,1,'system.php','system_log_display','2007-02-14 21:07:47'),(49,'File System History',6,11,'fs_detail.php','fs_detail_history_show','2005-10-24 18:44:17'),(48,'Remove Alert Group - DELETE',3,0,'rs_admin.php','RemoveAlertGroup','2007-02-19 19:26:40'),(47,'Add Alert Group - DELETE',3,0,'rs_admin.php','AddAlertGroup','2007-02-19 19:26:53'),(44,'fs_detail_show',6,0,'fs_detail.php','fs_detail_show','2005-08-11 19:08:44'),(40,'Submit Modified Menu',3,0,'MenuAdmin.php','SubmitOptionEdit','2005-07-27 14:07:49'),(42,'File System<bold>',6,10,'fs_tree.php','DisplayFS','2005-10-24 19:08:20'),(55,'Public Folder History',6,21,'pf_detail.php','pf_detail_history_show','2005-10-24 19:19:44'),(56,'pf_detail_edit',6,0,'pf_detail.php','pf_detail_edit','2005-10-24 19:21:25'),(57,'Log Analysis',1,3,'log_analysis.php','show_log_stats','2006-05-29 13:00:18'),(58,'Existing Queries',8,1,'log_analysis.php','show_existing_queries','2006-05-29 12:29:02'),(59,'Query Builder',8,2,'log_analysis.php','show_query_builder','2006-05-29 17:39:53'),(60,'SQL Query',8,3,'log_analysis.php','show_sql_query','2006-05-29 12:31:35'),(61,'Jobs',3,4,'job_admin.php','edit_job','2006-06-15 18:29:49'),(62,'File Audit Search',8,10,'sys_events.php','FileAuditSearch','2006-10-05 20:54:40'),(63,'SQL Process List',3,6,'sql_admin.php','sql_processlist','2007-02-14 21:33:25'),(64,'Systems',3,5,'systems.php','systems_edit','2007-02-14 21:31:50'),(65,'Alert Group Admin',3,10,'alert_admin.php','alert_group_admin','2007-02-28 20:44:44'),(66,'junk',5,10,'junk','junk','2007-02-16 19:26:34'),(67,'Alert User Admin',3,11,'alert_admin.php','alert_user_admin','2007-02-28 20:44:33'),(68,'Computer Groups Admin',3,12,'systems.php','computer_group_admin','2007-02-28 20:44:20'),(69,'Alert Admin',3,9,'alert_admin.php','alert_admin','2007-06-21 06:41:23'),(70,'MANAGE_CARVER',8,5,'manage_carver.php','manage_carver','2007-04-21 17:41:21');
/*!40000 ALTER TABLE `menuoption` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `orggroup`
--

DROP TABLE IF EXISTS `orggroup`;
CREATE TABLE `orggroup` (
  `OrgGroupID` int(10) unsigned NOT NULL auto_increment,
  `OrgGroupTypeID` int(10) unsigned NOT NULL default '0',
  `IdentifyingOrgUnitID` int(10) unsigned NOT NULL default '0',
  `LatestChangeStamp` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  PRIMARY KEY  (`OrgGroupID`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

--
-- Dumping data for table `orggroup`
--

LOCK TABLES `orggroup` WRITE;
/*!40000 ALTER TABLE `orggroup` DISABLE KEYS */;
/*!40000 ALTER TABLE `orggroup` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `orggroupmember`
--

DROP TABLE IF EXISTS `orggroupmember`;
CREATE TABLE `orggroupmember` (
  `OrgGroupMemberID` int(10) unsigned NOT NULL auto_increment,
  `OrgGroupID` int(10) unsigned NOT NULL default '0',
  `MemberOrgUnitID` int(10) unsigned NOT NULL default '0',
  `LatestChangeStamp` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  PRIMARY KEY  (`OrgGroupMemberID`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

--
-- Dumping data for table `orggroupmember`
--

LOCK TABLES `orggroupmember` WRITE;
/*!40000 ALTER TABLE `orggroupmember` DISABLE KEYS */;
/*!40000 ALTER TABLE `orggroupmember` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `orggrouptype`
--

DROP TABLE IF EXISTS `orggrouptype`;
CREATE TABLE `orggrouptype` (
  `OrgGroupTypeID` int(10) unsigned NOT NULL auto_increment,
  `OrgGroupTypeName` char(40) collate utf8_unicode_ci NOT NULL default '',
  `IdentifyingOrgUnitTypeID` int(10) unsigned NOT NULL default '0',
  `MemberOrgUnitTypeID` int(10) unsigned NOT NULL default '0',
  `LatestChangeStamp` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  PRIMARY KEY  (`OrgGroupTypeID`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

--
-- Dumping data for table `orggrouptype`
--

LOCK TABLES `orggrouptype` WRITE;
/*!40000 ALTER TABLE `orggrouptype` DISABLE KEYS */;
/*!40000 ALTER TABLE `orggrouptype` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `orgunit`
--

DROP TABLE IF EXISTS `orgunit`;
CREATE TABLE `orgunit` (
  `OrgUnitID` int(10) unsigned NOT NULL auto_increment,
  `OrgUnitTypeID` int(10) unsigned NOT NULL default '0',
  `OrgUnitName` char(40) collate utf8_unicode_ci NOT NULL default '',
  `DomainLoginName` char(15) collate utf8_unicode_ci NOT NULL default '',
  `OrgUnitUserKey` char(10) collate utf8_unicode_ci NOT NULL default '',
  `DefaultLanguageID` int(10) unsigned NOT NULL default '0',
  `SourceA2KSystemID` int(10) unsigned NOT NULL default '0',
  `LatestChangeStamp` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  PRIMARY KEY  (`OrgUnitID`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

--
-- Dumping data for table `orgunit`
--

LOCK TABLES `orgunit` WRITE;
/*!40000 ALTER TABLE `orgunit` DISABLE KEYS */;
/*!40000 ALTER TABLE `orgunit` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `orgunittype`
--

DROP TABLE IF EXISTS `orgunittype`;
CREATE TABLE `orgunittype` (
  `OrgUnitTypeID` int(10) unsigned NOT NULL auto_increment,
  `OrgUnitTypeName` char(40) collate utf8_unicode_ci NOT NULL default '',
  `OrgUnitUserKeyLabel` char(40) collate utf8_unicode_ci NOT NULL default '',
  `LoginDomainFlag` tinyint(1) NOT NULL default '0',
  `UserNameLabel` char(40) collate utf8_unicode_ci NOT NULL default '',
  `MaxUserNum` smallint(5) unsigned NOT NULL default '0',
  `LatestChangeStamp` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  PRIMARY KEY  (`OrgUnitTypeID`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

--
-- Dumping data for table `orgunittype`
--

LOCK TABLES `orgunittype` WRITE;
/*!40000 ALTER TABLE `orgunittype` DISABLE KEYS */;
/*!40000 ALTER TABLE `orgunittype` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `role`
--

DROP TABLE IF EXISTS `role`;
CREATE TABLE `role` (
  `RoleID` int(10) unsigned NOT NULL auto_increment,
  `RoleName` char(40) collate utf8_unicode_ci NOT NULL default '',
  `RoleDescr` char(128) collate utf8_unicode_ci NOT NULL default '',
  `RoleOrgUnitTypeID` int(10) unsigned NOT NULL default '0',
  `UserRoleOrgUnitTypeID` int(10) unsigned NOT NULL default '0',
  `LatestChangeStamp` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  PRIMARY KEY  (`RoleID`)
) ENGINE=MyISAM AUTO_INCREMENT=7 DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

--
-- Dumping data for table `role`
--

LOCK TABLES `role` WRITE;
/*!40000 ALTER TABLE `role` DISABLE KEYS */;
INSERT INTO `role` VALUES (1,'devel','Software Developer',0,0,'2005-06-29 20:10:49'),(2,'admin','Administrator',0,0,'2005-06-29 20:11:15'),(3,'test','Test Role',0,0,'2005-07-05 18:18:08'),(4,'user1','General Users',0,0,'2005-07-05 18:18:08'),(5,'user2','Security Users',0,0,'2005-07-05 18:18:50'),(6,'user3','Oversight Users',0,0,'2005-07-05 18:18:50');
/*!40000 ALTER TABLE `role` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `rolemenuoption`
--

DROP TABLE IF EXISTS `rolemenuoption`;
CREATE TABLE `rolemenuoption` (
  `RoleMenuOptionID` int(10) unsigned NOT NULL auto_increment,
  `RoleID` int(10) unsigned NOT NULL default '0',
  `MenuOptionID` int(10) unsigned NOT NULL default '0',
  `LatestChangeStamp` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  PRIMARY KEY  (`RoleMenuOptionID`)
) ENGINE=MyISAM AUTO_INCREMENT=135 DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

--
-- Dumping data for table `rolemenuoption`
--

LOCK TABLES `rolemenuoption` WRITE;
/*!40000 ALTER TABLE `rolemenuoption` DISABLE KEYS */;
INSERT INTO `rolemenuoption` VALUES (42,1,8,'2005-07-27 14:05:04'),(2,1,1,'2005-06-29 20:20:34'),(3,1,2,'2005-06-29 20:20:34'),(4,1,3,'2005-06-29 20:20:34'),(5,1,4,'2005-06-29 20:20:34'),(6,1,5,'2005-06-29 20:20:34'),(7,1,6,'2005-06-29 20:20:34'),(8,1,7,'2005-06-29 20:21:07'),(9,1,10,'2005-06-30 12:35:38'),(69,1,11,'2005-10-20 15:45:15'),(43,1,12,'2005-07-27 14:05:19'),(45,1,13,'2005-07-27 14:05:52'),(46,1,14,'2005-07-27 14:06:02'),(47,1,21,'2005-07-27 14:06:15'),(48,1,22,'2005-07-27 14:06:32'),(49,1,23,'2005-07-27 14:06:45'),(50,1,24,'2005-07-27 14:06:57'),(70,1,25,'2005-10-20 15:45:30'),(52,1,26,'2005-07-27 14:07:38'),(41,1,41,'2005-07-27 13:58:05'),(40,3,28,'2005-07-07 13:04:00'),(39,1,28,'2005-07-07 13:04:00'),(23,1,29,'2005-07-06 19:29:54'),(24,1,30,'2005-07-06 19:30:08'),(25,1,31,'2005-07-06 19:33:36'),(26,1,32,'2005-07-06 19:33:57'),(27,1,33,'2005-07-06 19:36:34'),(28,1,34,'2005-07-06 19:38:52'),(29,1,35,'2005-07-06 19:48:44'),(30,1,36,'2005-07-06 19:49:12'),(31,1,37,'2005-07-06 19:49:24'),(32,1,38,'2005-07-06 19:49:51'),(33,1,39,'2005-07-06 19:53:15'),(34,5,39,'2005-07-06 19:53:15'),(54,2,40,'2005-07-27 14:07:49'),(53,1,40,'2005-07-27 14:07:49'),(78,1,42,'2005-10-24 19:08:20'),(58,1,43,'2005-07-27 19:35:56'),(62,1,44,'2005-08-11 19:08:44'),(63,1,46,'2005-08-11 19:14:02'),(119,1,47,'2007-02-19 19:26:53'),(118,1,48,'2007-02-19 19:26:40'),(73,1,49,'2005-10-24 18:44:17'),(105,1,50,'2007-02-14 21:07:47'),(75,1,52,'2005-10-24 18:57:33'),(79,1,53,'2005-10-24 19:10:32'),(81,1,54,'2005-10-24 19:13:07'),(83,1,55,'2005-10-24 19:19:44'),(84,1,56,'2005-10-24 19:21:25'),(85,1,57,'2006-05-29 12:20:16'),(86,2,57,'2006-05-29 12:20:16'),(87,5,57,'2006-05-29 12:20:16'),(88,6,57,'2006-05-29 12:20:16'),(89,1,59,'2006-05-29 12:29:41'),(90,2,59,'2006-05-29 12:29:41'),(91,5,59,'2006-05-29 12:29:41'),(92,6,59,'2006-05-29 12:29:41'),(93,1,60,'2006-05-29 12:31:35'),(94,2,60,'2006-05-29 12:31:35'),(95,5,60,'2006-05-29 12:31:35'),(96,6,60,'2006-05-29 12:31:35'),(97,2,58,'2006-05-29 12:33:18'),(98,5,58,'2006-05-29 12:33:18'),(99,6,58,'2006-05-29 12:33:18'),(100,1,58,'2006-05-29 12:34:37'),(101,1,61,'2006-06-15 18:29:49'),(103,1,62,'2006-10-05 20:54:40'),(107,1,63,'2007-02-14 21:33:25'),(106,1,64,'2007-02-14 21:31:50'),(116,1,66,'2007-02-16 19:26:34'),(128,1,65,'2007-02-28 20:44:44'),(127,1,67,'2007-02-28 20:44:33'),(126,1,68,'2007-02-28 20:44:20'),(130,1,69,'2007-02-28 20:45:56'),(131,1,70,'2007-04-21 17:41:21'),(132,2,70,'2007-04-21 17:41:21'),(133,5,70,'2007-04-21 17:41:21'),(134,6,70,'2007-04-21 17:41:21');
/*!40000 ALTER TABLE `rolemenuoption` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `session`
--

DROP TABLE IF EXISTS `session`;
CREATE TABLE `session` (
  `SessionID` binary(64) NOT NULL default '\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0',
  `UserID` int(10) unsigned NOT NULL default '0',
  `IPAddress` char(15) collate utf8_unicode_ci NOT NULL default '',
  `ExpireTime` int(10) unsigned NOT NULL default '0',
  `LastOptionID` int(10) unsigned NOT NULL default '0',
  PRIMARY KEY  (`SessionID`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

--
-- Dumping data for table `session`
--

LOCK TABLES `session` WRITE;
/*!40000 ALTER TABLE `session` DISABLE KEYS */;
INSERT INTO `session` VALUES ('gB9LPnY2S4wFfusoncSt6afCDVQ2Xg9ljQaYEtIqdKJ6YxQx9n~9zccsHxaRhfEY',1,'192.168.33.1',1183137922,0),('15.S~_PAk73TY_RWNsVqaofF50ziGDSBWkLd9Bjs9kb0e6s2nIHfTM10v_YSGrF~',2,'10.245.31.158',1163887791,0),('OrTw5lwItQMo|IlmMB7n4oDmeP2Xqispt$8o8A5ExybugjHSykDtszWSlJ$vH1sM',32,'10.1.194.102',1122459828,0),('5y79KbLsPUQru0SkDTnKqVB3$YZTQjB~qoIJLluWoJmNd|zUvUW8gkeO1FW5WaKj',8,'10.1.194.102',1120127637,0),('t2gCJTsDROFlmd84.SJX3Ug2I$w9|r.dL23o4U6Foslzjo5Zo5f94E6.YZfYdFi|',12,'10.1.194.102',1120128802,0),('8FMv3u~9PQbbng|K~r_aWOp|JG75H4RGJ5lcjv$7e|nYcOuRybboR4x9ospL4C3O',13,'10.1.194.102',1120140832,0),('Vdy6HZQpngm|x6OfiN2kHQVT|VWJKQ4HFKR~mx0I$PAbQYetHGTq46Z|Lu6a7xvF',14,'10.1.194.102',1120141966,0),('4XOZJtEBMPriT9VX|F0|xAsYNMi7QlsFSqG2r7QeDIbo20_aFKXejABd~wt~Mbvy',19,'10.1.194.102',1120149744,0),('MvXf9W|xBIM_cW6QSAndEV4ugmblfLrF5O4RhWMw1FTkyZewYpM4K~Uj6LxCKX9W',22,'10.1.194.102',1120226441,0),('VBmyTm4Kmy6thHF$Mm4ZxJP_hQE~5W~qeAPpdDwsfVRBSRV2J8dS.C70U8ySkHuw',33,'10.1.56.113',1141307184,0),('.2SaN_ZIwM4N|Rd55KzlYrpm6xE0H.x6.Im~uxLhhgB1jd4.hmJemr~z2Grlhwer',34,'10.1.194.98',1142946878,0),('LtpavdNDafJA2obDH3LUqWfW0seQxvHaQn4.7Ycf1vNEOZETaCg4qiFKbof6ML6C',35,'10.1.182.95',1169597068,0),('Bi5wKpIm92YUOhB2n24c2l8vb68i9kWDgWTWS2Q$oj9K29yJg5xyinUaHQY9vAyf',3,'127.0.0.1',1173735943,0),('_M6WwkpAWFhPIaQNKXzdkiDomiB2_oAcCz|P2eqZ_q2owAYmRGTzu|Rcj3u5HKVe',6,'10.1.195.113',1173723972,0);
/*!40000 ALTER TABLE `session` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `system`
--

DROP TABLE IF EXISTS `system`;
CREATE TABLE `system` (
  `SystemID` int(10) unsigned NOT NULL auto_increment,
  `AttributeName` char(15) collate utf8_unicode_ci NOT NULL default '',
  `AttributeValue` char(40) collate utf8_unicode_ci NOT NULL default '',
  `LatestChangeStamp` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  PRIMARY KEY  (`SystemID`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

--
-- Dumping data for table `system`
--

LOCK TABLES `system` WRITE;
/*!40000 ALTER TABLE `system` DISABLE KEYS */;
/*!40000 ALTER TABLE `system` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `userrole`
--

DROP TABLE IF EXISTS `userrole`;
CREATE TABLE `userrole` (
  `UserRoleID` int(10) unsigned NOT NULL auto_increment,
  `UserID` int(10) unsigned NOT NULL default '0',
  `RoleID` int(10) unsigned NOT NULL default '0',
  `OrgUnitID` int(10) unsigned NOT NULL default '0',
  `CreatedDatetime` datetime NOT NULL default '0000-00-00 00:00:00',
  `DeletedDatetime` datetime NOT NULL default '0000-00-00 00:00:00',
  `LatestChangeUserID` int(10) unsigned NOT NULL default '0',
  `LatestChangeStamp` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  PRIMARY KEY  (`UserRoleID`)
) ENGINE=MyISAM AUTO_INCREMENT=69 DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

--
-- Dumping data for table `userrole`
--

LOCK TABLES `userrole` WRITE;
/*!40000 ALTER TABLE `userrole` DISABLE KEYS */;
INSERT INTO `userrole` VALUES (49,3,1,0,'0000-00-00 00:00:00','0000-00-00 00:00:00',0,'2005-07-02 15:37:58'),(50,2,1,0,'0000-00-00 00:00:00','0000-00-00 00:00:00',0,'2005-07-02 15:38:23'),(51,1,1,0,'0000-00-00 00:00:00','0000-00-00 00:00:00',3,'2005-07-02 15:40:50'),(52,6,1,0,'0000-00-00 00:00:00','0000-00-00 00:00:00',3,'2005-07-02 15:40:57'),(53,23,1,0,'0000-00-00 00:00:00','0000-00-00 00:00:00',3,'2005-07-16 13:03:11'),(66,34,1,0,'0000-00-00 00:00:00','0000-00-00 00:00:00',0,'2006-03-21 14:05:31'),(64,32,1,0,'0000-00-00 00:00:00','0000-00-00 00:00:00',3,'2005-07-27 14:01:06'),(56,26,4,0,'0000-00-00 00:00:00','0000-00-00 00:00:00',3,'2005-09-22 14:57:56'),(63,22,3,0,'0000-00-00 00:00:00','0000-00-00 00:00:00',3,'2005-07-22 19:31:33'),(65,33,1,0,'0000-00-00 00:00:00','0000-00-00 00:00:00',3,'2005-09-22 00:20:01'),(59,29,5,0,'0000-00-00 00:00:00','0000-00-00 00:00:00',0,'2005-07-22 12:47:36'),(60,30,5,0,'0000-00-00 00:00:00','0000-00-00 00:00:00',0,'2005-07-22 12:55:37'),(62,21,3,0,'0000-00-00 00:00:00','0000-00-00 00:00:00',3,'2005-07-22 17:48:52'),(67,35,1,0,'0000-00-00 00:00:00','0000-00-00 00:00:00',0,'2006-06-02 13:43:49'),(68,36,1,0,'0000-00-00 00:00:00','0000-00-00 00:00:00',0,'2006-06-02 13:53:16'),(1,1,1,0,'0000-00-00 00:00:00','0000-00-00 00:00:00',0,'2005-07-02 22:40:57'),(2,1,2,0,'0000-00-00 00:00:00','0000-00-00 00:00:00',0,'2005-07-02 22:40:57');
/*!40000 ALTER TABLE `userrole` ENABLE KEYS */;
UNLOCK TABLES;

--
-- Table structure for table `userstat`
--

DROP TABLE IF EXISTS `userstat`;
CREATE TABLE `userstat` (
  `UserStatID` int(10) unsigned NOT NULL auto_increment,
  `UserID` int(10) unsigned NOT NULL default '0',
  `LoginCount` int(10) unsigned NOT NULL default '0',
  `LatestLoginStamp` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  PRIMARY KEY  (`UserStatID`)
) ENGINE=MyISAM AUTO_INCREMENT=18 DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

--
-- Dumping data for table `userstat`
--

LOCK TABLES `userstat` WRITE;
/*!40000 ALTER TABLE `userstat` DISABLE KEYS */;
INSERT INTO `userstat` VALUES (1,1,128,'2007-06-29 14:49:49'),(2,2,167,'2006-11-18 19:36:19'),(3,6,154,'2007-03-12 15:22:27'),(4,8,1,'2005-06-30 14:18:57'),(5,12,1,'2005-06-30 14:38:22'),(6,13,1,'2005-06-30 17:58:52'),(7,14,1,'2005-06-30 18:01:56'),(8,19,1,'2005-06-30 20:27:24'),(9,3,424,'2007-03-12 13:29:05'),(10,22,3,'2005-07-01 17:41:56'),(11,23,25,'2006-02-01 20:19:50'),(12,32,2,'2005-07-27 14:01:15'),(13,33,12,'2006-03-02 15:47:40'),(14,34,2,'2006-03-21 15:43:20'),(15,35,17,'2007-01-23 21:21:34'),(16,36,1,'2006-06-02 13:53:27'),(17,37,7,'2007-01-23 20:16:29');
/*!40000 ALTER TABLE `userstat` ENABLE KEYS */;
UNLOCK TABLES;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2007-07-02 19:06:02
--
-- Dumping data for table `user`
--
/*!40000 ALTER TABLE `user` DISABLE KEYS */;
LOCK TABLES `user` WRITE;
INSERT INTO `user` VALUES (1,'admin','70ccd9007338d6d81dd3b6271621b9cf9a97ea00','The','Administrator','',0,'2005-06-30 20:41:19','0000-00-00 00:00:00',3,'2007-03-13 19:00:59');
UNLOCK TABLES;
/*!40000 ALTER TABLE `user` ENABLE KEYS */;
--
-- Dumping data for table `userrole`
--
/*!40000 ALTER TABLE `userrole` DISABLE KEYS */;
LOCK TABLES `userrole` WRITE;
INSERT INTO `userrole` VALUES (1,1,1,0,'0000-00-00 00:00:00','0000-00-00 00:00:00',0,'2005-07-02 15:40:57'),(2,1,2,0,'0000-00-00 00:00:00','0000-00-00 00:00:00',0,'2005-07-02 15:40:57');
UNLOCK TABLES;
/*!40000 ALTER TABLE `userrole` ENABLE KEYS */;

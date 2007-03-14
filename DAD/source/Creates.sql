-- MySQL dump 10.10
--
-- Host: 10.245.31.155    Database: dad
-- ------------------------------------------------------
-- Server version	5.0.21-community-nt

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
-- Current Database: `dad`
--

CREATE DATABASE /*!32312 IF NOT EXISTS*/ `dad` /*!40100 DEFAULT CHARACTER SET latin1 */;

USE `dad`;

--
-- Table structure for table `a2ksystem`
--

DROP TABLE IF EXISTS `a2ksystem`;
CREATE TABLE `a2ksystem` (
  `A2KSystemID` int(10) unsigned NOT NULL auto_increment,
  `BranchNum` int(11) NOT NULL default '0',
  `LatestTransferDatetime` datetime NOT NULL default '0000-00-00 00:00:00',
  `LatestChangeStamp` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  PRIMARY KEY  (`A2KSystemID`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

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
-- Table structure for table `dad_adm_alert`
--

DROP TABLE IF EXISTS `dad_adm_alert`;
CREATE TABLE `dad_adm_alert` (
  `id_dad_adm_alert` int(10) unsigned NOT NULL auto_increment,
  `id_dad_adm_computer_group` int(10) unsigned default NULL,
  `description` varchar(45) NOT NULL default '',
  `id_dad_adm_action` int(10) unsigned default NULL,
  `notes` varchar(200) default NULL,
  `calleractive` varchar(45) default NULL,
  `timeactive` int(10) unsigned default NULL,
  `active` tinyint(1) unsigned default NULL,
  `supress_interval` smallint(5) unsigned default NULL,
  `supress_criteria` int(10) unsigned default NULL,
  PRIMARY KEY  (`id_dad_adm_alert`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Table structure for table `dad_adm_alert_criteria`
--

DROP TABLE IF EXISTS `dad_adm_alert_criteria`;
CREATE TABLE `dad_adm_alert_criteria` (
  `id_dad_adm_alert_criteria` int(10) unsigned NOT NULL auto_increment,
  `id_dad_adm_alert` int(10) unsigned NOT NULL default '0',
  `field` varchar(45) NOT NULL default '',
  `criteria` varchar(150) NOT NULL default '',
  PRIMARY KEY  (`id_dad_adm_alert_criteria`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Table structure for table `dad_adm_alert_group`
--

DROP TABLE IF EXISTS `dad_adm_alert_group`;
CREATE TABLE `dad_adm_alert_group` (
  `id_dad_adm_alertgroup` smallint(5) unsigned NOT NULL auto_increment,
  `name` varchar(30) NOT NULL default '',
  `description` varchar(100) default '',
  `calleractive` varchar(45) NOT NULL default '',
  `timeactive` int(10) unsigned default NULL,
  PRIMARY KEY  (`id_dad_adm_alertgroup`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 ROW_FORMAT=DYNAMIC;

--
-- Table structure for table `dad_adm_alert_group_member`
--

DROP TABLE IF EXISTS `dad_adm_alert_group_member`;
CREATE TABLE `dad_adm_alert_group_member` (
  `id_dad_adm_alertgroup` smallint(5) unsigned NOT NULL default '0',
  `id_dad_adm_alertuser` int(10) unsigned NOT NULL default '0',
  `calleractive` varchar(45) NOT NULL default '',
  `timeactive` int(10) unsigned default NULL,
  KEY `idx_dad_adm_alertgroupmember_idperson` USING BTREE (`id_dad_adm_alertgroup`,`id_dad_adm_alertuser`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Table structure for table `dad_adm_alertuser`
--

DROP TABLE IF EXISTS `dad_adm_alertuser`;
CREATE TABLE `dad_adm_alertuser` (
  `id_dad_adm_alertuser` smallint(5) unsigned NOT NULL auto_increment,
  `employeeid` int(10) unsigned default NULL,
  `firstname` varchar(30) NOT NULL default '',
  `lastname` varchar(30) NOT NULL default '',
  `emailaddress` varchar(45) NOT NULL default '',
  `department` varchar(100) default '',
  `subdepartment` varchar(100) default NULL,
  `phone1` varchar(30) default NULL,
  `phone2` varchar(30) default NULL,
  `location` varchar(45) default NULL,
  `custom_entry` tinyint(3) unsigned default NULL,
  `calleractive` varchar(45) NOT NULL default '',
  `timeactive` int(10) unsigned default NULL,
  PRIMARY KEY  (`id_dad_adm_alertuser`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 ROW_FORMAT=DYNAMIC;

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
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Table structure for table `dad_adm_computer_group_member`
--

DROP TABLE IF EXISTS `dad_adm_computer_group_member`;
CREATE TABLE `dad_adm_computer_group_member` (
  `id_dad_adm_computer_group_member` int(10) unsigned NOT NULL auto_increment,
  `id_dad_adm_computer_group` int(10) unsigned default NULL,
  `system_id` int(10) unsigned default NULL,
  `calleractive` varchar(45) default NULL,
  `timeactive` int(11) default NULL,
  PRIMARY KEY  (`id_dad_adm_computer_group_member`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Table structure for table `dad_adm_grooming`
--

DROP TABLE IF EXISTS `dad_adm_grooming`;
CREATE TABLE `dad_adm_grooming` (
  `id_dad_adm_grooming` int(10) unsigned NOT NULL auto_increment,
  `object` varchar(200) default NULL,
  `ageinhours` decimal(10,2) unsigned default NULL,
  `calleractive` text,
  `timeactive` datetime default NULL,
  PRIMARY KEY  (`id_dad_adm_grooming`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

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
  `timeactive` int(10) unsigned default NULL,
  `user_name` varchar(45) default NULL,
  `distinguishedname` varchar(256) default NULL,
  `pword` varchar(100) default NULL,
  `times_to_run` int(10) unsigned default NULL,
  `times_ran` smallint(6) unsigned default NULL,
  `start_date` date default NULL,
  `start_time` time default NULL,
  `last_ran` int(10) unsigned default NULL,
  `min` varchar(45) default NULL,
  `hour` varchar(45) default NULL,
  `d_of_m` varchar(45) default NULL,
  `m_of_y` varchar(45) default NULL,
  `d_of_w` varchar(45) default NULL,
  PRIMARY KEY  (`id_dad_adm_job`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Table structure for table `dad_adm_log`
--

DROP TABLE IF EXISTS `dad_adm_log`;
CREATE TABLE `dad_adm_log` (
  `id_dad_adm_log` int(10) unsigned NOT NULL auto_increment,
  `id_dad_adm_logtype` int(10) unsigned NOT NULL default '0',
  `message` text,
  `eventsource` varchar(200) default NULL,
  `eventtime` datetime default NULL,
  `jobstarttime` datetime default NULL,
  `jobstoptime` datetime default NULL,
  `acknowledged` tinyint(1) unsigned NOT NULL default '0',
  PRIMARY KEY  (`id_dad_adm_log`),
  KEY `idx_dad_adm_log_idlogtype` USING BTREE (`id_dad_adm_logtype`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Table structure for table `dad_adm_logtype`
--

DROP TABLE IF EXISTS `dad_adm_logtype`;
CREATE TABLE `dad_adm_logtype` (
  `id_dad_adm_logtype` int(10) unsigned NOT NULL default '0',
  `description` varchar(50) default NULL,
  PRIMARY KEY  (`id_dad_adm_logtype`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 ROW_FORMAT=DYNAMIC;

--
-- Table structure for table `dad_cl_classification`
--

DROP TABLE IF EXISTS `dad_cl_classification`;
CREATE TABLE `dad_cl_classification` (
  `id_dad_cl_classification` tinyint(4) unsigned NOT NULL default '0',
  `description` text,
  `name` varchar(20) default NULL,
  `color` varchar(20) default NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Table structure for table `dad_ds_groupmembership`
--

DROP TABLE IF EXISTS `dad_ds_groupmembership`;
CREATE TABLE `dad_ds_groupmembership` (
  `id` bigint(20) unsigned NOT NULL auto_increment,
  `objectsid_dad_ds_object_group` varchar(100) default NULL,
  `objectsid_dad_ds_object_member` varchar(100) default NULL,
  `domain` varchar(25) default NULL,
  `activeyesno` tinyint(1) unsigned default NULL,
  `calleractive` varchar(255) default NULL,
  `timeactive` datetime default NULL,
  `callerinactive` varchar(255) default NULL,
  `timeinactive` datetime default NULL,
  PRIMARY KEY  (`id`),
  KEY `idx_dad_ds_groupmembership_idgroup` USING BTREE (`objectsid_dad_ds_object_group`,`objectsid_dad_ds_object_member`,`activeyesno`),
  KEY `idx_dad_ds_groupmembership_idmember` USING BTREE (`objectsid_dad_ds_object_member`,`objectsid_dad_ds_object_group`,`activeyesno`),
  KEY `idx_dad_ds_groupmembership_activeyesno` USING BTREE (`activeyesno`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Table structure for table `dad_ds_groupmembership_h`
--

DROP TABLE IF EXISTS `dad_ds_groupmembership_h`;
CREATE TABLE `dad_ds_groupmembership_h` (
  `id` bigint(20) unsigned default NULL,
  `objectsid_dad_ds_object_group` varchar(100) default NULL,
  `objectsid_dad_ds_object_member` varchar(100) default NULL,
  `domain` varchar(25) default NULL,
  `activeyesno` tinyint(1) unsigned default NULL,
  `calleractive` varchar(255) default NULL,
  `timeactive` datetime default NULL,
  `callerinactive` varchar(255) default NULL,
  `timeinactive` datetime default NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Table structure for table `dad_ds_groupmembership_t`
--

DROP TABLE IF EXISTS `dad_ds_groupmembership_t`;
CREATE TABLE `dad_ds_groupmembership_t` (
  `objectsid_dad_ds_object_group` varchar(100) default NULL,
  `objectsid_dad_ds_object_member` varchar(100) default NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Table structure for table `dad_ds_object`
--

DROP TABLE IF EXISTS `dad_ds_object`;
CREATE TABLE `dad_ds_object` (
  `id` bigint(20) unsigned NOT NULL auto_increment,
  `objectsid` varchar(100) default NULL,
  `querytime` datetime NOT NULL default '0000-00-00 00:00:00',
  `samaccountname` varchar(255) default NULL,
  `whenchanged` datetime default NULL,
  `samaccounttype` int(11) default NULL,
  `objectclass` varchar(200) default NULL,
  `info` text,
  `employeeid` int(11) default NULL,
  `accountexpires` datetime default NULL,
  `cn` varchar(200) default NULL,
  `useraccountcontrol` int(11) default NULL,
  `pwdlastset` datetime default NULL,
  `description` varchar(255) default NULL,
  `distinguishedname` text,
  `whencreated` datetime default NULL,
  `displayname` varchar(255) default NULL,
  `objectguid` varchar(36) default NULL,
  PRIMARY KEY  (`id`),
  UNIQUE KEY `id` (`id`),
  KEY `idx_dad_ds_object_objectsid` USING BTREE (`objectsid`,`samaccountname`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Table structure for table `dad_ds_object_cl`
--

DROP TABLE IF EXISTS `dad_ds_object_cl`;
CREATE TABLE `dad_ds_object_cl` (
  `id` int(10) unsigned NOT NULL auto_increment,
  `sid_dad_ds_object` varchar(100) default NULL,
  `id_dad_cl_classification` tinyint(4) default NULL,
  `id_dad_adm_action` smallint(5) unsigned default NULL,
  `id_dad_adm_alertgroup` smallint(5) unsigned default NULL,
  `calleractive` varchar(45) NOT NULL default '',
  `timeactive` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`id`),
  KEY `idx_dad_ds_object_cl_idobject` USING BTREE (`sid_dad_ds_object`,`id_dad_adm_action`,`id_dad_adm_alertgroup`,`id_dad_cl_classification`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Table structure for table `dad_ds_samaccounttype`
--

DROP TABLE IF EXISTS `dad_ds_samaccounttype`;
CREATE TABLE `dad_ds_samaccounttype` (
  `id` int(11) NOT NULL auto_increment,
  `samaccounttype` int(11) default NULL,
  `samaccounttypehex` varchar(12) default NULL,
  `constantname` varchar(35) default NULL,
  `description` varchar(50) default NULL,
  `genericdescription` varchar(20) default NULL,
  PRIMARY KEY  (`id`),
  KEY `idx_dad_ds_samaccounttype_samaccounttype` USING BTREE (`samaccounttype`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Table structure for table `dad_ds_wks`
--

DROP TABLE IF EXISTS `dad_ds_wks`;
CREATE TABLE `dad_ds_wks` (
  `id_dad_ds_wks` smallint(5) unsigned NOT NULL auto_increment,
  `objectsid` varchar(255) default NULL,
  `samaccountname` varchar(255) default NULL,
  `displayname` varchar(255) default NULL,
  `description` text,
  PRIMARY KEY  (`id_dad_ds_wks`),
  KEY `idx_dad_ds_wks` USING BTREE (`id_dad_ds_wks`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Table structure for table `dad_event_log_types`
--

DROP TABLE IF EXISTS `dad_event_log_types`;
CREATE TABLE `dad_event_log_types` (
  `Event_Log_Type_ID` int(10) unsigned NOT NULL auto_increment,
  `Log_Type` varchar(45) NOT NULL,
  `Log_Type_Value` int(10) unsigned NOT NULL,
  PRIMARY KEY  (`Event_Log_Type_ID`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COMMENT='Used to map event log types to binary values';

--
-- Table structure for table `dad_fs_alertgroup`
--

DROP TABLE IF EXISTS `dad_fs_alertgroup`;
CREATE TABLE `dad_fs_alertgroup` (
  `id` bigint(20) unsigned NOT NULL auto_increment,
  `id_dad_fs_path` int(10) unsigned default NULL,
  `id_dad_adm_alertgroup` smallint(5) unsigned default NULL,
  `calleractive` varchar(45) default NULL,
  `timeactive` timestamp NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`id`),
  KEY `idx_dad_fs_path_alertgroup_id_dad_fs_path` USING BTREE (`id_dad_fs_path`,`id_dad_adm_alertgroup`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Table structure for table `dad_fs_dacl`
--

DROP TABLE IF EXISTS `dad_fs_dacl`;
CREATE TABLE `dad_fs_dacl` (
  `id` smallint(5) unsigned NOT NULL auto_increment,
  `dacl` varchar(20) NOT NULL default '',
  `description` text,
  `querytime` datetime default NULL,
  PRIMARY KEY  (`id`),
  KEY `idx_dad_fs_dacl_dacl` USING BTREE (`dacl`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Table structure for table `dad_fs_log`
--

DROP TABLE IF EXISTS `dad_fs_log`;
CREATE TABLE `dad_fs_log` (
  `id` smallint(5) unsigned NOT NULL auto_increment,
  `filename` varchar(255) default NULL,
  `filesize` int(10) unsigned default NULL,
  `datemodified` datetime default NULL,
  `querytime` datetime default NULL,
  `imported` tinyint(1) default NULL,
  PRIMARY KEY  (`id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Table structure for table `dad_fs_path`
--

DROP TABLE IF EXISTS `dad_fs_path`;
CREATE TABLE `dad_fs_path` (
  `id_dad_fs_path` int(10) unsigned NOT NULL auto_increment,
  `fullpath` text,
  `name` varchar(255) default '',
  `depth` int(10) unsigned default '0',
  `activeyesno` tinyint(1) unsigned default '0',
  `timeactive` datetime default '0000-00-00 00:00:00',
  `parent_id` int(10) unsigned default NULL,
  `timeinactive` datetime default '0000-00-00 00:00:00',
  PRIMARY KEY  (`id_dad_fs_path`),
  KEY `idx_dad_fs_path_fullpath` USING BTREE (`fullpath`(140),`depth`,`activeyesno`,`id_dad_fs_path`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Table structure for table `dad_fs_path_cl`
--

DROP TABLE IF EXISTS `dad_fs_path_cl`;
CREATE TABLE `dad_fs_path_cl` (
  `id` bigint(20) unsigned NOT NULL auto_increment,
  `id_dad_fs_path` int(10) unsigned default NULL,
  `id_dad_cl_classification_read` tinyint(4) unsigned default NULL,
  `id_dad_cl_classification_write` tinyint(4) unsigned default NULL,
  `id_dad_adm_action_read` smallint(5) unsigned default NULL,
  `id_dad_adm_action_write` smallint(5) unsigned default NULL,
  `calleractive` varchar(45) default NULL,
  `timeactive` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  PRIMARY KEY  (`id`),
  KEY `idx_dad_fs_path_cl_idpath` USING BTREE (`id_dad_fs_path`,`id_dad_cl_classification_read`,`id_dad_cl_classification_write`,`id_dad_adm_action_read`,`id_dad_adm_action_write`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Table structure for table `dad_fs_permission`
--

DROP TABLE IF EXISTS `dad_fs_permission`;
CREATE TABLE `dad_fs_permission` (
  `id` bigint(20) unsigned NOT NULL auto_increment,
  `id_dad_fs_path` int(10) unsigned NOT NULL default '0',
  `objectsid_dad_ds_object` varchar(100) default NULL,
  `dacl` varchar(20) default NULL,
  `querytime` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`id`),
  UNIQUE KEY `id` (`id`),
  KEY `idx_dad_fs_permission_id_dad_fs_path` USING BTREE (`id_dad_fs_path`,`objectsid_dad_ds_object`,`querytime`),
  KEY `idx_dad_fs_permission_objectsid_dad_ds_object` USING BTREE (`objectsid_dad_ds_object`,`id_dad_fs_path`,`querytime`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Table structure for table `dad_org_department`
--

DROP TABLE IF EXISTS `dad_org_department`;
CREATE TABLE `dad_org_department` (
  `deptname` varchar(100) NOT NULL default '',
  `iddept` int(10) unsigned NOT NULL default '0',
  `subdeptname` varchar(100) NOT NULL default '',
  `idsubdept` int(10) unsigned NOT NULL default '0',
  KEY `idx_dad_org_department_dept` USING BTREE (`iddept`),
  KEY `idx_dad_org_department_subdept` USING BTREE (`idsubdept`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Table structure for table `dad_org_person`
--

DROP TABLE IF EXISTS `dad_org_person`;
CREATE TABLE `dad_org_person` (
  `id_dad_org_person` int(10) unsigned NOT NULL default '0',
  `name` varchar(100) NOT NULL default '',
  `email` varchar(100) NOT NULL default '',
  `workphone` varchar(20) default NULL,
  `deptname` varchar(100) default NULL,
  `iddept` int(10) unsigned default NULL,
  `subdeptname` varchar(100) default NULL,
  `idsubdept` int(10) unsigned default NULL,
  `activeyesno` tinyint(1) unsigned default NULL,
  `timeinactive` datetime default NULL,
  KEY `idx_dad_org_person_id` USING BTREE (`id_dad_org_person`,`name`,`activeyesno`),
  KEY `idx_dad_org_person_name` USING BTREE (`name`,`id_dad_org_person`,`activeyesno`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Table structure for table `dad_sr_groupmembership`
--

DROP TABLE IF EXISTS `dad_sr_groupmembership`;
CREATE TABLE `dad_sr_groupmembership` (
  `id` int(10) unsigned NOT NULL auto_increment,
  `groupname` varchar(200) NOT NULL default '',
  `membername` varchar(200) NOT NULL default '',
  `server` varchar(20) NOT NULL default '',
  `querytime` datetime NOT NULL default '0000-00-00 00:00:00',
  PRIMARY KEY  (`id`),
  KEY `idx_dad_sr_groupmembership_querytime` USING BTREE (`querytime`),
  KEY `idx_dad_sr_groupmembership_groupname` (`groupname`,`membername`,`server`,`querytime`),
  KEY `idx_dad_sr_groupmembership_membername` (`membername`,`groupname`,`server`,`querytime`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Table structure for table `dad_sr_object`
--

DROP TABLE IF EXISTS `dad_sr_object`;
CREATE TABLE `dad_sr_object` (
  `sid_dad_sr_object` varchar(100) NOT NULL default '',
  `samaccountname` varchar(255) default NULL,
  `distinguishedname` varchar(255) default NULL,
  `description` varchar(255) default NULL,
  `samaccounttype` int(10) unsigned default NULL,
  `lastlogon` datetime default NULL,
  `pwdexpire` datetime default NULL,
  `pwdrequired` tinyint(1) unsigned default NULL,
  `disabled` tinyint(1) unsigned default NULL,
  `server` varchar(20) default NULL,
  `querytime` datetime default NULL,
  `id` int(11) NOT NULL auto_increment,
  PRIMARY KEY  (`id`),
  KEY `idx_dad_sr_object_id` USING BTREE (`sid_dad_sr_object`,`samaccountname`,`description`,`server`,`querytime`),
  KEY `idx_dad_sr_object_samaccountname` USING BTREE (`samaccountname`,`sid_dad_sr_object`,`server`,`querytime`),
  KEY `idx_dad_sr_object_description` USING BTREE (`description`,`sid_dad_sr_object`,`server`,`querytime`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Table structure for table `dad_sys_cis_imported`
--

DROP TABLE IF EXISTS `dad_sys_cis_imported`;
CREATE TABLE `dad_sys_cis_imported` (
  `CIS_Imported_ID` int(10) unsigned NOT NULL auto_increment,
  `Log_Name` varchar(255) NOT NULL,
  `System_Name` varchar(45) default NULL,
  `LastLogEntry` bigint(20) unsigned default NULL,
  PRIMARY KEY  (`CIS_Imported_ID`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Table structure for table `dad_sys_event_import_from`
--

DROP TABLE IF EXISTS `dad_sys_event_import_from`;
CREATE TABLE `dad_sys_event_import_from` (
  `ToImportID` int(10) unsigned NOT NULL auto_increment,
  `System_Name` varchar(80) NOT NULL,
  `Priority` int(10) unsigned NOT NULL,
  `Next_Run` int(10) unsigned NOT NULL,
  `Log_These` int(10) unsigned NOT NULL,
  PRIMARY KEY  (`ToImportID`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;

--
-- Table structure for table `dad_sys_event_stats`
--

DROP TABLE IF EXISTS `dad_sys_event_stats`;
CREATE TABLE `dad_sys_event_stats` (
  `Stats_ID` int(10) unsigned NOT NULL auto_increment,
  `System_Name` varchar(45) NOT NULL,
  `Service_Name` varchar(45) NOT NULL,
  `Stat_Type` int(10) unsigned NOT NULL,
  `Total_In_Log` int(10) unsigned NOT NULL,
  `Number_Inserted` int(10) unsigned NOT NULL,
  `Stat_Time` int(10) unsigned NOT NULL,
  PRIMARY KEY  (`Stats_ID`),
  KEY `Stats Type` (`Stat_Type`),
  KEY `Systems` (`System_Name`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COMMENT='Tracks event log gathering statistics';

--
-- Table structure for table `dad_sys_events`
--

DROP TABLE IF EXISTS `dad_sys_events`;
CREATE TABLE `dad_sys_events` (
  `dad_sys_events_id` int(10) unsigned NOT NULL auto_increment,
  `SystemID` mediumint(8) unsigned NOT NULL default '0',
  `ServiceID` mediumint(8) unsigned NOT NULL default '0',
  `TimeWritten` int(10) unsigned NOT NULL default '0',
  `TimeGenerated` int(10) unsigned NOT NULL default '0',
  `Source` char(255) NOT NULL default '',
  `Category` char(255) NOT NULL default '',
  `SID` char(64) character set latin1 NOT NULL default '',
  `Computer` char(255) NOT NULL default '',
  `EventID` mediumint(8) unsigned NOT NULL default '0',
  `EventType` tinyint(3) unsigned NOT NULL default '0',
  `Field_0` varchar(760) default NULL,
  `Field_1` varchar(760) default NULL,
  `Field_2` varchar(760) default NULL,
  `Field_3` varchar(760) default NULL,
  `Field_4` varchar(760) default NULL,
  `Field_5` varchar(760) default NULL,
  `Field_6` varchar(760) default NULL,
  `Field_7` varchar(760) default NULL,
  `Field_8` varchar(760) default NULL,
  `Field_9` varchar(760) default NULL,
  `Field_10` varchar(760) default NULL,
  `Field_11` varchar(760) default NULL,
  `Field_12` varchar(760) default NULL,
  `Field_13` varchar(760) default NULL,
  `Field_14` varchar(760) default NULL,
  `Field_15` varchar(760) default NULL,
  `Field_16` varchar(760) default NULL,
  `Field_17` varchar(760) default NULL,
  `Field_18` varchar(760) default NULL,
  `Field_19` varchar(760) default NULL,
  `Field_20` varchar(760) default NULL,
  `Field_21` varchar(760) default NULL,
  `Field_22` varchar(760) default NULL,
  `Field_23` varchar(760) default NULL,
  `Field_24` varchar(760) default NULL,
  `Field_25` varchar(760) default NULL,
  `idxID_Code` char(64) default NULL,
  `idxID_Kerb` char(64) default NULL,
  `idxID_NTLM` char(64) default NULL,
  PRIMARY KEY  (`dad_sys_events_id`),
  KEY `idxEventID` (`EventID`),
  KEY `idxSID` (`SID`),
  KEY `idxTimestamp` (`TimeGenerated`),
  KEY `idxIDbyCode` (`idxID_Code`(10)),
  KEY `idxIDbyKerb` (`idxID_Kerb`(15)),
  KEY `idxIDbyNTLM` (`idxID_NTLM`(10)),
  KEY `idxNTLMCode` (`Field_3`(15))
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COMMENT='Normalized Windows Events';

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
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COMMENT='Aging schedule for various Windows events';

--
-- Table structure for table `dad_sys_events_groomed`
--

DROP TABLE IF EXISTS `dad_sys_events_groomed`;
CREATE TABLE `dad_sys_events_groomed` (
  `Groomed_ID` int(10) unsigned NOT NULL auto_increment,
  `Timestamp` int(10) unsigned NOT NULL,
  `Event_ID` int(10) unsigned NOT NULL,
  `Number_Groomed` int(10) unsigned NOT NULL,
  PRIMARY KEY  (`Groomed_ID`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COMMENT='Groomed Event Stats';

--
-- Table structure for table `dad_sys_events_old`
--

DROP TABLE IF EXISTS `dad_sys_events_old`;
CREATE TABLE `dad_sys_events_old` (
  `Event_ID` bigint(20) unsigned NOT NULL auto_increment,
  `System_ID` int(10) unsigned NOT NULL default '0',
  `Timestamp` int(10) unsigned NOT NULL default '0',
  `Service_ID` int(10) unsigned NOT NULL default '0',
  `Field_0` varchar(64) default NULL,
  `Field_1` varchar(768) default NULL,
  `Field_2` varchar(64) default NULL,
  `Field_3` varchar(64) default NULL,
  `Field_4` varchar(768) default NULL,
  `Field_5` int(10) unsigned default '0',
  `Field_6` varchar(512) default NULL,
  `Field_7` varchar(64) default NULL,
  `Field_8` int(10) unsigned default '0',
  `Field_9` varchar(768) default NULL,
  `Field_10` varchar(512) default NULL,
  `Field_11` varchar(512) default NULL,
  `Field_12` varchar(768) default NULL,
  `Field_13` varchar(512) default NULL,
  `Field_14` varchar(64) default NULL,
  `Field_15` varchar(64) default NULL,
  `Field_16` varchar(64) default NULL,
  `Field_17` varchar(64) default NULL,
  `Field_18` varchar(64) default NULL,
  `Field_19` varchar(64) default NULL,
  `Field_20` varchar(64) default NULL,
  `Field_21` varchar(64) default NULL,
  `Field_22` varchar(64) default NULL,
  `Field_23` varchar(64) default NULL,
  `Field_24` varchar(64) default NULL,
  `Field_25` varchar(64) default NULL,
  PRIMARY KEY  (`Event_ID`),
  KEY `System` (`System_ID`),
  KEY `Timestamp` (`Timestamp`),
  KEY `Service` (`Service_ID`),
  KEY `WindowsEventID` (`Field_8`),
  KEY `Username` (`Field_10`(255)),
  KEY `TimeGenerated` (`Field_5`),
  KEY `LogonID_Filename` (`Field_12`(255)),
  KEY `SystemName` (`Field_7`),
  KEY `Username2` (`Field_11`(255)),
  KEY `KerberosMsgNumber` (`Field_13`(255)),
  KEY `KerberosMsgNumber2` (`Field_14`),
  KEY `FileType` (`Field_25`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COMMENT='Contains actual event data';

--
-- Table structure for table `dad_sys_field_descriptions`
--

DROP TABLE IF EXISTS `dad_sys_field_descriptions`;
CREATE TABLE `dad_sys_field_descriptions` (
  `Service_ID` int(10) unsigned NOT NULL,
  `Field_0_Name` varchar(45) NOT NULL default '',
  `Field_1_Name` varchar(45) NOT NULL default '',
  `Field_2_Name` varchar(45) NOT NULL default '',
  `Field_3_Name` varchar(45) NOT NULL default '',
  `Field_4_Name` varchar(45) NOT NULL default '',
  `Field_5_Name` varchar(45) NOT NULL default '',
  `Field_6_Name` varchar(45) NOT NULL default '',
  `Field_7_Name` varchar(45) NOT NULL default '',
  `Field_8_Name` varchar(45) NOT NULL default '',
  `Field_9_Name` varchar(45) NOT NULL default '',
  `Field_10_Name` varchar(45) NOT NULL,
  `Field_11_Name` varchar(45) NOT NULL,
  `Field_12_Name` varchar(45) NOT NULL,
  `Field_13_Name` varchar(45) NOT NULL,
  `Field_14_Name` varchar(45) NOT NULL,
  `Field_15_Name` varchar(45) NOT NULL,
  `Field_16_Name` varchar(45) NOT NULL,
  PRIMARY KEY  (`Service_ID`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COMMENT='Identifies general fields from the Event table';

--
-- Table structure for table `dad_sys_filtered_events`
--

DROP TABLE IF EXISTS `dad_sys_filtered_events`;
CREATE TABLE `dad_sys_filtered_events` (
  `Filtered_ID` int(10) unsigned NOT NULL auto_increment,
  `Event_ID` int(10) unsigned NOT NULL,
  `Description` varchar(45) NOT NULL,
  PRIMARY KEY  (`Filtered_ID`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COMMENT='Event IDs that are filtered from incoming logs';

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
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COMMENT='These queries are linked to by other queries, never called d';

--
-- Table structure for table `dad_sys_location`
--

DROP TABLE IF EXISTS `dad_sys_location`;
CREATE TABLE `dad_sys_location` (
  `Location_ID` int(10) unsigned NOT NULL auto_increment,
  `Location_Name` varchar(45) NOT NULL default '',
  `Contact_Information` varchar(80) NOT NULL default '',
  PRIMARY KEY  (`Location_ID`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COMMENT='Tracks system locations';

--
-- Table structure for table `dad_sys_os`
--

DROP TABLE IF EXISTS `dad_sys_os`;
CREATE TABLE `dad_sys_os` (
  `OS_ID` int(10) unsigned NOT NULL auto_increment,
  `OS_Name` varchar(45) NOT NULL default '',
  `Max_Patch_ID` int(10) unsigned NOT NULL default '0',
  PRIMARY KEY  (`OS_ID`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COMMENT='Operating Systems';

--
-- Table structure for table `dad_sys_patchlevels`
--

DROP TABLE IF EXISTS `dad_sys_patchlevels`;
CREATE TABLE `dad_sys_patchlevels` (
  `Patch_ID` int(10) unsigned NOT NULL auto_increment,
  `Patch_Date` datetime NOT NULL default '0000-00-00 00:00:00',
  `Patch_Name` varchar(45) NOT NULL default '',
  `OS_ID` int(10) unsigned NOT NULL default '0',
  PRIMARY KEY  (`Patch_ID`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COMMENT='Tracks OS Patch levels';

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
  PRIMARY KEY  (`Query_ID`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COMMENT='Used for stored queries';

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
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COMMENT='Tracks services reported on';

--
-- Table structure for table `dad_sys_systems`
--

DROP TABLE IF EXISTS `dad_sys_systems`;
CREATE TABLE `dad_sys_systems` (
  `System_ID` int(10) unsigned NOT NULL auto_increment,
  `System_Name` varchar(45) NOT NULL default '',
  `Location_ID` int(10) unsigned NOT NULL default '0',
  `Timezone` varchar(6) NOT NULL default '',
  `OS_ID` int(10) unsigned NOT NULL default '0',
  `Patch_ID` int(10) unsigned NOT NULL default '0',
  `IP_Address` varchar(15) NOT NULL default '',
  `Contact_Information` varchar(80) NOT NULL default '',
  PRIMARY KEY  (`System_ID`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COMMENT='Master system table';

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
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

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
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

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
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

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
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

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
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

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
-- Table structure for table `user`
--

DROP TABLE IF EXISTS `user`;
CREATE TABLE `user` (
  `UserID` int(10) unsigned NOT NULL auto_increment,
  `UserName` char(20) collate utf8_unicode_ci NOT NULL default '',
  `PasswordText` char(40) collate utf8_unicode_ci NOT NULL default '',
  `FirstName` char(40) collate utf8_unicode_ci NOT NULL default '',
  `LastName` char(40) collate utf8_unicode_ci NOT NULL default '',
  `EmailAddress` char(45) collate utf8_unicode_ci NOT NULL default '',
  `LanguageID` int(10) unsigned NOT NULL default '0',
  `CreatedDatetime` datetime NOT NULL default '0000-00-00 00:00:00',
  `DeletedDatetime` datetime NOT NULL default '0000-00-00 00:00:00',
  `LatestChangeUserID` int(10) unsigned NOT NULL default '0',
  `LatestChangeStamp` timestamp NOT NULL default CURRENT_TIMESTAMP on update CURRENT_TIMESTAMP,
  PRIMARY KEY  (`UserID`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

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
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;

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
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;


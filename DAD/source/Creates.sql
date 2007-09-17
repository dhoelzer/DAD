-- MySQL dump 10.13
--
-- Host: 127.0.0.1    Database: dad
-- ------------------------------------------------------
-- Server version	5.1.21-beta-community

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
-- Table structure for table `dad_adm_action`
--

DROP TABLE IF EXISTS `dad_adm_action`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_adm_action` (
  `id_dad_adm_action` mediumint(8) unsigned NOT NULL AUTO_INCREMENT,
  `abbreviation` char(1) DEFAULT NULL,
  `name` varchar(50) NOT NULL DEFAULT '',
  `description` text,
  `activeyesno` tinyint(1) unsigned NOT NULL DEFAULT '0',
  `timeactive` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  PRIMARY KEY (`id_dad_adm_action`)
) ENGINE=MyISAM AUTO_INCREMENT=11 DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_adm_alert`
--

DROP TABLE IF EXISTS `dad_adm_alert`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_adm_alert` (
  `id_dad_adm_alert` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `id_dad_adm_computer_group` int(10) unsigned DEFAULT NULL,
  `description` varchar(45) NOT NULL DEFAULT '',
  `id_dad_adm_action` int(10) unsigned DEFAULT NULL,
  `notes` varchar(200) DEFAULT NULL,
  `calleractive` varchar(45) DEFAULT NULL,
  `timeactive` int(10) unsigned DEFAULT NULL,
  `active` tinyint(1) unsigned DEFAULT NULL,
  `supress_interval` smallint(5) unsigned DEFAULT NULL,
  `id_dad_adm_alert_group` int(10) unsigned DEFAULT NULL,
  `id_dad_adm_alert_message` int(10) DEFAULT NULL,
  PRIMARY KEY (`id_dad_adm_alert`)
) ENGINE=MyISAM AUTO_INCREMENT=120 DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_adm_alert_criteria`
--

DROP TABLE IF EXISTS `dad_adm_alert_criteria`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_adm_alert_criteria` (
  `id_dad_adm_alert_criteria` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `id_dad_adm_alert` int(10) unsigned NOT NULL DEFAULT '0',
  `field` varchar(45) NOT NULL DEFAULT '',
  `criteria` varchar(150) NOT NULL DEFAULT '',
  PRIMARY KEY (`id_dad_adm_alert_criteria`)
) ENGINE=MyISAM AUTO_INCREMENT=1526 DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_adm_alert_group`
--

DROP TABLE IF EXISTS `dad_adm_alert_group`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_adm_alert_group` (
  `id_dad_adm_alertgroup` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `name` varchar(30) NOT NULL DEFAULT '',
  `description` varchar(100) DEFAULT '',
  `calleractive` varchar(45) NOT NULL DEFAULT '',
  `timeactive` int(10) unsigned DEFAULT NULL,
  PRIMARY KEY (`id_dad_adm_alertgroup`)
) ENGINE=MyISAM AUTO_INCREMENT=31 DEFAULT CHARSET=latin1 ROW_FORMAT=DYNAMIC;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_adm_alert_group_member`
--

DROP TABLE IF EXISTS `dad_adm_alert_group_member`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_adm_alert_group_member` (
  `id_dad_adm_alertgroup` smallint(5) unsigned NOT NULL DEFAULT '0',
  `id_dad_adm_alertuser` int(10) unsigned NOT NULL DEFAULT '0',
  `calleractive` varchar(45) NOT NULL DEFAULT '',
  `timeactive` int(10) unsigned DEFAULT NULL,
  PRIMARY KEY (`id_dad_adm_alertgroup`,`id_dad_adm_alertuser`),
  KEY `idx_dad_adm_alertgroupmember_idperson` (`id_dad_adm_alertgroup`,`id_dad_adm_alertuser`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_adm_alert_message`
--

DROP TABLE IF EXISTS `dad_adm_alert_message`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_adm_alert_message` (
  `id_dad_adm_alert_message` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `description` varchar(100) DEFAULT NULL,
  `subject` varchar(100) DEFAULT NULL,
  `body` varchar(1000) DEFAULT NULL,
  `template` tinyint(4) DEFAULT NULL,
  `timeactive` int(10) unsigned DEFAULT NULL,
  `calleractive` varchar(45) DEFAULT NULL,
  PRIMARY KEY (`id_dad_adm_alert_message`)
) ENGINE=MyISAM AUTO_INCREMENT=61 DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_adm_alert_supress`
--

DROP TABLE IF EXISTS `dad_adm_alert_supress`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_adm_alert_supress` (
  `id_dad_adm_alert_supress` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `id_dad_adm_alert` int(10) unsigned DEFAULT NULL,
  `field_name` varchar(100) DEFAULT NULL,
  PRIMARY KEY (`id_dad_adm_alert_supress`)
) ENGINE=MyISAM AUTO_INCREMENT=110 DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_adm_alertuser`
--

DROP TABLE IF EXISTS `dad_adm_alertuser`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_adm_alertuser` (
  `id_dad_adm_alertuser` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `employeeid` int(10) unsigned DEFAULT NULL,
  `firstname` varchar(30) NOT NULL DEFAULT '',
  `lastname` varchar(30) NOT NULL DEFAULT '',
  `emailaddress` varchar(45) NOT NULL DEFAULT '',
  `department` varchar(100) DEFAULT '',
  `subdepartment` varchar(100) DEFAULT NULL,
  `phone1` varchar(30) DEFAULT NULL,
  `phone2` varchar(30) DEFAULT NULL,
  `location` varchar(45) DEFAULT NULL,
  `custom_entry` tinyint(3) unsigned DEFAULT NULL,
  `calleractive` varchar(45) NOT NULL DEFAULT '',
  `timeactive` int(10) unsigned DEFAULT NULL,
  PRIMARY KEY (`id_dad_adm_alertuser`)
) ENGINE=MyISAM AUTO_INCREMENT=4555 DEFAULT CHARSET=latin1 ROW_FORMAT=DYNAMIC;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_adm_carvers`
--

DROP TABLE IF EXISTS `dad_adm_carvers`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_adm_carvers` (
  `dad_adm_carvers_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `match_rule` varchar(768) NOT NULL DEFAULT '',
  `carve_rule` varchar(768) NOT NULL DEFAULT '',
  `creator_id` int(10) unsigned NOT NULL DEFAULT '0',
  `last_edited_by` int(10) unsigned NOT NULL DEFAULT '0',
  `creation_date` int(10) unsigned NOT NULL DEFAULT '0',
  `last_edit_date` int(10) unsigned NOT NULL DEFAULT '0',
  `rule_name` varchar(45) NOT NULL DEFAULT '',
  PRIMARY KEY (`dad_adm_carvers_id`)
) ENGINE=MyISAM AUTO_INCREMENT=3 DEFAULT CHARSET=latin1 COMMENT='Contains matching and carving rules for log extraction';
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_adm_computer_group`
--

DROP TABLE IF EXISTS `dad_adm_computer_group`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_adm_computer_group` (
  `id_dad_adm_computer_group` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `group_name` varchar(45) DEFAULT NULL,
  `description` varchar(100) DEFAULT NULL,
  `calleractive` varchar(45) DEFAULT NULL,
  `timeactive` int(11) DEFAULT NULL,
  PRIMARY KEY (`id_dad_adm_computer_group`)
) ENGINE=MyISAM AUTO_INCREMENT=25 DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_adm_computer_group_member`
--

DROP TABLE IF EXISTS `dad_adm_computer_group_member`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_adm_computer_group_member` (
  `id_dad_adm_computer_group_member` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `id_dad_adm_computer_group` int(10) unsigned DEFAULT NULL,
  `system_id` int(10) unsigned DEFAULT NULL,
  `calleractive` varchar(45) DEFAULT NULL,
  `timeactive` int(11) DEFAULT NULL,
  PRIMARY KEY (`id_dad_adm_computer_group_member`)
) ENGINE=MyISAM AUTO_INCREMENT=279 DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_adm_grooming`
--

DROP TABLE IF EXISTS `dad_adm_grooming`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_adm_grooming` (
  `id_dad_adm_grooming` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `object` varchar(200) DEFAULT NULL,
  `ageinhours` decimal(10,2) unsigned DEFAULT NULL,
  `calleractive` text,
  `timeactive` datetime DEFAULT NULL,
  PRIMARY KEY (`id_dad_adm_grooming`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_adm_job`
--

DROP TABLE IF EXISTS `dad_adm_job`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_adm_job` (
  `id_dad_adm_job` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `descrip` varchar(256) DEFAULT NULL,
  `length` int(10) unsigned DEFAULT NULL,
  `job_type` varchar(15) DEFAULT NULL,
  `path` varchar(2048) DEFAULT NULL,
  `package_name` varchar(100) DEFAULT NULL,
  `calleractive` varchar(45) DEFAULT NULL,
  `next_start` int(10) unsigned DEFAULT NULL,
  `user_name` varchar(45) DEFAULT NULL,
  `distinguishedname` varchar(256) DEFAULT NULL,
  `pword` varchar(100) DEFAULT NULL,
  `times_to_run` int(10) unsigned DEFAULT NULL,
  `times_ran` smallint(6) unsigned DEFAULT NULL,
  `start_date` date DEFAULT NULL,
  `start_time` time DEFAULT NULL,
  `last_ran` int(10) unsigned DEFAULT NULL,
  `min` int(10) unsigned DEFAULT NULL,
  `hour` int(10) unsigned DEFAULT NULL,
  `day` int(10) unsigned DEFAULT NULL,
  `month` int(10) unsigned DEFAULT NULL,
  `is_running` tinyint(1) NOT NULL DEFAULT '0',
  `persistent` tinyint(1) NOT NULL DEFAULT '0',
  `argument_1` varchar(45) NOT NULL,
  PRIMARY KEY (`id_dad_adm_job`)
) ENGINE=MyISAM AUTO_INCREMENT=19 DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_adm_log`
--

DROP TABLE IF EXISTS `dad_adm_log`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_adm_log` (
  `id_dad_adm_log` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `id_dad_adm_logtype` int(10) unsigned NOT NULL DEFAULT '0',
  `message` text,
  `eventsource` varchar(200) DEFAULT NULL,
  `eventtime` datetime DEFAULT NULL,
  `jobstarttime` datetime DEFAULT NULL,
  `jobstoptime` datetime DEFAULT NULL,
  `acknowledged` tinyint(1) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`id_dad_adm_log`),
  KEY `idx_dad_adm_log_idlogtype` (`id_dad_adm_logtype`) USING BTREE
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_adm_logtype`
--

DROP TABLE IF EXISTS `dad_adm_logtype`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_adm_logtype` (
  `id_dad_adm_logtype` int(10) unsigned NOT NULL DEFAULT '0',
  `description` varchar(50) DEFAULT NULL,
  PRIMARY KEY (`id_dad_adm_logtype`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 ROW_FORMAT=DYNAMIC;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_alerts`
--

DROP TABLE IF EXISTS `dad_alerts`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_alerts` (
  `dad_alert_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `Alert_Time` int(10) unsigned NOT NULL DEFAULT '0',
  `Event_Time` int(10) unsigned NOT NULL DEFAULT '0',
  `Event_Data` varchar(200) NOT NULL DEFAULT '',
  `Acknowledged` tinyint(1) NOT NULL DEFAULT '0',
  `Acknowledged_by` int(10) unsigned NOT NULL DEFAULT '0',
  `Acknowledged_Time` int(10) unsigned NOT NULL DEFAULT '0',
  `Severity` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`dad_alert_id`),
  KEY `Acknowledged_idx` (`Acknowledged`),
  KEY `Time_idx` (`Alert_Time`)
) ENGINE=MyISAM AUTO_INCREMENT=2130 DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_cl_classification`
--

DROP TABLE IF EXISTS `dad_cl_classification`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_cl_classification` (
  `id_dad_cl_classification` tinyint(4) unsigned NOT NULL DEFAULT '0',
  `description` text,
  `name` varchar(20) DEFAULT NULL,
  `color` varchar(20) DEFAULT NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_ds_groupmembership`
--

DROP TABLE IF EXISTS `dad_ds_groupmembership`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_ds_groupmembership` (
  `dad_ds_groupmembership_id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `objectsid_dad_ds_object_group` varchar(100) DEFAULT NULL,
  `objectsid_dad_ds_object_member` varchar(100) DEFAULT NULL,
  `domain` varchar(25) DEFAULT NULL,
  `activeyesno` tinyint(1) unsigned DEFAULT NULL,
  `calleractive` varchar(255) DEFAULT NULL,
  `timeactive` datetime DEFAULT NULL,
  `callerinactive` varchar(255) DEFAULT NULL,
  `timeinactive` datetime DEFAULT NULL,
  PRIMARY KEY (`dad_ds_groupmembership_id`),
  KEY `idx_dad_ds_groupmembership_idgroup` (`objectsid_dad_ds_object_group`,`objectsid_dad_ds_object_member`,`activeyesno`) USING BTREE,
  KEY `idx_dad_ds_groupmembership_idmember` (`objectsid_dad_ds_object_member`,`objectsid_dad_ds_object_group`,`activeyesno`) USING BTREE,
  KEY `idx_dad_ds_groupmembership_activeyesno` (`activeyesno`) USING BTREE
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_ds_groupmembership_h`
--

DROP TABLE IF EXISTS `dad_ds_groupmembership_h`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_ds_groupmembership_h` (
  `dad_ds_groupmembership_h_id` bigint(20) unsigned DEFAULT NULL,
  `objectsid_dad_ds_object_group` varchar(100) DEFAULT NULL,
  `objectsid_dad_ds_object_member` varchar(100) DEFAULT NULL,
  `domain` varchar(25) DEFAULT NULL,
  `activeyesno` tinyint(1) unsigned DEFAULT NULL,
  `calleractive` varchar(255) DEFAULT NULL,
  `timeactive` datetime DEFAULT NULL,
  `callerinactive` varchar(255) DEFAULT NULL,
  `timeinactive` datetime DEFAULT NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_ds_groupmembership_t`
--

DROP TABLE IF EXISTS `dad_ds_groupmembership_t`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_ds_groupmembership_t` (
  `objectsid_dad_ds_object_group` varchar(100) DEFAULT NULL,
  `objectsid_dad_ds_object_member` varchar(100) DEFAULT NULL
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_ds_object`
--

DROP TABLE IF EXISTS `dad_ds_object`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_ds_object` (
  `dad_ds_object_id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `objectsid` varchar(100) DEFAULT NULL,
  `querytime` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `samaccountname` varchar(255) DEFAULT NULL,
  `whenchanged` datetime DEFAULT NULL,
  `samaccounttype` int(11) DEFAULT NULL,
  `objectclass` varchar(200) DEFAULT NULL,
  `info` text,
  `employeeid` int(11) DEFAULT NULL,
  `accountexpires` datetime DEFAULT NULL,
  `cn` varchar(200) DEFAULT NULL,
  `useraccountcontrol` int(11) DEFAULT NULL,
  `pwdlastset` datetime DEFAULT NULL,
  `description` varchar(255) DEFAULT NULL,
  `distinguishedname` text,
  `whencreated` datetime DEFAULT NULL,
  `displayname` varchar(255) DEFAULT NULL,
  `objectguid` varchar(36) DEFAULT NULL,
  PRIMARY KEY (`dad_ds_object_id`),
  UNIQUE KEY `id` (`dad_ds_object_id`),
  KEY `idx_dad_ds_object_objectsid` (`objectsid`,`samaccountname`) USING BTREE
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_ds_object_cl`
--

DROP TABLE IF EXISTS `dad_ds_object_cl`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_ds_object_cl` (
  `dad_ds_object_cl_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `sid_dad_ds_object` varchar(100) DEFAULT NULL,
  `id_dad_cl_classification` tinyint(4) DEFAULT NULL,
  `id_dad_adm_action` smallint(5) unsigned DEFAULT NULL,
  `id_dad_adm_alertgroup` smallint(5) unsigned DEFAULT NULL,
  `calleractive` varchar(45) NOT NULL DEFAULT '',
  `timeactive` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  PRIMARY KEY (`dad_ds_object_cl_id`),
  KEY `idx_dad_ds_object_cl_idobject` (`sid_dad_ds_object`,`id_dad_adm_action`,`id_dad_adm_alertgroup`,`id_dad_cl_classification`) USING BTREE
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_ds_samaccounttype`
--

DROP TABLE IF EXISTS `dad_ds_samaccounttype`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_ds_samaccounttype` (
  `dad_ds_samaccounttype_id` int(11) NOT NULL AUTO_INCREMENT,
  `samaccounttype` int(11) DEFAULT NULL,
  `samaccounttypehex` varchar(12) DEFAULT NULL,
  `constantname` varchar(35) DEFAULT NULL,
  `description` varchar(50) DEFAULT NULL,
  `genericdescription` varchar(20) DEFAULT NULL,
  PRIMARY KEY (`dad_ds_samaccounttype_id`),
  KEY `idx_dad_ds_samaccounttype_samaccounttype` (`samaccounttype`) USING BTREE
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_ds_wks`
--

DROP TABLE IF EXISTS `dad_ds_wks`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_ds_wks` (
  `id_dad_ds_wks` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `objectsid` varchar(255) DEFAULT NULL,
  `samaccountname` varchar(255) DEFAULT NULL,
  `displayname` varchar(255) DEFAULT NULL,
  `description` text,
  PRIMARY KEY (`id_dad_ds_wks`),
  KEY `idx_dad_ds_wks` (`id_dad_ds_wks`) USING BTREE
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_event_log_types`
--

DROP TABLE IF EXISTS `dad_event_log_types`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_event_log_types` (
  `Event_Log_Type_ID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `Log_Type` varchar(45) NOT NULL,
  `Log_Type_Value` int(10) unsigned NOT NULL,
  PRIMARY KEY (`Event_Log_Type_ID`)
) ENGINE=MyISAM AUTO_INCREMENT=8 DEFAULT CHARSET=utf8 COMMENT='Used to map event log types to binary values';
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_fs_alertgroup`
--

DROP TABLE IF EXISTS `dad_fs_alertgroup`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_fs_alertgroup` (
  `dad_fs_alertgroup_id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `id_dad_fs_path` int(10) unsigned DEFAULT NULL,
  `id_dad_adm_alertgroup` smallint(5) unsigned DEFAULT NULL,
  `calleractive` varchar(45) DEFAULT NULL,
  `timeactive` timestamp NOT NULL DEFAULT '0000-00-00 00:00:00',
  PRIMARY KEY (`dad_fs_alertgroup_id`),
  KEY `idx_dad_fs_path_alertgroup_id_dad_fs_path` (`id_dad_fs_path`,`id_dad_adm_alertgroup`) USING BTREE
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_fs_dacl`
--

DROP TABLE IF EXISTS `dad_fs_dacl`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_fs_dacl` (
  `dad_fs_dacl_id` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `dacl` varchar(20) NOT NULL DEFAULT '',
  `description` text,
  `querytime` datetime DEFAULT NULL,
  PRIMARY KEY (`dad_fs_dacl_id`),
  KEY `idx_dad_fs_dacl_dacl` (`dacl`) USING BTREE
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_fs_log`
--

DROP TABLE IF EXISTS `dad_fs_log`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_fs_log` (
  `dad_fs_log_id` smallint(5) unsigned NOT NULL AUTO_INCREMENT,
  `filename` varchar(255) DEFAULT NULL,
  `filesize` int(10) unsigned DEFAULT NULL,
  `datemodified` datetime DEFAULT NULL,
  `querytime` datetime DEFAULT NULL,
  `imported` tinyint(1) DEFAULT NULL,
  PRIMARY KEY (`dad_fs_log_id`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_fs_path`
--

DROP TABLE IF EXISTS `dad_fs_path`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_fs_path` (
  `id_dad_fs_path` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `fullpath` text,
  `name` varchar(255) DEFAULT '',
  `depth` int(10) unsigned DEFAULT '0',
  `activeyesno` tinyint(1) unsigned DEFAULT '0',
  `timeactive` datetime DEFAULT '0000-00-00 00:00:00',
  `parent_id` int(10) unsigned DEFAULT NULL,
  `timeinactive` datetime DEFAULT '0000-00-00 00:00:00',
  PRIMARY KEY (`id_dad_fs_path`),
  KEY `idx_dad_fs_path_fullpath` (`fullpath`(140),`depth`,`activeyesno`,`id_dad_fs_path`) USING BTREE
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_fs_path_cl`
--

DROP TABLE IF EXISTS `dad_fs_path_cl`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_fs_path_cl` (
  `dad_fs_path_cl_id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `id_dad_fs_path` int(10) unsigned DEFAULT NULL,
  `id_dad_cl_classification_read` tinyint(4) unsigned DEFAULT NULL,
  `id_dad_cl_classification_write` tinyint(4) unsigned DEFAULT NULL,
  `id_dad_adm_action_read` smallint(5) unsigned DEFAULT NULL,
  `id_dad_adm_action_write` smallint(5) unsigned DEFAULT NULL,
  `calleractive` varchar(45) DEFAULT NULL,
  `timeactive` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`dad_fs_path_cl_id`),
  KEY `idx_dad_fs_path_cl_idpath` (`id_dad_fs_path`,`id_dad_cl_classification_read`,`id_dad_cl_classification_write`,`id_dad_adm_action_read`,`id_dad_adm_action_write`) USING BTREE
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_fs_permission`
--

DROP TABLE IF EXISTS `dad_fs_permission`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_fs_permission` (
  `dad_fs_permission_id` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `id_dad_fs_path` int(10) unsigned NOT NULL DEFAULT '0',
  `objectsid_dad_ds_object` varchar(100) DEFAULT NULL,
  `dacl` varchar(20) DEFAULT NULL,
  `querytime` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  PRIMARY KEY (`dad_fs_permission_id`),
  UNIQUE KEY `id` (`dad_fs_permission_id`),
  KEY `idx_dad_fs_permission_id_dad_fs_path` (`id_dad_fs_path`,`objectsid_dad_ds_object`,`querytime`) USING BTREE,
  KEY `idx_dad_fs_permission_objectsid_dad_ds_object` (`objectsid_dad_ds_object`,`id_dad_fs_path`,`querytime`) USING BTREE
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_org_department`
--

DROP TABLE IF EXISTS `dad_org_department`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_org_department` (
  `deptname` varchar(100) NOT NULL DEFAULT '',
  `iddept` int(10) unsigned NOT NULL DEFAULT '0',
  `subdeptname` varchar(100) NOT NULL DEFAULT '',
  `idsubdept` int(10) unsigned NOT NULL DEFAULT '0',
  KEY `idx_dad_org_department_dept` (`iddept`) USING BTREE,
  KEY `idx_dad_org_department_subdept` (`idsubdept`) USING BTREE
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_org_person`
--

DROP TABLE IF EXISTS `dad_org_person`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_org_person` (
  `id_dad_org_person` int(10) unsigned NOT NULL DEFAULT '0',
  `name` varchar(100) NOT NULL DEFAULT '',
  `email` varchar(100) NOT NULL DEFAULT '',
  `workphone` varchar(20) DEFAULT NULL,
  `deptname` varchar(100) DEFAULT NULL,
  `iddept` int(10) unsigned DEFAULT NULL,
  `subdeptname` varchar(100) DEFAULT NULL,
  `idsubdept` int(10) unsigned DEFAULT NULL,
  `activeyesno` tinyint(1) unsigned DEFAULT NULL,
  `timeinactive` datetime DEFAULT NULL,
  KEY `idx_dad_org_person_id` (`id_dad_org_person`,`name`,`activeyesno`) USING BTREE,
  KEY `idx_dad_org_person_name` (`name`,`id_dad_org_person`,`activeyesno`) USING BTREE
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_sr_groupmembership`
--

DROP TABLE IF EXISTS `dad_sr_groupmembership`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_sr_groupmembership` (
  `dad_sr_groupmembership_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `groupname` varchar(200) NOT NULL DEFAULT '',
  `membername` varchar(200) NOT NULL DEFAULT '',
  `server` varchar(20) NOT NULL DEFAULT '',
  `querytime` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  PRIMARY KEY (`dad_sr_groupmembership_id`),
  KEY `idx_dad_sr_groupmembership_querytime` (`querytime`) USING BTREE,
  KEY `idx_dad_sr_groupmembership_groupname` (`groupname`,`membername`,`server`,`querytime`),
  KEY `idx_dad_sr_groupmembership_membername` (`membername`,`groupname`,`server`,`querytime`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_sr_object`
--

DROP TABLE IF EXISTS `dad_sr_object`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_sr_object` (
  `sid_dad_sr_object` varchar(100) NOT NULL DEFAULT '',
  `samaccountname` varchar(255) DEFAULT NULL,
  `distinguishedname` varchar(255) DEFAULT NULL,
  `description` varchar(255) DEFAULT NULL,
  `samaccounttype` int(10) unsigned DEFAULT NULL,
  `lastlogon` datetime DEFAULT NULL,
  `pwdexpire` datetime DEFAULT NULL,
  `pwdrequired` tinyint(1) unsigned DEFAULT NULL,
  `disabled` tinyint(1) unsigned DEFAULT NULL,
  `server` varchar(20) DEFAULT NULL,
  `querytime` datetime DEFAULT NULL,
  `id` int(11) NOT NULL AUTO_INCREMENT,
  PRIMARY KEY (`id`),
  KEY `idx_dad_sr_object_id` (`sid_dad_sr_object`,`samaccountname`,`description`,`server`,`querytime`) USING BTREE,
  KEY `idx_dad_sr_object_samaccountname` (`samaccountname`,`sid_dad_sr_object`,`server`,`querytime`) USING BTREE,
  KEY `idx_dad_sr_object_description` (`description`,`sid_dad_sr_object`,`server`,`querytime`) USING BTREE
) ENGINE=MyISAM DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_sys_cis_imported`
--

DROP TABLE IF EXISTS `dad_sys_cis_imported`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_sys_cis_imported` (
  `CIS_Imported_ID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `Log_Name` varchar(255) NOT NULL,
  `System_Name` varchar(45) DEFAULT NULL,
  `LastLogEntry` bigint(20) unsigned DEFAULT NULL,
  PRIMARY KEY (`CIS_Imported_ID`)
) ENGINE=MyISAM AUTO_INCREMENT=1106 DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_sys_event_desc`
--

DROP TABLE IF EXISTS `dad_sys_event_desc`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_sys_event_desc` (
  `dad_sys_event_desc_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `event_id` int(10) unsigned DEFAULT NULL,
  `event_log` varchar(100) DEFAULT NULL,
  `event_source` varchar(100) DEFAULT NULL,
  `event_type` varchar(100) DEFAULT NULL,
  `message` varchar(3500) DEFAULT NULL,
  `os_name` varchar(100) DEFAULT NULL,
  `os_ver` varchar(20) DEFAULT NULL,
  PRIMARY KEY (`dad_sys_event_desc_id`)
) ENGINE=MyISAM AUTO_INCREMENT=6730 DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_sys_event_import_from`
--

DROP TABLE IF EXISTS `dad_sys_event_import_from`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_sys_event_import_from` (
  `ToImportID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `System_Name` varchar(80) NOT NULL,
  `Priority` int(10) unsigned NOT NULL,
  `Next_Run` int(10) unsigned NOT NULL,
  `Log_These` int(10) unsigned NOT NULL,
  PRIMARY KEY (`ToImportID`)
) ENGINE=MyISAM AUTO_INCREMENT=142 DEFAULT CHARSET=latin1;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_sys_event_stats`
--

DROP TABLE IF EXISTS `dad_sys_event_stats`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_sys_event_stats` (
  `Stats_ID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `System_Name` varchar(45) NOT NULL,
  `Service_Name` varchar(45) NOT NULL,
  `Stat_Type` int(10) unsigned NOT NULL,
  `Total_In_Log` int(10) unsigned NOT NULL,
  `Number_Inserted` int(10) unsigned NOT NULL,
  `Stat_Time` int(10) unsigned NOT NULL,
  PRIMARY KEY (`Stats_ID`),
  KEY `Systems` (`System_Name`),
  KEY `Stats_Type` (`Stat_Type`) USING BTREE
) ENGINE=MyISAM AUTO_INCREMENT=7380854 DEFAULT CHARSET=latin1 COMMENT='Tracks event log gathering statistics';
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_sys_events`
--

DROP TABLE IF EXISTS `dad_sys_events`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_sys_events` (
  `dad_sys_events_id` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `SystemID` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `ServiceID` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `TimeWritten` int(10) unsigned NOT NULL DEFAULT '0',
  `TimeGenerated` int(10) unsigned NOT NULL DEFAULT '0',
  `Source` char(255) NOT NULL DEFAULT '',
  `Category` char(255) NOT NULL DEFAULT '',
  `SID` char(64) CHARACTER SET latin1 NOT NULL DEFAULT '',
  `Computer` char(255) NOT NULL DEFAULT '',
  `EventID` mediumint(8) unsigned NOT NULL DEFAULT '0',
  `EventType` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `Field_0` varchar(760) DEFAULT NULL,
  `Field_1` varchar(760) DEFAULT NULL,
  `Field_2` varchar(760) DEFAULT NULL,
  `Field_3` varchar(760) DEFAULT NULL,
  `Field_4` varchar(760) DEFAULT NULL,
  `Field_5` varchar(760) DEFAULT NULL,
  `Field_6` varchar(760) DEFAULT NULL,
  `Field_7` varchar(760) DEFAULT NULL,
  `Field_8` varchar(760) DEFAULT NULL,
  `Field_9` varchar(760) DEFAULT NULL,
  `Field_10` varchar(760) DEFAULT NULL,
  `Field_11` varchar(760) DEFAULT NULL,
  `Field_12` varchar(760) DEFAULT NULL,
  `Field_13` varchar(760) DEFAULT NULL,
  `Field_14` varchar(760) DEFAULT NULL,
  `Field_15` varchar(760) DEFAULT NULL,
  `Field_16` varchar(760) DEFAULT NULL,
  `Field_17` varchar(760) DEFAULT NULL,
  `Field_18` varchar(760) DEFAULT NULL,
  `Field_19` varchar(760) DEFAULT NULL,
  `Field_20` varchar(760) DEFAULT NULL,
  `Field_21` varchar(760) DEFAULT NULL,
  `Field_22` varchar(760) DEFAULT NULL,
  `Field_23` varchar(760) DEFAULT NULL,
  `Field_24` varchar(760) DEFAULT NULL,
  `Field_25` varchar(760) DEFAULT NULL,
  `idxID_Code` char(64) DEFAULT NULL,
  `idxID_Kerb` char(64) DEFAULT NULL,
  `idxID_NTLM` char(64) DEFAULT NULL,
  PRIMARY KEY (`dad_sys_events_id`),
  KEY `idxEventID` (`EventID`),
  KEY `idxSID` (`SID`),
  KEY `idxTimestamp` (`TimeGenerated`),
  KEY `idxIDbyCode` (`idxID_Code`(10)),
  KEY `idxIDbyKerb` (`idxID_Kerb`(15)),
  KEY `idxIDbyNTLM` (`idxID_NTLM`(10)),
  KEY `idxNTLMCode` (`Field_3`(15))
) ENGINE=MyISAM AUTO_INCREMENT=72285891 DEFAULT CHARSET=utf8 COMMENT='Normalized Windows Events';
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_sys_events_aging`
--

DROP TABLE IF EXISTS `dad_sys_events_aging`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_sys_events_aging` (
  `Aging_ID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `Event_ID` int(10) unsigned NOT NULL,
  `Explanation` varchar(255) NOT NULL,
  `Retention_Time` int(10) unsigned NOT NULL,
  PRIMARY KEY (`Aging_ID`)
) ENGINE=MyISAM AUTO_INCREMENT=14 DEFAULT CHARSET=latin1 COMMENT='Aging schedule for various Windows events';
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_sys_events_groomed`
--

DROP TABLE IF EXISTS `dad_sys_events_groomed`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_sys_events_groomed` (
  `Groomed_ID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `Timestamp` int(10) unsigned NOT NULL,
  `Event_ID` int(10) unsigned NOT NULL,
  `Number_Groomed` int(10) unsigned NOT NULL,
  PRIMARY KEY (`Groomed_ID`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COMMENT='Groomed Event Stats';
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_sys_field_descriptions`
--

DROP TABLE IF EXISTS `dad_sys_field_descriptions`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_sys_field_descriptions` (
  `Service_ID` int(10) unsigned NOT NULL,
  `Field_0_Name` varchar(45) NOT NULL DEFAULT '',
  `Field_1_Name` varchar(45) NOT NULL DEFAULT '',
  `Field_2_Name` varchar(45) NOT NULL DEFAULT '',
  `Field_3_Name` varchar(45) NOT NULL DEFAULT '',
  `Field_4_Name` varchar(45) NOT NULL DEFAULT '',
  `Field_5_Name` varchar(45) NOT NULL DEFAULT '',
  `Field_6_Name` varchar(45) NOT NULL DEFAULT '',
  `Field_7_Name` varchar(45) NOT NULL DEFAULT '',
  `Field_8_Name` varchar(45) NOT NULL DEFAULT '',
  `Field_9_Name` varchar(45) NOT NULL DEFAULT '',
  `Field_10_Name` varchar(45) NOT NULL,
  `Field_11_Name` varchar(45) NOT NULL,
  `Field_12_Name` varchar(45) NOT NULL,
  `Field_13_Name` varchar(45) NOT NULL,
  `Field_14_Name` varchar(45) NOT NULL,
  `Field_15_Name` varchar(45) NOT NULL,
  `Field_16_Name` varchar(45) NOT NULL,
  PRIMARY KEY (`Service_ID`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COMMENT='Identifies general fields from the Event table';
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_sys_filtered_events`
--

DROP TABLE IF EXISTS `dad_sys_filtered_events`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_sys_filtered_events` (
  `Filtered_ID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `Event_ID` int(10) unsigned NOT NULL,
  `Description` varchar(45) NOT NULL,
  PRIMARY KEY (`Filtered_ID`)
) ENGINE=MyISAM AUTO_INCREMENT=12 DEFAULT CHARSET=latin1 COMMENT='Event IDs that are filtered from incoming logs';
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_sys_linked_queries`
--

DROP TABLE IF EXISTS `dad_sys_linked_queries`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_sys_linked_queries` (
  `Query_ID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `SQL` varchar(768) NOT NULL,
  `Role_ID` int(10) unsigned NOT NULL COMMENT 'Eventually to be used to limit who can query what...  Maybe this should be handled somewhere else?  Here too...',
  `Query_Desc` varchar(255) NOT NULL,
  PRIMARY KEY (`Query_ID`)
) ENGINE=MyISAM AUTO_INCREMENT=2 DEFAULT CHARSET=latin1 COMMENT='These queries are linked to by other queries, never called d';
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_sys_location`
--

DROP TABLE IF EXISTS `dad_sys_location`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_sys_location` (
  `Location_ID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `Location_Name` varchar(45) NOT NULL DEFAULT '',
  `Contact_Information` varchar(80) NOT NULL DEFAULT '',
  PRIMARY KEY (`Location_ID`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COMMENT='Tracks system locations';
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_sys_os`
--

DROP TABLE IF EXISTS `dad_sys_os`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_sys_os` (
  `OS_ID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `OS_Name` varchar(45) NOT NULL DEFAULT '',
  `Max_Patch_ID` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`OS_ID`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COMMENT='Operating Systems';
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_sys_patchlevels`
--

DROP TABLE IF EXISTS `dad_sys_patchlevels`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_sys_patchlevels` (
  `Patch_ID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `Patch_Date` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `Patch_Name` varchar(45) NOT NULL DEFAULT '',
  `OS_ID` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`Patch_ID`)
) ENGINE=MyISAM DEFAULT CHARSET=latin1 COMMENT='Tracks OS Patch levels';
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_sys_queries`
--

DROP TABLE IF EXISTS `dad_sys_queries`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_sys_queries` (
  `Query_ID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `Query` varchar(1024) NOT NULL,
  `Description` varchar(1024) NOT NULL,
  `Name` varchar(45) NOT NULL,
  `Category` varchar(45) NOT NULL,
  `Roles` varchar(256) NOT NULL DEFAULT '',
  `Timeframe` int(10) unsigned NOT NULL DEFAULT '86400',
  PRIMARY KEY (`Query_ID`)
) ENGINE=MyISAM AUTO_INCREMENT=65 DEFAULT CHARSET=latin1 COMMENT='Used for stored queries';
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_sys_services`
--

DROP TABLE IF EXISTS `dad_sys_services`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_sys_services` (
  `Service_ID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `Service_Name` varchar(45) NOT NULL DEFAULT '',
  `Contact_Information` varchar(80) NOT NULL DEFAULT '',
  `log_these_id` int(11) DEFAULT NULL,
  PRIMARY KEY (`Service_ID`)
) ENGINE=MyISAM AUTO_INCREMENT=2041 DEFAULT CHARSET=latin1 COMMENT='Tracks services reported on';
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `dad_sys_systems`
--

DROP TABLE IF EXISTS `dad_sys_systems`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `dad_sys_systems` (
  `System_ID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `System_Name` varchar(45) NOT NULL DEFAULT '',
  `Location_ID` int(10) unsigned NOT NULL DEFAULT '0',
  `Timezone` varchar(6) NOT NULL DEFAULT '',
  `OS_ID` int(10) unsigned NOT NULL DEFAULT '0',
  `Patch_ID` int(10) unsigned NOT NULL DEFAULT '0',
  `IP_Address` varchar(15) NOT NULL DEFAULT '',
  `Contact_Information` varchar(80) NOT NULL DEFAULT '',
  PRIMARY KEY (`System_ID`)
) ENGINE=MyISAM AUTO_INCREMENT=131 DEFAULT CHARSET=latin1 COMMENT='Master system table';
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `event_fields`
--

DROP TABLE IF EXISTS `event_fields`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `event_fields` (
  `Field_ID` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `Events_ID` bigint(20) unsigned NOT NULL COMMENT 'Foreign key to Events table',
  `Position` int(10) unsigned NOT NULL COMMENT 'Which field am I?',
  `String_ID` bigint(20) unsigned NOT NULL COMMENT 'Foreign key to unique strings table',
  PRIMARY KEY (`Field_ID`),
  KEY `idxString_ID` (`String_ID`),
  KEY `idxEvent_ID` (`Events_ID`)
) ENGINE=MyISAM AUTO_INCREMENT=13137204 DEFAULT CHARSET=latin1 COMMENT='Normalized field values from events';
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `event_unique_strings`
--

DROP TABLE IF EXISTS `event_unique_strings`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `event_unique_strings` (
  `String_ID` bigint(20) unsigned NOT NULL AUTO_INCREMENT,
  `String` varchar(768) NOT NULL COMMENT 'Actual unique string',
  PRIMARY KEY (`String_ID`),
  UNIQUE KEY `idxStrings` (`String`) USING BTREE
) ENGINE=MyISAM AUTO_INCREMENT=415566 DEFAULT CHARSET=latin1 COMMENT='Holds all unique strings used in events';
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `events`
--

DROP TABLE IF EXISTS `events`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `events` (
  `Events_ID` bigint(20) unsigned NOT NULL AUTO_INCREMENT COMMENT 'Primary index',
  `Time_Written` int(10) unsigned NOT NULL COMMENT 'Time the event is added to the database',
  `Time_Generated` int(10) unsigned NOT NULL COMMENT 'Time the generating system created the event',
  `System_ID` int(10) unsigned NOT NULL COMMENT 'Foreign Key to dad_sys_systems',
  `Service_ID` int(10) unsigned NOT NULL COMMENT 'Foreign Key to dad_sys_services',
  PRIMARY KEY (`Events_ID`),
  KEY `idxTime_Written` (`Time_Written`),
  KEY `idxTime_Generated` (`Time_Generated`),
  KEY `idxSystem_ID` (`System_ID`),
  KEY `idxService_ID` (`Service_ID`)
) ENGINE=MyISAM AUTO_INCREMENT=859328 DEFAULT CHARSET=latin1 COMMENT='Normalized events';
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `language`
--

DROP TABLE IF EXISTS `language`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `language` (
  `LanguageID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `LanguageCode` char(3) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `LanguageName` char(40) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `LatestChangeStamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`LanguageID`)
) ENGINE=MyISAM AUTO_INCREMENT=7 DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `menu`
--

DROP TABLE IF EXISTS `menu`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `menu` (
  `MenuID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `MenuName` char(40) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `LevelNum` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `SequenceNum` tinyint(3) unsigned NOT NULL DEFAULT '0',
  `ParentMenuOptionID` int(10) unsigned NOT NULL DEFAULT '0',
  `LatestChangeStamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`MenuID`)
) ENGINE=MyISAM AUTO_INCREMENT=9 DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `menuoption`
--

DROP TABLE IF EXISTS `menuoption`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `menuoption` (
  `MenuOptionID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `OptionName` char(40) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `MenuID` int(10) unsigned NOT NULL DEFAULT '0',
  `SequenceNum` smallint(5) unsigned NOT NULL DEFAULT '0',
  `ContentPathName` char(128) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `FunctionName` char(40) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `LatestChangeStamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`MenuOptionID`)
) ENGINE=MyISAM AUTO_INCREMENT=72 DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `orggroup`
--

DROP TABLE IF EXISTS `orggroup`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `orggroup` (
  `OrgGroupID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `OrgGroupTypeID` int(10) unsigned NOT NULL DEFAULT '0',
  `IdentifyingOrgUnitID` int(10) unsigned NOT NULL DEFAULT '0',
  `LatestChangeStamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`OrgGroupID`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `orggroupmember`
--

DROP TABLE IF EXISTS `orggroupmember`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `orggroupmember` (
  `OrgGroupMemberID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `OrgGroupID` int(10) unsigned NOT NULL DEFAULT '0',
  `MemberOrgUnitID` int(10) unsigned NOT NULL DEFAULT '0',
  `LatestChangeStamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`OrgGroupMemberID`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `orggrouptype`
--

DROP TABLE IF EXISTS `orggrouptype`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `orggrouptype` (
  `OrgGroupTypeID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `OrgGroupTypeName` char(40) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `IdentifyingOrgUnitTypeID` int(10) unsigned NOT NULL DEFAULT '0',
  `MemberOrgUnitTypeID` int(10) unsigned NOT NULL DEFAULT '0',
  `LatestChangeStamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`OrgGroupTypeID`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `orgunit`
--

DROP TABLE IF EXISTS `orgunit`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `orgunit` (
  `OrgUnitID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `OrgUnitTypeID` int(10) unsigned NOT NULL DEFAULT '0',
  `OrgUnitName` char(40) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `DomainLoginName` char(15) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `OrgUnitUserKey` char(10) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `DefaultLanguageID` int(10) unsigned NOT NULL DEFAULT '0',
  `SourceA2KSystemID` int(10) unsigned NOT NULL DEFAULT '0',
  `LatestChangeStamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`OrgUnitID`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `orgunittype`
--

DROP TABLE IF EXISTS `orgunittype`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `orgunittype` (
  `OrgUnitTypeID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `OrgUnitTypeName` char(40) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `OrgUnitUserKeyLabel` char(40) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `LoginDomainFlag` tinyint(1) NOT NULL DEFAULT '0',
  `UserNameLabel` char(40) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `MaxUserNum` smallint(5) unsigned NOT NULL DEFAULT '0',
  `LatestChangeStamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`OrgUnitTypeID`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `role`
--

DROP TABLE IF EXISTS `role`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `role` (
  `RoleID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `RoleName` char(40) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `RoleDescr` char(128) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `RoleOrgUnitTypeID` int(10) unsigned NOT NULL DEFAULT '0',
  `UserRoleOrgUnitTypeID` int(10) unsigned NOT NULL DEFAULT '0',
  `LatestChangeStamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`RoleID`)
) ENGINE=MyISAM AUTO_INCREMENT=7 DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `rolemenuoption`
--

DROP TABLE IF EXISTS `rolemenuoption`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `rolemenuoption` (
  `RoleMenuOptionID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `RoleID` int(10) unsigned NOT NULL DEFAULT '0',
  `MenuOptionID` int(10) unsigned NOT NULL DEFAULT '0',
  `LatestChangeStamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`RoleMenuOptionID`)
) ENGINE=MyISAM AUTO_INCREMENT=132 DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `session`
--

DROP TABLE IF EXISTS `session`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `session` (
  `SessionID` binary(64) NOT NULL DEFAULT '\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0\0',
  `UserID` int(10) unsigned NOT NULL DEFAULT '0',
  `IPAddress` char(15) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `ExpireTime` int(10) unsigned NOT NULL DEFAULT '0',
  `LastOptionID` int(10) unsigned NOT NULL DEFAULT '0',
  PRIMARY KEY (`SessionID`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `system`
--

DROP TABLE IF EXISTS `system`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `system` (
  `SystemID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `AttributeName` char(15) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `AttributeValue` char(40) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `LatestChangeStamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`SystemID`)
) ENGINE=MyISAM DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `user`
--

DROP TABLE IF EXISTS `user`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `user` (
  `UserID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `UserName` char(20) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `PasswordText` char(40) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `FirstName` char(40) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `LastName` char(40) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `EmailAddress` char(45) COLLATE utf8_unicode_ci NOT NULL DEFAULT '',
  `LanguageID` int(10) unsigned NOT NULL DEFAULT '0',
  `CreatedDatetime` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `DeletedDatetime` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `LatestChangeUserID` int(10) unsigned NOT NULL DEFAULT '0',
  `LatestChangeStamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`UserID`)
) ENGINE=MyISAM AUTO_INCREMENT=5 DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `userrole`
--

DROP TABLE IF EXISTS `userrole`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `userrole` (
  `UserRoleID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `UserID` int(10) unsigned NOT NULL DEFAULT '0',
  `RoleID` int(10) unsigned NOT NULL DEFAULT '0',
  `OrgUnitID` int(10) unsigned NOT NULL DEFAULT '0',
  `CreatedDatetime` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `DeletedDatetime` datetime NOT NULL DEFAULT '0000-00-00 00:00:00',
  `LatestChangeUserID` int(10) unsigned NOT NULL DEFAULT '0',
  `LatestChangeStamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`UserRoleID`)
) ENGINE=MyISAM AUTO_INCREMENT=72 DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
SET character_set_client = @saved_cs_client;

--
-- Table structure for table `userstat`
--

DROP TABLE IF EXISTS `userstat`;
SET @saved_cs_client     = @@character_set_client;
SET character_set_client = utf8;
CREATE TABLE `userstat` (
  `UserStatID` int(10) unsigned NOT NULL AUTO_INCREMENT,
  `UserID` int(10) unsigned NOT NULL DEFAULT '0',
  `LoginCount` int(10) unsigned NOT NULL DEFAULT '0',
  `LatestLoginStamp` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`UserStatID`)
) ENGINE=MyISAM AUTO_INCREMENT=20 DEFAULT CHARSET=utf8 COLLATE=utf8_unicode_ci;
SET character_set_client = @saved_cs_client;
/*!40103 SET TIME_ZONE=@OLD_TIME_ZONE */;

/*!40101 SET SQL_MODE=@OLD_SQL_MODE */;
/*!40014 SET FOREIGN_KEY_CHECKS=@OLD_FOREIGN_KEY_CHECKS */;
/*!40014 SET UNIQUE_CHECKS=@OLD_UNIQUE_CHECKS */;
/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
/*!40111 SET SQL_NOTES=@OLD_SQL_NOTES */;

-- Dump completed on 2007-09-17 22:48:27

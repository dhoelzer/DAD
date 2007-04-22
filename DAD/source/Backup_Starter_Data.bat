@echo off
echo Backing up initial tables from %1
mysqldump -u root -p -h %1 --databases dad --tables dad_adm_job --tables dad_adm_carvers --tables dad_adm_action --tables dad_adm_computer_group --tables dad_sys_services --tables dad_event_log_types --tables dad_sys_events_aging --tables dad_sys_filtered_events --tables dad_sys_linked_queries --tables dad_sys_queries --tables language --tables menu --tables menuoption --tables orggroup --tables orggroupmember --tables orggrouptype --tables orgunit --tables orgunittype --tables role --tables rolemenuoption --tables session --tables system --tables userrole --tables userstat -q > Starter_Data.sql

ECHO -->> Starter_Data.sql
ECHO -- Dumping data for table `user`>> Starter_Data.sql
ECHO -->> Starter_Data.sql
ECHO /*!40000 ALTER TABLE `user` DISABLE KEYS */;>> Starter_Data.sql
ECHO LOCK TABLES `user` WRITE;>> Starter_Data.sql
ECHO INSERT INTO `user` VALUES (1,'admin','70ccd9007338d6d81dd3b6271621b9cf9a97ea00','The','Administrator','',0,'2005-06-30 20:41:19','0000-00-00 00:00:00',3,'2007-03-13 19:00:59');>> Starter_Data.sql
ECHO UNLOCK TABLES;>> Starter_Data.sql
ECHO /*!40000 ALTER TABLE `user` ENABLE KEYS */;>> Starter_Data.sql

ECHO -->> Starter_Data.sql
ECHO -- Dumping data for table `userrole`>> Starter_Data.sql
ECHO -->> Starter_Data.sql
ECHO /*!40000 ALTER TABLE `userrole` DISABLE KEYS */;>> Starter_Data.sql
ECHO LOCK TABLES `userrole` WRITE;>> Starter_Data.sql
ECHO INSERT INTO `userrole` VALUES (1,1,1,0,'0000-00-00 00:00:00','0000-00-00 00:00:00',0,'2005-07-02 15:40:57'),(2,1,2,0,'0000-00-00 00:00:00','0000-00-00 00:00:00',0,'2005-07-02 15:40:57');>> Starter_Data.sql
ECHO UNLOCK TABLES;>> Starter_Data.sql
ECHO /*!40000 ALTER TABLE `userrole` ENABLE KEYS */;>> Starter_Data.sql


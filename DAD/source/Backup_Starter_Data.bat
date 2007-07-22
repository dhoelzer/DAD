@echo off
echo Backing up initial tables from %1
mysqldump -u root --password="All4Fun" -h 127.0.0.1 --databases dad --tables dad_adm_action --tables dad_adm_carvers --tables dad_adm_computer_group --tables dad_adm_job --tables dad_event_log_types --tables dad_sys_events_aging --tables dad_sys_event_desc --tables dad_sys_filtered_events --tables dad_sys_linked_queries --tables dad_sys_queries --tables language --tables menu --tables menuoption --tables role --tables rolemenuoption --tables user -q > Starter_Data.sql

ECHO -->> Starter_Data.sql
ECHO -- Dumping data for table `userrole`>> Starter_Data.sql
ECHO -->> Starter_Data.sql
ECHO /*!40000 ALTER TABLE `userrole` DISABLE KEYS */;>> Starter_Data.sql
ECHO LOCK TABLES `userrole` WRITE;>> Starter_Data.sql
ECHO INSERT INTO `userrole` VALUES (1,1,1,0,'0000-00-00 00:00:00','0000-00-00 00:00:00',0,'2005-07-02 15:40:57'),(2,1,2,0,'0000-00-00 00:00:00','0000-00-00 00:00:00',0,'2005-07-02 15:40:57');>> Starter_Data.sql
ECHO UNLOCK TABLES;>> Starter_Data.sql
ECHO /*!40000 ALTER TABLE `userrole` ENABLE KEYS */;>> Starter_Data.sql


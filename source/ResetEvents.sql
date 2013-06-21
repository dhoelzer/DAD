USE dad;
CREATE DEFINER=`root`@`%` PROCEDURE `ResetEvents`()
BEGIN
  UPDATE dad_sys_event_import_from SET Next_Run=0;
  DELETE FROM dad_sys_cis_imported;
  DELETE FROM events;
  DELETE FROM event_fields;
  DELETE FROM event_unique_strings;
  DELETE FROM unique_fields;
END
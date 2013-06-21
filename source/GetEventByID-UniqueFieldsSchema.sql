USE DAD;
CREATE DEFINER=`root`@`%` PROCEDURE `GetEventByID`(IN intEventID BIGINT(20))
BEGIN
  select
        events.events_id,
        from_unixtime(time_generated),from_unixtime(time_written),system_name,service_name,
        group_concat(event_unique_strings.string ORDER BY unique_fields.position SEPARATOR ' ')
  from
        events,
        event_fields,
        dad_sys_systems,
        dad_sys_services,
        unique_fields,
        event_unique_strings
  where
          events.system_id = dad_sys_systems.system_id
          and events.service_id = dad_sys_services.service_id
          and events.events_id = event_fields.events_id
          and event_fields.unique_field_id = unique_fields.unique_field_id
          and unique_fields.string_id = event_unique_strings.string_id
          and events.Events_ID=intEventID
  GROUP BY events.events_id
  ORDER BY events.events_id;

END
USE DAD;
CREATE DEFINER=`root`@`%` PROCEDURE `GetEventIDsByString`(IN strString VARCHAR(767))
BEGIN
SELECT ef.Events_ID FROM event_fields as ef, unique_fields as uf, event_unique_strings as eus
                  WHERE
                          eus.String=strString AND
                          uf.String_ID=eus.String_ID AND
                          uf.Unique_Field_ID=ef.Unique_Field_ID GROUP BY Events_ID ORDER BY Events_ID;
END
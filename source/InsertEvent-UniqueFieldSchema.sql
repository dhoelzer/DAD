CREATE DEFINER=`root`@`%` PROCEDURE `InsertEvent`(IN intTimeGenerated INTEGER, IN vcSystemName VARCHAR(45), IN vcServiceName VARCHAR(45), IN vcEventLine VARCHAR(8192))
    SQL SECURITY INVOKER
BEGIN
         /* ----- Initialize variables ----- */
        DECLARE intSystemID INT DEFAULT 0;
        DECLARE intServiceID INT DEFAULT 0;
        DECLARE intEventID INT DEFAULT 0;
        DECLARE intStatus INT DEFAULT 0;
        DECLARE intUniqueStatus INT DEFAULT 0;
        DECLARE vcString VARCHAR(767);
        DECLARE intStringID INT DEFAULT 0;
        DECLARE intPosition TINYINT DEFAULT 0;
        DECLARE intUniqueFieldID INT DEFAULT 0;
        DECLARE EXIT HANDLER FOR SQLEXCEPTION
        BEGIN
                SELECT "Error";
        ROLLBACK;
        END;

        DECLARE CONTINUE HANDLER FOR 1062 SET intUniqueStatus=1;
        DECLARE CONTINUE HANDLER FOR NOT FOUND SET intStatus=1;
        /* ----- Convert system_name and service_name into ids ----- */
        SELECT System_ID FROM dad_sys_systems WHERE System_Name = vcSystemName INTO intSystemID;
        IF intStatus = 1 THEN
                INSERT INTO dad_sys_systems (System_Name) VALUES (vcSystemName);
                SELECT LAST_INSERT_ID() INTO intSystemID;
                SET intStatus=0;
        END IF;
        SELECT Service_ID FROM dad_sys_services WHERE Service_Name = vcServiceName INTO intServiceID;
        IF intStatus = 1 THEN
                INSERT INTO dad_sys_services (Service_Name) VALUES (vcServiceName);
                SELECT LAST_INSERT_ID() INTO intServiceID;
                SET intStatus=0;
        END IF;

        /* ----- Continue if system and service names were able to be looked up -----*/
        IF intStatus = 1 THEN
                SELECT "Error - missing service or system name";
        ELSE
                SET AUTOCOMMIT=0;
                START TRANSACTION;
                /* ----- Insert into events table ----- */
                INSERT INTO Events (Time_Generated,Time_Written,System_ID,Service_ID)  VALUES (intTimeGenerated, UNIX_TIMESTAMP(CURRENT_TIMESTAMP), intSystemID, intServiceID);
                SELECT LAST_INSERT_ID() INTO intEventID;

                /* ----- Insert strings into event_unique_strings, unique_fields, and event_fields -----*/
                REPEAT
                        SET intPosition = intPosition + 1;
                        SET vcString = LTRIM(SUBSTRING(SUBSTRING_INDEX(vcEventLine,' ',intPosition),LENGTH(SUBSTRING_INDEX(vcEventLine,' ',intPosition-1))+1));


                        /* Get String ID for string */
                        SELECT String_ID FROM event_unique_strings WHERE string=vcString INTO intStringID;
                        IF intStatus = 1 THEN
                                INSERT INTO event_unique_strings (string) VALUES (vcString);
                                IF intUniqueStatus=1 THEN
                                        SELECT String_ID FROM event_unique_strings WHERE string=vcString INTO intStringID;
                                        SET intUniqueStatus=0;
                                ELSE
                                        SELECT LAST_INSERT_ID() INTO intStringID;
                                END IF;
                                SET intStatus=0;
                        END IF;
                        /* Get Unique Field ID */
                        SELECT Unique_Field_ID FROM unique_fields WHERE String_ID=intStringID AND Position=intPosition INTO intUniqueFieldID;
                        IF intStatus = 1 THEN
                                INSERT INTO unique_fields (String_ID,Position) VALUES (intStringID,intPosition);
                                SELECT LAST_INSERT_ID() INTO intUniqueFieldID;
                                SET intStatus=0;
                        END IF;

                        /* Insert into event fields */
                        INSERT INTO event_fields (Events_ID,Unique_Field_ID) VALUES (intEventID, intUniqueFieldID);
                        UNTIL vcEventLine = SUBSTRING_INDEX(vcEventLine, ' ',intPosition)
                END REPEAT;
                COMMIT;
                SELECT "OK";
        END IF;
END
/*
 * ScheduleDBInterface.java
 *
 * Created on April 15, 2007, 10:06 PM
 *
 * To change this template, choose Tools | Template Manager
 * and open the template in the editor.
 */

package dadscheduler;
import java.sql.*;
import java.util.*;
import java.io.*;

/**
 *
 * @author dhoelzer
 */
public class ScheduleDBInterface {
    
    private DatabaseClass dbo;
    private String DBURL, DBUser, DBPassword;
    
    /** Creates a new instance of ScheduleDBInterface */
    public ScheduleDBInterface() {
        BufferedReader ConfigFile = null;
        String Line;
        dbo = null;
        try {
            ConfigFile = new BufferedReader(new FileReader("/DAD/dbconfig.jv"));
            while((Line = ConfigFile.readLine()) != null)
            {
                if(Line.contains("URL"))
                {
                    DBURL = Line.substring(Line.indexOf("=")+1).trim();
                }
                if(Line.contains("User"))
                {
                    DBUser = Line.substring(Line.indexOf("=")+1).trim();
                }
                if(Line.contains("Password"))
                {
                    DBPassword = Line.substring(Line.indexOf("=")+1).trim();
                }
            }
            ConfigFile.close();
        }
        catch(Exception e)
        {
            System.out.println("Exception reading configuration file: "+e.getMessage());
        }
    }
    
    public Job GetPersistentJobs()
    {
        return GetNextJob("AND persistent=TRUE");
    }
    
    public Job GetNextJob()
    {
        return GetNextJob("");
    }
    
    public Job GetNextJob(String PersistentState)
    {
        Job thisJob = new Job();
        String data;
        java.util.Date now = new java.util.Date();
        String SQL;
        
        dbo = new DatabaseClass(DBURL, DBUser, DBPassword);
        now.getTime();
        SQL = "SELECT * FROM dad_adm_job WHERE next_start<" +
                (now.getTime()/1000) + " AND is_running=FALSE " +
                PersistentState;
        thisJob = dbo.SQLQuery(SQL);
        if(thisJob == null)
        {
            dbo = null;
            return null; 
        }
        SQL = "UPDATE dad_adm_job SET is_running=TRUE WHERE " +
                "id_dad_adm_job='" + thisJob.QueryJobID() + "'";
        dbo.SQLQueryNoResult(SQL);
        dbo = null;
        return thisJob;
    }

    void SetFinished(int job)
    {
        dbo = new DatabaseClass(DBURL, DBUser, DBPassword);
        String SQL = "UPDATE dad_adm_job SET is_running=FALSE WHERE " +
                "id_dad_adm_job='" + job + "'";
        dbo.SQLQueryNoResult(SQL);
        dbo = null;
    }

    void ClearIsRunning()
    {
        String SQL;
        dbo = new DatabaseClass(DBURL, DBUser, DBPassword);
        SQL = "UPDATE dad_adm_job SET "+
                "is_running=FALSE";
        dbo.SQLQueryNoResult(SQL);
        dbo = null;
        return;
    }
    
    void Reschedule(int job)
    {
        //JobSQLResults RetrievedJob;
        long last_started, next_start_time, minutes, hours, days;
        java.util.Date now = new java.util.Date();
        dbo = new DatabaseClass(DBURL, DBUser, DBPassword);
        
        now.getTime();System.out.println("\tGot time");
        String SQL = "SELECT * FROM dad_adm_job WHERE id_dad_adm_job='" + 
                job + "'";
        Job thisResult = dbo.SQLQuery(SQL);System.out.println("\tGot job");
        last_started = thisResult.GetNextStart();System.out.println("\tGot next start");
        if(last_started == 0)
        {
            last_started = (now.getTime()/1000);
        }
        if( ! thisResult.IsPersistent())
        {
            minutes = thisResult.GetMin() * 60;
            hours = thisResult.GetHour() * 3600;
            days = thisResult.GetDay() * 86400;
            next_start_time = last_started + minutes + hours + days;

            while(next_start_time < (now.getTime()/1000))
            {
                next_start_time += (minutes + hours + days);
            }
        }
        else
        {
            next_start_time = last_started;
        }
        SQL = "UPDATE dad_adm_job SET "+
                "is_running=FALSE, last_ran=" + last_started +
                ", next_start=" + next_start_time + " WHERE " +
                "id_dad_adm_job='" + job + "'";
        System.out.println("\t"+SQL);
        dbo.SQLQueryNoResult(SQL);System.out.println("\tSet next start");
        now = null;
        dbo = null;
    }
}

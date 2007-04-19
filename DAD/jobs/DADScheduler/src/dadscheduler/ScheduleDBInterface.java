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

/**
 *
 * @author dhoelzer
 */
public class ScheduleDBInterface {
    
    private DatabaseClass dbo;
    
    /** Creates a new instance of ScheduleDBInterface */
    public ScheduleDBInterface() {
        dbo = new DatabaseClass();
    }
    
    public Job GetNextJob()
    {
        Job thisJob = new Job();
        ResultSet rs;
        int job_ID;
        ResultSetMetaData columns;
        String data;
        java.util.Date now = new java.util.Date();
        
        now.getTime();
        String SQL = "SELECT * FROM dad_adm_job WHERE next_start<" +
                (now.getTime()/1000) + " AND is_running=FALSE";
        rs = dbo.SQLQuery(SQL);
        try
        {
            if(!rs.next()) { return thisJob; }
            thisJob.SetExecutable(rs.getString("path"));
            thisJob.SetLastExecTime(rs.getString("last_ran"));
            thisJob.SetName(rs.getString("descrip"));
            thisJob.SetRuntime(rs.getInt("next_start"));
            job_ID = rs.getInt("id_dad_adm_job");
            thisJob.SetJobID(job_ID);
            rs.close();
            SQL = "UPDATE dad_adm_job SET is_running=TRUE WHERE " +
                    "id_dad_adm_job='" + job_ID + "'";
            dbo.SQLQueryNoResult(SQL);
        }
        catch (java.sql.SQLException e)
        {
            System.err.println("SQL error has occurred: " + e.getMessage());
        }
        return thisJob;
    }

    void SetFinished(int job)
    {
        String SQL = "UPDATE dad_adm_job SET is_running=FALSE WHERE " +
                "id_dad_adm_job='" + job + "'";
        dbo.SQLQueryNoResult(SQL);
    }
    
    void Reschedule(int job)
    {
        ResultSet rs;
        long last_started, next_start_time, minutes, hours, days;
        java.util.Date now = new java.util.Date();
        
        now.getTime();
        String SQL = "SELECT * FROM dad_adm_job WHERE id_dad_adm_job='" + 
                job + "'";
        rs = dbo.SQLQuery(SQL);
        try
        {
            if(!rs.next()) { return; } // Job deleted while running?
            last_started = rs.getInt("next_start");
            if(last_started == 0)
            {
                last_started = (now.getTime()/1000);
            }
            minutes = rs.getInt("min") * 60;
            hours = rs.getInt("hour") * 3600;
            days = rs.getInt("day") * 86400;
            rs.close();
            next_start_time = last_started + minutes + hours + days;
            while(next_start_time < (now.getTime()/1000))
            {
                next_start_time += minutes + hours + days;
            }
            SQL = "UPDATE dad_adm_job SET "+
                    "is_running=FALSE, last_ran=" + last_started +
                    ", next_start=" + next_start_time + " WHERE " +
                    "id_dad_adm_job='" + job + "'";
            dbo.SQLQueryNoResult(SQL);
        }
        catch (java.sql.SQLException e)
        {
            System.err.println("SQL error has occurred: " + e.getMessage());
            System.err.println("Could not mark job as completed!");
            return;
        }
    }
}

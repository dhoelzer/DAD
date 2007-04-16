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
        ResultSetMetaData columns;
        String data;
        
        String SQL = "SELECT * FROM dad_adm_job ";
        rs = dbo.SQLQuery(SQL);
        System.out.printf("Ran query\n");
        try
        {
            if(!rs.next()) { return null; }
            thisJob.SetExecutable(rs.getString("path"));
            thisJob.SetName(rs.getString("descrip"));
            thisJob.SetRuntime(rs.getInt("timeactive"));
            rs.close();
        }
        catch (java.sql.SQLException e)
        {
            System.err.println("SQL error has occurred: " + e.getMessage());
        }
        return thisJob;
    }
}

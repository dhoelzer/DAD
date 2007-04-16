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
        
        String SQL = "SELECT * FROM dad_sys_adm_job";
        rs = dbo.SQLQuery(SQL);
        try
        {
            columns = rs.getMetaData();
            while (rs.next())
            {
                int i,j;
                i = columns.getColumnCount();
                for(j=0;j!=i;j++)
                {
                    data = rs.getString(columns.getColumnName(j));
                    System.out.printf("%s: %s\t",columns.getColumnName(j), data);
                }
                System.out.println();
            }
            rs.close();
        }
        catch (java.sql.SQLException e)
        {
            System.err.println("SQL error has occurred: " + e.getMessage());
        }
        return thisJob;
    }
}

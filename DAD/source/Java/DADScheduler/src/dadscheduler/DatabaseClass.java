/*
 * DatabaseClass.java
 *
 * Created on April 15, 2007, 9:50 PM
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
public class DatabaseClass {
    
    private Connection conn = null;

    
    /** Creates a new instance of DatabaseClass */
    public DatabaseClass(String URL, String Username, String Password) {

        try
        {
            Class.forName("com.mysql.jdbc.Driver").newInstance();
            conn = DriverManager.getConnection(URL, Username, Password);
        }
        catch(IllegalAccessException e)
        {
            System.err.println("Illegal access exception:"+e.getMessage());
        }
        catch(InstantiationException e)
        {
            System.err.println("Could not instantiate driver:" + e.getMessage());
        }
        catch(ClassNotFoundException e)
        {
            System.err.println("Could not find class:" + e.getMessage());
        }
        catch(SQLException e)
        {
            System.err.println("Could not connect to database:" + e.getMessage());
        }
              
    }
    public DatabaseClass() {
        this("jdbc:mysql://127.0.0.1/DAD", "root", "All4Fun");
    }
    
    public int SQLQueryNoResult(String theQuery)
    {
        int affected;
        Statement s;
        try
        {
            s = conn.createStatement();
            affected = s.executeUpdate(theQuery);
            s.close();
        }
        catch(java.sql.SQLException e)
        {
            System.err.println("SQL Exception occurred: " + e.getMessage());
            affected = -1;
        }
        finally
        {
            s = null;
        }
        return(affected);
    }
    
    public Job SQLQuery(String theQuery)
    {
        Job ThisJob;
        
        ThisJob = new Job();
        try
        {
            Statement s = conn.createStatement();
            ResultSet rs;
            s.executeQuery(theQuery);
            rs = s.getResultSet();
            if(!rs.next()) { return null; } // Job deleted while running?
            ThisJob.SetDay(rs.getInt("day"));
            ThisJob.SetHour(rs.getInt("hour"));
            ThisJob.SetMin(rs.getInt("min"));
            ThisJob.SetMonth(rs.getInt("month"));
            ThisJob.SetNextStart(rs.getInt("next_start"));
            ThisJob.SetWorkingDirectory(rs.getString("path"));
            ThisJob.SetExecutable(rs.getString("package_name"));
            ThisJob.SetArgs(rs.getString("argument_1"));
            ThisJob.SetName(rs.getString("descrip"));
            ThisJob.SetJobID(rs.getInt("id_dad_adm_job"));
            ThisJob.SetLastExecTime(rs.getString("last_ran"));
            ThisJob.SetIsPersistent(rs.getBoolean("persistent"));
            
            rs.close();
            s.close();
            rs = null;
            s = null;
            return(ThisJob);
        }
        catch(java.sql.SQLException e)
        {
            System.err.println("SQL Exception occurred: " + e.getMessage());
            e.printStackTrace();
            return(null);
        }
    }
}

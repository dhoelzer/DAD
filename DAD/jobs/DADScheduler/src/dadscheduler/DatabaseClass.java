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
    private String username = "root";
    private String password = "All4Fun";
    private String connectionURL = "jdbc:mysql://127.0.0.1/DAD";

    
    /** Creates a new instance of DatabaseClass */
    public DatabaseClass() {
        try
        {
            Class.forName("com.mysql.jdbc.Driver").newInstance();
            conn = DriverManager.getConnection(connectionURL, username, password);
        }
        catch (Exception e)
        {
            System.err.println("Could not connect to database server");
        }
    }
    
    public int SQLQueryNoResult(String theQuery)
    {
        int affected;
        try
        {
            Statement s = conn.createStatement();
            affected = s.executeUpdate(theQuery);
            s.close();
        }
        catch(java.sql.SQLException e)
        {
            System.err.println("SQL Exception occurred: " + e.getMessage());
            affected = -1;
        }
        return(affected);
    }
    
    public ResultSet SQLQuery(String theQuery)
    {
        ResultSet rs;
        try
        {
            Statement s = conn.createStatement();
            s.executeQuery(theQuery);
            rs = s.getResultSet();
            s.close();
        }
        catch(java.sql.SQLException e)
        {
            System.err.println("SQL Exception occurred: " + e.getMessage());
            return(null);
        }
        return(rs);
    }
}

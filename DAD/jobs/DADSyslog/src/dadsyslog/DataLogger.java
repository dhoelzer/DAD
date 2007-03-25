/*
 * DataLogger.java
 *
 * Created on February 5, 2007, 8:33 AM
 *
 * To change this template, choose Tools | Template Manager
 * and open the template in the editor.
 */

package dadsyslog;

import java.io.*;
import java.util.*;

/**
 *
 * @author dhoelzer
 */
public class DataLogger {
    
    private long Mark;
    
    /** Creates a new instance of DataLogger */
    public DataLogger() 
    {
        Date timestamp = new Date();
    // Generate a file name
    // Open the file
    // Mark the time
     Mark = timestamp.getTime();
    }
    

    public boolean LogData(String Message)
    {
        Date Timestamp = new Date();
        // Spew data
        System.out.print(Timestamp.getTime() + " " + Message);
        // Check time
        if((Timestamp.getTime() - Mark > 300000))
        {
            System.out.println(" -- Time to carve the log --");
            Mark = Timestamp.getTime();
        }
        // Elapsed?  New file, spawn carver
        return true;
    }
}

/*
 * DataLogger.java
 *
 * Created on February 5, 2007, 8:33 AM
    #    Copyright (C) 2006, David Hoelzer/Cyber-Defense.org
    #
    #    This program is free software; you can redistribute it and/or modify
    #    it under the terms of the GNU General Public License as published by
    #    the Free Software Foundation; either version 2 of the License, or
    #    (at your option) any later version.
    #
    #    This program is distributed in the hope that it will be useful,
    #    but WITHOUT ANY WARRANTY; without even the implied warranty of
    #    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    #    GNU General Public License for more details.
    #
    #    You should have received a copy of the GNU General Public License
    #    along with this program; if not, write to the Free Software
    #    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA

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
    private String filename;
    private File DataFile;
    private FileWriter OutputStream;
    /** Creates a new instance of DataLogger */
    public DataLogger() 
    {
        Date timestamp = new Date();
    // Mark the time
        Mark = timestamp.getTime();
    // Generate a file name
        filename = "syslog." + Mark;
    // Open the file
        DataFile = new File("C:\\DAD\\jobs\\LogStaging\\", filename);
        try
        {
            DataFile.createNewFile();
            OutputStream = new FileWriter(DataFile);
        }
        catch (Exception e) // Lazy TODO
        {
            System.out.println("Error opening file:" + e.getMessage());
        }
    }
    

    public boolean LogData(String Message)
    {
        Date Timestamp = new Date();
        // Spew data
        try
        {
            OutputStream.write(Timestamp.toString()+" "+Message);
            //System.out.print(Timestamp.getTime() + " " + Message);
            // Check time
            if((Timestamp.getTime() - Mark > 300000))
            {
                Mark = Timestamp.getTime();
                OutputStream.close();
                File rename = new File("C:\\DAD\\jobs\\LogsToProcess\\"+filename);
                DataFile.renameTo(rename);
                filename = "syslog." + Mark;
            // Open the file
                DataFile = new File("C:\\DAD\\jobs\\LogStaging\\", filename);
                try
                {
                    DataFile.createNewFile();
                    OutputStream = new FileWriter(DataFile);
                }
                catch (Exception e) // Lazy TODO
                {
                    System.out.println("Error opening file:" + e.getMessage());
                }
            }
            // Elapsed?  New file, spawn carver
            return true;
        }
        catch(Exception e) // Lazy TODO
        { ; }
        return false;
    }
}

/*
 * SpawnCarver.java
 *
 * Created on February 5, 2007, 8:45 AM
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
 *
 * This object allows the job scheduler to spawn an external Perl
 * data carver to push syslog data into the DAD database.
 */
public class SpawnCarver extends Thread implements Runnable {
    private String FileToProcess;
    private Process CarverProcess;
    private Date TimeStarted;
    
    /** Creates a new instance of SpawnCarver
     *
     * Constructor requires String Datafile where Datafile is the name of
     * the text file containing the Syslog data to process.
     */
    public SpawnCarver(String DataFile) {
        FileToProcess = DataFile;
    }
 
    public void run()
    {
        try {
        CarverProcess = new ProcessBuilder("carver.pl", FileToProcess).start();
        // The following should be changed to real error checking - TODO
        }
        catch (Exception err)
        {
            err.printStackTrace();
        }
        TimeStarted = new Date();
    }
    
    /*
     * IsRunning returns the current status of the spawned process.  This
     * status is found by attempting to throw an error based on the exit code
     * for the process in question.
     */
    public boolean IsRunning()
    {
        boolean bRunning;
        try
        {
            if(CarverProcess.exitValue() == 0)
            {
                bRunning = false;
            }
            else // Throws exception - should never run this code
            {
                bRunning = true;
            }         
        }
        catch(IllegalThreadStateException eITSE)
        {
            bRunning = true;
        }
        return bRunning;
    }
    
    /*
     * KillProcess allows an external object to terminate the running process.
     * For instance, the scheduler can use TimeRunning to determine how long
     * the process has been running.  If too much time has passed, the process
     * can be explicitly terminated and the log file brought to the attention
     * of the administrator for manual handling.
     */
    public void KillProcess()
    {
        CarverProcess.destroy();
    }
    
    /* TimeRunning returns the number of seconds that have elapsed since the
     * process spawned.
     */
    long TimeRunning()
    {
        Date Now = new Date();
        long difference = Now.getTime() - TimeStarted.getTime();
        difference /= 1000;
        return difference;
    }
}

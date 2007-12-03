/*
 * SpawnProcess.java
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

package dadscheduler;


import java.io.*;
import java.util.*;

/**
 *
 * @author dhoelzer
 *
 * This object allows the job scheduler to spawn an external process.
 */
public class SpawnProcess extends Thread implements Runnable {
    private Process SpawnedProcess;
    private Date TimeStarted;
    private Job thisJob;
    
    public String QueryDescription()
    {
        return thisJob.GetName();
    }
    public int QueryJobID()
    {
        return thisJob.QueryJobID();
    }
    /** Creates a new instance of SpawnProcess
     *
     * Constructor requires the executable and two arguments.  The arguments
     * may be blank.
     */
    public SpawnProcess(Job DoThis) {
        thisJob = DoThis;
        TimeStarted = new Date();
    }
 
    public void run()
    {
        ProcessBuilder proc;
        try
        {
            if(Main.isDebug())
            {
                System.out.println("\tSpawning "+ thisJob.GetExecutable() + " with "+ thisJob.GetLastExecTime());
            }
            proc = new ProcessBuilder(thisJob.GetExecutable(), thisJob.GetArg1(),
                    thisJob.GetLastExecTime());
            proc.directory(thisJob.GetWorkingDirectory());
            SpawnedProcess = proc.start();
        }
        catch(IOException err)
        {
            err.printStackTrace();
        }
        
    }
    
    /*
     * IsRunning returns the current status of the spawned process.  This
     * status is found by attempting to throw an error based on the exit code
     * for the process in question.
     */
    public boolean IsRunning()
    {
        try
        {
            if(SpawnedProcess.exitValue() != -999)
            {
                if(Main.isDebug())
                {
                    System.out.println("Exit Value for "+this.QueryDescription()+" is " + SpawnedProcess.exitValue());
                }
                if(SpawnedProcess.exitValue() != 0)
                {
                    
                }
                return false;
            }
            else // Throws exception - should never run this code
            {
                //return true;
            }         
        }
        catch(IllegalThreadStateException eITSE)
        {
            return true;
        }
        catch(IllegalMonitorStateException eIMSE)
        {
            return true;
        }
        catch(NullPointerException npe)
        {
            return true;
        }
        return true;
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
        if(Main.isDebug())
        {
            System.out.println("\t\tKilling Process...");
        }
        SpawnedProcess.destroy();
        if(Main.isDebug())
        {
            System.out.println("\t\tProcess killed.");
        }
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

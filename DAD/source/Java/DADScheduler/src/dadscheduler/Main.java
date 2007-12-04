/*
 * Main.java
 *
 * Created on February 27, 2007, 9:00 PM
 *
 * To change this template, choose Tools | Template Manager
 * and open the template in the editor.
 */

package dadscheduler;
import java.util.*;

/**
 *
 * @author dhoelzer
 *  
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
    
 */
public class Main {
    
    static private boolean DEBUG = true;
    static private ScheduleDBInterface schedule;
    static private String Version="0.3";
    static private ArrayList<SpawnProcess> processes;
    static private boolean KeepRunning;
    
    public static void StopRunning()
    {
        KeepRunning = false;
    }
    
    /** Creates a new instance of Main */
    public Main() {
    }
    
    private static void JobFinished(int job)
    {
        if(DEBUG)
        {
            System.out.println("Killing JobID: " + job);
        }
        schedule.SetFinished(job);
        schedule.Reschedule(job);
    }
    /**
     * @param args the command line arguments
     */
    public static void main(String[] args) {
        // TODO code application logic here
        Job DoThis;
        SpawnProcess process;
        processes = new ArrayList<SpawnProcess>();

        KeepRunning = true;
        try
        {
            new Shutdown().runProgram();
            schedule = new ScheduleDBInterface();
            System.out.println("Copyright (C) 2007, David Hoelzer/Cyber-Defense.org");
            System.out.println("DAD Scheduler (v"+Version+") now operational.");
            System.out.println("---------------------------------------------------");
            System.out.println("Starting persistent jobs");

            schedule.ClearIsRunning();
            DoThis = schedule.GetPersistentJobs();
            while(DoThis != null)
            {
                if(DEBUG)
                {
                    System.out.println("In persistent loop");
                }
                System.out.println("\tStarting "+DoThis.GetName());
                process = new SpawnProcess(DoThis);
                process.start();
                processes.add(process);
                DoThis = schedule.GetPersistentJobs();
            }
            System.out.println("Normal operation begins.");
            // Persistent jobs started.
            while(KeepRunning)
            {
                if(DEBUG)
                {
                    System.out.println("Main while loop");
                }

                DoThis = schedule.GetNextJob();
                if(DoThis != null)
                {
                    if(DEBUG)
                    {
                        System.out.println("\tJob triggered");
                    }
                    process = new SpawnProcess(DoThis);
                    process.start();
                    processes.add(process);
                }
                else
                {
                    try
                    {
                        DoThis=null;
                        Thread.sleep(10000);
                        if(DEBUG)
                        {
                            System.out.println("Sleeping");
                        }
                    }
                    catch (InterruptedException e)
                    { 
                        if(DEBUG)
                        {
                            System.out.println("Inner catch in main.  Throws exception");
                        }
                        
                        System.out.print("Process Interrupted");
                        throw(e); 
                    }
                }
                PruneDeadJobs(processes);
            }
        }
        catch(InterruptedException e)
        {
            System.out.println("Caught exception: "+e.getMessage());
        }
        catch(Exception e)
        {
            System.out.println("Caught unhandled exception: "+e.getMessage());
            e.printStackTrace();
        }
        finally
        {
            if(DEBUG)
            {
                System.out.println("In finally for main");
            }
            System.out.println("Terminating running jobs:");
            KillAllJobs();            
            if(DEBUG)
            {
                System.out.println("All jobs killed");
            }
            
        }
    }

    public static void KillAllJobs()
    {
        SpawnProcess aProcessList[] = new SpawnProcess[processes.size()];
        aProcessList = processes.toArray(aProcessList);
        System.out.println("Jobs to kill: " + processes.size());
        for(SpawnProcess i : aProcessList)
        {
            System.out.println("\tPreparing to kill " + i.QueryJobID() + ": " + 
                    i.QueryDescription() + 
                    " is " + (i.IsRunning() == true ? "running" : "dead"));
            i.KillProcess();
            JobFinished(i.QueryJobID());
            processes.remove(i);
        }
        System.out.println("All Jobs Killed");
    }
    
    public static boolean isDebug()
    {
        return DEBUG;
    }
    private static void PruneDeadJobs(ArrayList<SpawnProcess> ProcessList)
    {
        SpawnProcess aProcessList[] = new SpawnProcess[ProcessList.size()];
        aProcessList = ProcessList.toArray(aProcessList);
        if(DEBUG)
        {
            System.out.println("------------------");
            System.out.println("Running jobs: " + ProcessList.size());            
        }
        for(SpawnProcess i : aProcessList)
        {
            if(DEBUG)
            {
                System.out.println("\t" + i.QueryJobID() + ": " + i.TimeRunning() +
                   " seconds : "+ i.QueryDescription() + 
                   " is " + (i.IsRunning() == true ? "running" : "dead"));
            }
            if(! i.IsRunning())
            {
                JobFinished(i.QueryJobID());
                ProcessList.remove(i);
            }
        }
    }
    
}

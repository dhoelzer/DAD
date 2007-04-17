/*
 * Main.java
 *
 * Created on February 27, 2007, 9:00 PM
 *
 * To change this template, choose Tools | Template Manager
 * and open the template in the editor.
 */

package dadscheduler;

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
    
    static private ScheduleDBInterface schedule;

    /** Creates a new instance of Main */
    public Main() {
    }
    
    private static void JobFinished(int job)
    {
        schedule.SetFinished(job);
        schedule.Reschedule(job);
    }
    /**
     * @param args the command line arguments
     */
    public static void main(String[] args) {
        // TODO code application logic here
        Job DoThis;
        SpawnProcess processes[] = new SpawnProcess[256];
        int running_jobs = 0;
        
        schedule = new ScheduleDBInterface();
        System.out.printf("Starting\n");
        while(1==1)
        {
            DoThis = schedule.GetNextJob();
            if(DoThis.exists())
            {
                running_jobs ++;
                SpawnProcess process = new SpawnProcess(DoThis.GetExecutable());
                process.SetJobID(DoThis.QueryJobID());
                process.start();
                processes[running_jobs] = process;
                System.out.println("Job: " + process.IsRunning());
                System.out.println("Array: " + processes[running_jobs].IsRunning());
            }
            else
            {
                try
                {
                    DoThis=null;
                    Thread.sleep(10000);
                }
                catch (Exception e)
                { ; }
            }
            System.out.println("Running jobs: " + running_jobs);
            for(int i = 1; i <= running_jobs; i++)
            {
                System.out.println("PID: "+i+"\t"+processes[i].IsRunning());
                if(! processes[i].IsRunning())
                {
                    if(i == running_jobs)
                    {
                        JobFinished(processes[i].QueryJobID());
                    }
                    else
                    {
                        System.out.println("Need to kill a job but it's not the last one");
                    }
                }
            }
            System.out.println("Looping");
        }
    }
    
}

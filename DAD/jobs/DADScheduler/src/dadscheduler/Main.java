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
    
    static private ScheduleDBInterface schedule;

    /** Creates a new instance of Main */
    public Main() {
    }
    
    private static void JobFinished(int job)
    {
//        System.out.println("Killing JobID: " + job);
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
        ArrayList<SpawnProcess> processes = new ArrayList<SpawnProcess>();
                
        schedule = new ScheduleDBInterface();
        System.out.println("Copyright (C) 2007, David Hoelzer/Cyber-Defense.org");
        System.out.println("DAD Scheduler now operational.");
        while(1==1)
        {
            DoThis = schedule.GetNextJob();
            if(DoThis.exists())
            {
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
                }
                catch (Exception e)
                { ; }
            }
            PruneDeadJobs(processes);
        }
    }
    
    private static void PruneDeadJobs(ArrayList<SpawnProcess> ProcessList)
    {
        SpawnProcess aProcessList[] = new SpawnProcess[ProcessList.size()];
        aProcessList = ProcessList.toArray(aProcessList);
//        System.out.println("Running jobs: " + ProcessList.size());
        for(SpawnProcess i : aProcessList)
        {
//            System.out.println("\t" + i.QueryJobID() + ": " + 
//                    i.QueryDescription() + 
//                    " is " + (i.IsRunning() == true ? "running" : "dead"));
            if(! i.IsRunning())
            {
                JobFinished(i.QueryJobID());
                ProcessList.remove(i);
            }
        }
//        System.out.println("------------------");
    }
    
}

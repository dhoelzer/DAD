/*
 * Job.java
 *
 * Created on April 15, 2007, 10:08 PM
 *
 * To change this template, choose Tools | Template Manager
 * and open the template in the editor.
 */
package dadscheduler;
import java.io.*;


/**
 *
 * @author dhoelzer
 */
public class Job {
    
    private String name;
    private String executable;
    private String arg1;
    private String arg2;
    private int next_start;
    private int min;
    private int hour;
    private int day;
    private int month;
    private String last_run;
    private int db_job_ID;
    private boolean exists;
    private File WorkingDirectory;

    
    /** Creates a new instance of Job */
    public Job() {
        name = "Null Job";
        executable = "";
        arg1 = "";
        arg2 = "";
        db_job_ID = -1;
        next_start = 0;
        last_run = "0";
        exists = false;
        WorkingDirectory = new File(".");
    }
    public void SetNextStart(int x)
    {
        next_start = (x >= 0 ? x : 0);
    }
    
    public void SetMin(int x)
    {
        min = (x >= 0 ? x : 0);
    }
    
    public void SetHour(int x)
    {
        hour = (x >= 0 ? x : 0);
    }
    
    public void SetDay(int x)
    {
        day = (x >= 0 ? x : 0);
    }
    
    public void SetMonth(int x)
    {
        month = (x >= 0 ? x : 0);
    }
    
    public int GetNextStart()
    {
        return next_start;
    }
    
    public int GetMin()
    {
        return min;
    }
    
    public int GetHour()
    {
        return hour;
    }
    
    public int GetDay()
    {
        return day;
    }
    
    public int GetMonth()
    {
        return month;
    }
    
    public String SetLastExecTime(String x)
    {
        last_run = (x==null? "0" : x);
        return last_run;
    }
    
    public String GetLastExecTime()
    {
        return last_run;
    }
    
    public boolean exists()
    {
        return exists;
    }
    
    public int SetJobID(int x)
    {
        db_job_ID = x;
        return db_job_ID;
    }
    
    public int QueryJobID()
    {
        return db_job_ID;
    }
    
    public String SetName(String x)
    {
        name = x;
        return(name);
    }
    
    public String SetExecutable(String x)
    {
        exists = true;
        executable = x;
        return(executable);
    }
    
    public void SetArgs(String x)
    {
        arg1 = x;
    }
    
    public void SetArgs(String x, String y)
    {
        arg1 = x;
        arg2 = y;
    }

    public int SetRuntime(int x)
    {
        next_start = x;
        return next_start;
    }
    
    public String GetName()
    {
        return name;
    }
    
    public File SetWorkingDirectory(String x)
    {
        WorkingDirectory= new File(x);
        return WorkingDirectory;
    }
    
    public File GetWorkingDirectory()
    {
        return WorkingDirectory;
    }
    public String GetExecutable()
    {
        return executable;
    }
    
    public String GetArg1()
    {
        return arg1;
    }
    
    public String GetArg2()
    {
        return arg2;
    }
    
    public int GetRuntime()
    {
        return next_start;
    }
}

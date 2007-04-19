/*
 * Job.java
 *
 * Created on April 15, 2007, 10:08 PM
 *
 * To change this template, choose Tools | Template Manager
 * and open the template in the editor.
 */

package dadscheduler;

/**
 *
 * @author dhoelzer
 */
public class Job {
    
    private String name;
    private String executable;
    private String arg1;
    private String arg2;
    private int runtime;
    private String last_run;
    private int db_job_ID;
    private boolean exists;
    
    /** Creates a new instance of Job */
    public Job() {
        name = "Null Job";
        executable = "";
        arg1 = "";
        arg2 = "";
        db_job_ID = -1;
        runtime = 0;
        exists = false;
    }
    
    public String SetLastExecTime(String x)
    {
        last_run = x;
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
        runtime = x;
        return runtime;
    }
    
    public String GetName()
    {
        return name;
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
        return runtime;
    }
}

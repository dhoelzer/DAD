/*
 * ScheduleDBInterface.java
 *
 * Created on April 15, 2007, 10:06 PM
 *
 * To change this template, choose Tools | Template Manager
 * and open the template in the editor.
 */

package dadscheduler;

/**
 *
 * @author dhoelzer
 */
public class ScheduleDBInterface {
    
    private DatabaseClass dbo;
    
    /** Creates a new instance of ScheduleDBInterface */
    public ScheduleDBInterface() {
        dbo = new DatabaseClass();
    }
    
    public Job GetNextJob()
    {
        Job thisJob = new Job();
        String SQL = "SELECT * FROM dad_sys_"
        
        return thisJob;
    }
}

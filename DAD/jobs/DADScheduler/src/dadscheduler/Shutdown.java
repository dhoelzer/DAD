/*
 * Shutdown.java
 *
 * Created on April 28, 2007, 9:35 PM
 *
 * To change this template, choose Tools | Template Manager
 * and open the template in the editor.
 */

package dadscheduler;

/**
 *
 * @author dhoelzer
 */
public class Shutdown { 

    private boolean Running = true;
    
    public class RunWhenShuttingDown extends Thread { 
        public void run() 
        { 
            System.out.println("Control-C caught. Shutting down..."); 
            Running = false; 
            try 
            { 
                Main.StopRunning();
                Thread.sleep(2000); 
            } 
            catch (InterruptedException e) 
            { 
                e.printStackTrace(); 
            } 
            System.out.println("Shutdown handler exiting.");
        } 
    }
    
    public void runProgram() throws InterruptedException 
    { 
        Runtime.getRuntime().addShutdownHook(new RunWhenShuttingDown()); 
    } 
}
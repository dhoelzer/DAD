/*
 * Main.java
 *
 * Created on November 25, 2006, 3:23 PM
 *
 * To change this template, choose Tools | Template Manager
 * and open the template in the editor.
 */

package dadsyslog;

/**
 *
 * @author dhoelzer
 */
public class Main {
    
    /** Creates a new instance of Main */
    public Main() {
    }
    
    /**
     * @param args the command line arguments
     */
    public static void main(String[] args) {
        // TODO code application logic here
        DataLogger dlo = new DataLogger();
        UDPNetworkListener SyslogService = new UDPNetworkListener("Syslog", 514, dlo);
        
    }
    
}

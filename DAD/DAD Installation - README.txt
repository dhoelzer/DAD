Before Installing
EXTREMELY IMPORTANT:
   DAD is not a standalone program.  In order for DAD to function, you need several pieces of supporting infrastructure to be in place first.  In almost all cases we have chosen not to distribute these pieces of third party software for two reasons.  The first is so that you can determine which versions of the various software packages you choose to run.  The second is to avoid any and all redistribution licensing issues that can arise since the various pieces of software, while FOSS, are released under a variety of licenses.
   
   Before attempting to run the installation checklist/script in the DAD/Source directory, you must first install the following packages.  The order of installation is not particularly important with the exception of Apache and PHP.  Apache must be installed first for the PHP installation to go smoothly.
   MySQL – http://www.mysql.com
(The free Community version is more than sufficient.  Version 5.0 or higher.  We recommend version 5.1 or higher because of improved stored procedure support.)
   Perl – http://www.activestate.com
(Version 5.8 or higher recommended for improved thread support)
   PHP – http://www.php.net
(Version 5.2.1 or higher recommended.  Be sure to install this after your Apache server)
   Apache – http://www.apache.org
(Most current version of either the 1.3, 2.0 or 2.2 tree.  We recommend using the binary installer that includes OpenSSL support so that you can run DAD over SSL)
   Java – http://www.java.com/en/download/index.jsp
(Any Java Virtual Machine should work that is Java 2 compliant.  We recommend the most current Sun JVM available from the link above.  If you use a different brand of virtual machine it may be necessary for you to find a JDBC driver other than the one included with DAD)
Unpacking DAD
   DAD in its current incarnation comes as a ZIP file containing DAD itself, a starter data set and a number of useful jobs and alerts.  After your target server has been built, the first task is to unpack the DAD suite.  To do this, please unzip the DAD archive into C:\.  When you have done this you should have a "C:\DAD" directory structure in which you will find a copy of this file, a "Source" folder, a "Web" folder and a "Jobs" folder.  Once you have unpacked everything, you should progress through this document step by step.

   NOTE: If you are installing on a 64 bit OS, the installation path for the various supporting packages will depend on whether you are installing the 32 bit or 64 bit versions of the software.  Typically, if you install a 32 bit package, you will find that “C:\Program Files” changes to “C:\Program Files (x86)”.
MySQL
   Using the MySQL installer that you have downloaded, perform a typical install by accepting all of the defaults.  The only adjustment that we would strongly recommend is that, when prompted, you choose to include the MySQL binary directory in your executable path.
   
   The DAD database tables that will be installed are all configured to use MyISAM.  If you wish to conserve memory, you can tell the installer that you will not need InnoDB.  On the other hand, if you prefer to take advantage of the transaction based InnoDB engine, please feel free to do so.  You will need to change the database engine for the tables that you wish to store using this engine.  We will assume that if you have a strong desire for this then you likely have the expertise to change the database engine for the various tables so we will exclude specific step by step directions.
   
   On some systems we have seen that the MySQL installer will return an error when you try to “Execute” the installation of the service and configuration of the server.  If the installer informs you that the service is not enabled or there is a firewall turned on. Ensure that the firewall is off of that the port is allowed to communicate. Also, the service simply maybe slow to start, so your first troubleshooting step should be to click 'retry' on the 'error' window.
Perl
   Using the installer that you have downloaded, please complete a default installation of Perl.  You can accept all of the defaults to complete the installation most easily.  If you wish to conserve space you could exclude the sample code and documentation files.
Apache
   Using the Apache installer that you downloaded, please perform a default installation of Apache.  As the installation process is proceeding, please take note of the installation directory where the Apache files are located.  You will need to give this path to the PHP installer to facilitate the installation of PHP as an Apache module.
PHP
   AFTER Apache has been installed you should install the PHP package that you downloaded.  Using the PHP installer that you downloaded, please perform a standard installation of PHP.  During the installation process you should select support for whichever version family of Apache that you installed.  You must also configure PHP to install the GD2, MySQL and MySQLi modules.  The PHP installer will also prompt you to select the Apache configuration directory.  This is typically something like “C:\Program Files\Apache Foundation\Apache\conf”.
Recommended OS Configuration
   One of the most common questions that we hear is, “Can I run DAD on Windows XP?”  The answer is that DAD will work on any version of Microsoft Windows in the 2000 family.  This includes 2000, 2003, XP Professional, Vista and Longhorn.  Generally we recommend that you use Server 2003.  The Standard Edition of 2003 Server is just fine.  If 2003 Server is unavailable, you can certainly install DAD on a 2000 Server or even an XP or 2000 desktop, but the overall performance should be best on a Server platform.
   We recommend that you set block size of data drive to 64k to allow for better space utilization for the database.  We also recommend that the drive where the database files will reside be configured as a Dynamic Disk so that future expansion will be easily accomplished by simply adding drives to the volume set.  When DAD is installed it expects the data drive to be C.  Internally, DAD only accesses the data drive through the MySQL database API, but when reporting available space the DAD\web\config\config.php file will report on whichever drive is listed in the configuration file.  If you store the database files on a different drive we would recommend that you adjust this setting.
Completing the Installation
   The simplest way to complete the installation is to browse to the “C:\DAD\source” directory and double-click on the “Installation” VBScript file.  This script does not actually do anything other than tell you what you should do.  Up until this point we have been very reluctant to make any changes to your system.  In the future we may change over to an automated installer that can take over after you’ve installed Apache, PHP, Perl, Java and MySQL.   Simply follow the directions as prompted to complete the installation.
   
   
EXTREMELY IMPORTANT:
   As distributed, DAD has a default password of "All4Fun" configured as the password for the 'root' user in the MySQL database.  If you wish to get up and running ASAP, you might wish to set this as the password for your root user on your SQL server.  Please note that we do not -recommend- this, we simply are pointing out that you might choose to do this.  What we recommend is that you choose a good password and then create another user for DAD to operate with.  This second account should only have rights to the DAD database and tables.
   
   After the installation has been completed, you MUST modify the C:\DAD\Web\Config\dbconfig.php file to reflect the correct IP address (should you choose to install the SQL service on another server), the DAD username used to access the database and the password used by this user.  This same change needs to be made to the C:\DAD\dbconfig.jv file (this is the database configuration for the various pieces of Java code) , the C:\DAD\jobs\dbconfig.ph file (this contains the database configuration for the various alerts and reports) and to the C:\DAD\jobs\Log Parser\aggregator.ph file (this contains the configuration parameters for the log aggregator).

   You must adjust the server, user and password appropriately to allow the various aspects of the DAD system to access the database.

Post Installation
DAD Credentials
   Once DAD is installed, there are a few things that you'll need to do to get up and running.  First off, you will need to either create an account under which the DAD Scheduler will run or decide whose credentials DAD will use.  Once you have done this, we recommend that you use group policy in your domain to grant this account the "Manage Security and Audit Logs" right to computers in the domain.  In most installations we would recommend applying this right for all computers, domain servers and domain controllers.  
   
   Please note:  If you wish to import logs other than the Security log, the simplest solution is to add the service account to the local administrators group for all of the systems that are monitored.  There are more difficult ways to add this capability without making the service account an administrator.  We will include details on how to configure these access control lists for Windows logs in a future release.
    
Starting the Scheduler
   If you used the installer script, it automatically starts the scheduler when it completes.  To restart the scheduler in the future (and thereby all of the scheduled jobs including the Aggregator) you will need to run the following commands:
   
   cd \DAD\jobs
   .\start_scheduler.bat
   
   We expect to push out the Scheduler as a service in the very next release which will eliminate the need for this step.  Until then, we recommend that you create a job using the Windows scheduling service that will start this batch script on startup using the credentials that you have created for DAD.

Adding Servers and Computers to Process
   The final step in setting up DAD is to add systems to the list of servers to aggregate logs from.  To add servers and workstations, log in as an administrator.  Under the “Maintenance” tab, select the “Systems” option.  Enter all of the pertinent information including, most importantly, the NETBIOS name of the system that you wish to add.  Please also include a priority value of 1 or higher.  A zero will disable collection from the host.  Lower numbers (1, for instance) indicate higher priority.  Typically, we recommend setting DCs and Global Catalog servers as priority 1.  Domain Servers would be priority 2.  Everything else would be priority 3 or more.  Once you have entered the necessary information, be sure to select which logs you wish to collect from this system.  Finally, click on the “Save as New” button to begin collections from that system.
   
   You will also want to configure all of your UNIX servers, routers, firewalls and other syslog based systems to forward their logs to the DAD server.  By default, the scheduler will start a syslog daemon.  No further interaction is required for DAD to begin to process and make available syslog data.  If you have web access logs or Dansguardian logs that you wish to process (or any other text based log), you can schedule a job to periodically drop the new logs to process into the C:\jobs\LogsToProcess directory.
    

Troubleshooting:
   1) Apache error log reports "PHP Warning:  PHP Startup: Unable to load dynamic library 'C:\\PHP\\php_mysql.dll' - The specified module could not be found.\r\n in Unknown on line 0"
   
   	This error, when the php_mysql.dll is in fact in the C:\PHP directory (and the correct version), is very misleading.  The actual problem is that "libmysql.dll" is not in the Apache\bin directory (or otherwise in the Apache path).
   
   2) I’ve added a workstation (or workstations) to the list of systems to collect data from but nothing seems to be entering the database from these systems.  What’s wrong?

This problem is caused, strangely enough, by the Windows Firewall.  Unfortunately, there is no simple granular control to change this behavior.  The simplest resolution is to either disable the firewall (not recommended unless you have some other firewall on there too) or to simply enable File Sharing in the Advanced settings.  We’re not actually sharing files, but this seems to take in all sorts of SMB communication including the logs.  In the future, if we have the energy, we’ll describe more specifically how this can be accomplished through Group Policy to only allow the DAD server to collect logs without completely opening up file sharing.  Of course, opening the file sharing ports doesn’t actually share anything; it just makes the connections possible.
   

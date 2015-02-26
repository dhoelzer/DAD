root@ezekiel:/etc/openvpn# wmic -U enclaveforensic/auditor%Password1 //507dc.enclaveforensics.com "select * from Win32_NTLogEvent "
[librpc/rpc/dcerpc_connect.c:329:dcerpc_pipe_connect_ncacn_ip_tcp_recv()] failed NT status (c00000c4) in dcerpc_pipe_connect_ncacn_ip_tcp_recv
[librpc/rpc/dcerpc_connect.c:790:dcerpc_pipe_connect_b_recv()] failed NT status (c00000c4) in dcerpc_pipe_connect_b_recv
CLASS: Win32_NTLogEvent
Category|CategoryString|ComputerName|Data|EventCode|EventIdentifier|EventType|InsertionStrings|Logfile|Message|RecordNumber|SourceName|TimeGenerated|TimeWritten|Type|User
3|ADWS Instance Events|GC-1.enclaveforensics.com|NULL|1200|1073743024|3|(GC,3268,3269)|Active Directory Web Services|Active Directory Web Services is now servicing the specified directory instance.
 
 Directory instance: GC
 Directory instance LDAP port: 3268
 Directory instance SSL port: 3269
|26459|ADWS|20150225230316.000000-000|20150225230316.000000-000|Information|(null)
3|ADWS Instance Events|GC-1.enclaveforensics.com|NULL|1200|1073743024|3|(NTDS,389,636)|Active Directory Web Services|Active Directory Web Services is now servicing the specified directory instance.
 
 Directory instance: NTDS
 Directory instance LDAP port: 389
 Directory instance SSL port: 636
|26458|ADWS|20150225230316.000000-000|20150225230316.000000-000|Information|(null)
1|ADWS Startup Events|GC-1.enclaveforensics.com|NULL|1004|1073742828|3|NULL|Active Directory Web Services|Active Directory Web Services has successfully started and is now accepting requests.|26457|ADWS|20150225230219.000000-000|20150225230219.000000-000|Information|(null)
1|ADWS Startup Events|GC-1.enclaveforensics.com|NULL|1006|1073742830|3|NULL|Active Directory Web Services|Active Directory Web Services is advertising.|26456|ADWS|20150225230219.000000-000|20150225230219.000000-000|Information|(null)
3|ADWS Instance Events|GC-1.enclaveforensics.com|NULL|1202|3221226674|1|(NTDS,389,636)|Active Directory Web Services|This computer is now hosting the specified directory instance, but Active Directory Web Services could not service it. Active Directory Web Services will retry this operation periodically.
 
 Directory instance: NTDS
 Directory instance LDAP port: 389
 Directory instance SSL port: 636
|26455|ADWS|20150225230216.000000-000|20150225230216.000000-000|Error|(null)

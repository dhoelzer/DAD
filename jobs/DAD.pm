package DAD;
use strict;
use ActiveDS;
use DBI;
use FileACL;
use FindBin qw($Bin $Script);
use Net::Ping;
use Net::Telnet;
use XML::Parser;


#######################
##TODO: 
##  - get_date_time
##     - specify format of returned date/time
##     - specify UTC or not
##  - log_event
##    - all sections need to use the new $_set_err();
##  - &$_set_err() - I want to be able to know what sub-routine call this one!!!! Then I an automatically include it in the text of the error message
##  - &$_set_err() - should this time stamp errors?
##  - &$_set_err() - should this record errors to event log? - make this optional when new() is called? Event::Carp.....
##  - need to setup default error numbers... have a hash of standard text for each default error number. that way, for standard problems, we only have to pass in default error numbers instead of error nubmer and text
##  - should we only show WARNings if a debug flg is on? (not all of them...)
##  - look into DBI:connect_cached().... will this provide the same 'looking' database handle so that we don't have to prepare all the statment again?
##  - need to test if the database is reachable - e.g. the server is up and running, but can we connect to teh database. The server might come up, but the MySQL service might still be loading.



BEGIN {
    use Exporter;

    my @ISA       = qw( Exporter );
    my @EXPORT_OK = qw(  );
    my @EXPORT    = qw(  );
}

#####################
## Global Vars
##
    my $VERSION = '0.1';

#-----------------------------------------------------------------------------#
# PRIVATE SUBROUTINES
#-----------------------------------------------------------------------------#


#####################
##  my %options = &$_import_options( @options );
##
##  - Expecting an array, where even number are element names, and odd are values
##  - Will upper case keys, but leave values
##    - keys should always be than name of your option that you are importing
##
    my $_import_options = sub {
        my %options = @_;
        my $k;
        my $v;

        while( ($k, $v) = each %options ){
            delete $options{ $k };
            $options{ uc($k) } = $v;
        }
        %options;
    };


#####################
##  $ret = $self->&$_set_err( $err_num, $err_str );
##    $err_num - int    - 0 means all is good, anything higher and there's a problem
##                        0 or empty string will resest err_num to 0 and err_str to '' (a.k.a reset error)
##    $err_str - string - text of error message
##
    my $_set_err = sub {
        my $self = shift;
        my $num  = shift;
        my $str  = shift;
        if( $num eq '' || $num == 0 ){
            $self->{ERR} = '';
            $self->{ERRSTR} = '';
        }else{
            if( $num!~/\D/ ){       # error number does not have non-digits in it
                $self->{ERR} = $num;
                chomp($str);
                if( $str eq '' ){
                    $self->{ERRSTR} = "unknown error\n";
                }else{
                    $self->{ERRSTR} = "$str\n";
                }
                warn $self->{ERRSTR} if $self->{'>DAD_PREFS>PERL_DEBUG>LEVEL'};
            }else{
                die 'DAD->&$_set_err() passed non-digit error number: [' . $num . ']';
                return 0;       ##perahps used later if we decide not to croak.
            }
        }
        return 1;
    };




#-----------------------------------------------------------------------------#
# PUBLIC SUBROUTINES
#-----------------------------------------------------------------------------#


#####################
## new DAD();
## syntax: $obj = new DAD( NO_DB => 1, NO_LDAP => 1, PREFS => 'c:/dad/jobs/dad.prefs' );
##   - NO_DB   - int    - 0 will load connection to DB [default]
##                        1 will not load connection to DB
##   - NO_LDAP - int    - 0 will load connection to LDAP [default]
##                        1 will not load connection to LDAP
##   - PREFS   - string - full path to prefs file
##                        default is "script_path/dad.prefs"
##
    sub new{
        my $proto   = shift;
        my $class   = ref( $proto ) || $proto;
        my %options = &$_import_options(@_);
        
        my @c;
        my $self = {};

        #$self->{DB_CONN_RETRIES} = 15;     #'>DAD_PREFS>DB>CONN_RETRIES'
        #$self->{DB_NAME}     = 'DAD';      #'>DAD_PREFS>DB>NAME'
        #$self->{DB_SERVER}   = 'ussrv124';  #'>DAD_PREFS>DB>SERVER'
        #$self->{DEBUG}       = 1;           #'>DAD_PREFS>PERL_DEBUG>LEVEL'
        $self->{DS}          = '';
        $self->{ERR}         = 0;
        $self->{ERR_STR}     = '';
        $self->{FILEACL}     = new FileACL;
        $self->{JOB_ID}      = '';
        $self->{NET_PING}    = Net::Ping->new('','1');
        $self->{NET_PING}->hires(1);
        $self->{NET_TELNET}  = new Net::Telnet();
        $self->{NESTED}      = 0;
        $self->{SCRIPT_NAME} = $Script;
        $self->{SCRIPT_PATH} = $Bin;
        $self->{START_DATE}  = '';
        $self->{START_DATE_TIME}  = '';
        $self->{START_TIME}  = '';

        bless( $self, $class );
        die $self->errstr() unless $self->import_prefs( $options{PREFS} || $Bin . '/dad.prefs' );

        ( $self->{START_DATE}, $self->{START_TIME} ) = $self->get_date_time();
        $self->{START_DATE_TIME} = $self->{START_DATE} . ' ' . $self->{START_TIME};

        if( $options{'NO_DB'} != 1 ){
            $self->_db_conn();
            $self->{DB_DAD_I}->do( "INSERT INTO dad_adm_log( id_dad_adm_logtype, message, eventsource, eventtime, jobstarttime ) 
              VALUES ( 
                '2', 
                '" . $self->{SCRIPT_NAME} . "', 
                '" . $self->{SCRIPT_PATH} . '/' . $self->{SCRIPT_NAME} . "', 
                '" . $self->{START_DATE_TIME} . "', 
                '" . $self->{START_DATE_TIME} . "'
              )" 
            );
        }

        $self->{JOB_ID} = $self->{DB_DAD_I}->{'mysql_insertid'};
        #ERR_Report( '3', "Job ID: [$job_id]" );

        @c = $self->get_credentials('domain');     #username, distinguishedname, password
        $self->{DS} = ActiveDS->new('',$c[1],$c[2]) if $options{'NO_LDAP'} != 1;

        $self;
    }


#####################
##  ($username, $dn, $pw) = $self->get_credentials(which_credentials);
##      which_credentials:
##          - domain
##          - db_read
##          - db_change
##          - db_root
    sub get_credentials{
        my $self   = shift;
        my $option = lc(shift);
        my $d;
        my $p;
        my $u;

        if ( $option eq 'domain' ){
            $d = $self->{'>DAD_PREFS>DOMAIN_ACCOUNT>DN'};
            $p = $self->{'>DAD_PREFS>DOMAIN_ACCOUNT>PW'};
            $u = $self->{'>DAD_PREFS>DOMAIN_ACCOUNT>NAME'};
        }elsif ( $option eq 'db_read' ){
            $d = $self->{'>DAD_PREFS>DB_ACCOUNT_READ>DN'};
            $p = $self->{'>DAD_PREFS>DB_ACCOUNT_READ>PW'};
            $u = $self->{'>DAD_PREFS>DB_ACCOUNT_READ>NAME'};
        }elsif ( $option eq 'db_change' ){
            $d = $self->{'>DAD_PREFS>DB_ACCOUNT_CHANGE>DN'};
            $p = $self->{'>DAD_PREFS>DB_ACCOUNT_CHANGE>PW'};
            $u = $self->{'>DAD_PREFS>DB_ACCOUNT_CHANGE>NAME'};
        }elsif ( $option eq 'db_root' ){
            $d = $self->{'>DAD_PREFS>DB_ACCOUNT_ROOT>DN'};
            $p = $self->{'>DAD_PREFS>DB_ACCOUNT_ROOT>PW'};
            $u = $self->{'>DAD_PREFS>DB_ACCOUNT_ROOT>NAME'};
        }else{
            $self->$_set_err(1,"DAD::get_credentials(): incorrect credential type [$option]" );
            return undef;
        }

        $self->$_set_err(0);
        return ($u,$d,$p);
    }


####################
## $self->send_email( $eSub, $eBody, $eTo, $eFrom, $eCC, $eBCC );
##
    sub send_email{
        use Net::SMTP;
        my $self = shift;
        my( $eSub, $eBody, $eTo, $eFrom, $eCC, $eBCC ) = @_;

        $eFrom = $ENV{USER} if $eFrom eq '';
        $eFrom = $ENV{USERNAME} if $eFrom eq '';
        $eTo   = 'InboxISSecurityTeam@usa.wtbts.net' if $eTo eq '';

        my $smtp = Net::SMTP->new('mail.usa.wtbts.net');

        $smtp->mail(    $eFrom );
        foreach( split/[;,]/,$eTo ){
            $smtp->to($_);
        }
        foreach( split/[;,]/,$eCC ){
            $smtp->cc($_);
        }
        foreach( split/[;,]/,$eBCC ){
            $smtp->bcc($_);
        }

        $smtp->data();
        $smtp->datasend("To: $eTo\n");          ## displayed TO names
        $smtp->datasend("Subject: $eSub\n");    
        $smtp->datasend("\n");               # have to have a blank line in between the subject and the body.
        foreach( split/\n/,$eBody ){
            $smtp->datasend($_);
            $smtp->datasend("\n");
        }
        #$smtp->datasend("$eBody");
        $smtp->dataend();

        $smtp->quit;
        return 1;
    }


###########################
##  $escaped_str = $self->sql_escape( string );
##
    sub sql_escape{
        my $self = shift;
        my( $str ) = @_;

        $str=~s/\'/\'\'/gi;
        $str=~s/\\/\\\\/gi;

        return $str;
    }


###################
## $err = $self->log_event( $type, $message )
##    Types:
##      -1   - print message to screen only
##      0    - Unknown
##      1    - Error
##      2    - Job
##      3    - Information    (default)
##      4    - Warning
##      100 - MySQL errors
##
##    Returns 1 on success, 0 on failure
##
    sub log_event{
        my $self = shift;
        my $type = shift;
        my $msg  = shift;
        my $tmp;

        if( $msg eq '' ){
            $msg = $type;
            $type = 0;
        }

        return 0 if $type eq '' || $msg eq '';

        $msg = $self->sql_escape( $msg );
        
        if( $type == -1 ){

            print $msg;

        } else {

            my @t = $self->get_date_time();
            #print "\n\nINSERT INTO dad_adm_log( TypeID, Message, EventSource, EventTime ) VALUES ( '$type', '$msg', '$Bin/$Script', '$StartDate $StartTime'\n\n";
            $tmp = $self->{DB_DAD_I}->do( "INSERT INTO dad_adm_log( id_dad_adm_logtype, message, eventsource, eventtime ) 
              VALUES ( 
                '$type', 
                '$msg', 
                '" . $self->{SCRIPT_PATH} . '/' . $self->{SCRIPT_NAME} . "', 
                '$t[0] $t[1]' 
              )" 
            );

            if( !$tmp ){
                $self->send_email( "DAD Job Failure: " . $self->{SCRIPT_NAME} . ' log_event failed', "ERROR inserting [$msg] into [dad_adm_log]\n\nDBI ERROR: $DBI::errstr\n\nSCRIPT PATH: " . $self->{SCRIPT_PATH} . '/' . $self->{SCRIPT_NAME} );
                return 0;
            }

        }

        return 1;
    }


###########################
## 
    sub _prepare_stmts{
        my $self = shift;
        
        return 1;
    }


###########################
##  ($date, $time) = $self->get_date_time( seconds);
##
    sub get_date_time{
        my $self = shift;
        my $my_date;
        my $my_time;
        my $time;

        $time = shift || time;

        my ( $sec,$min,$hr,$mday,$mon,$year,$wday,$yday,$isdst ) = localtime( $time );
        $sec  = '0' . $sec if length($sec) == 1;
        $min  = '0' . $min if length($min) == 1;
        $hr   = '0' . $hr if length($hr) == 1;
        $mday = '0' . $mday if length($mday) == 1;
        $mon  = $mon + 1;
        $mon  = '0' . $mon if length($mon) == 1;
        $year = $year+1900;

        $my_date = "$year-$mon-$mday";
        $my_time = "$hr:$min:$sec";

        return ( $my_date, $my_time );
    }


###########################
## 
    sub _handler{
        my $self = shift;
        
        return 1;
    }


###########################
## 
    sub _db_conn{
        my $self = shift;
        my $cnt;
        my @u;

        sleep 2;    ##put a little pause in here; sometimes the ping fails on first attempt... not fully initialized yet?
        PING: while(! $self->ping( client => $self->{'>DAD_PREFS>DB>SERVER'}, timeout => 3 ) ){       ##will do a slow ping (3 seconds)
            $cnt++;
            $self->$_set_err(
                1,
                $self->{'>DAD_PREFS>DB>SERVER'} . " has been unreachable $cnt times via ping." . ( $cnt == $self->{'>DAD_PREFS>DB>CONN_RETRIES'} ? "\n" : " Will retry in 60 seconds.\n" )
            );
            die $self->errstr if $cnt == $self->{'>DAD_PREFS>DB>CONN_RETRIES'};
            sleep 60;
        }
        $cnt = 0;
        while(! $self->telnet_ping( host=>$self->{'>DAD_PREFS>DB>SERVER'}, port=>$self->{'>DAD_PREFS>DB>PORT'}, timeout=>3 ) ){
            $cnt++;
            $self->$_set_err(
                1,
                $self->{'>DAD_PREFS>DB>SERVER'} . " has been unreachable $cnt times via telnet on port " . $self->{'>DAD_PREFS>DB>PORT'} . '.' . ( $cnt == $self->{'>DAD_PREFS>DB>CONN_RETRIES'} ? "\n" : " Will retry in 60 seconds.\n" )
            );
            die $self->errstr if $cnt == $self->{'>DAD_PREFS>DB>CONN_RETRIES'};
            sleep 60;
        }
        $cnt = 0;

        @u = $self->get_credentials( 'db_change' );
        $self->{DB_DAD_I} = DBI->connect( 'DBI:mysql:database=' . $self->{'>DAD_PREFS>DB>NAME'} . ';host='. $self->{'>DAD_PREFS>DB>SERVER'} . ';port=' . $self->{'>DAD_PREFS>DB>PORT'}, $u[0], $u[2] );
        if( $DBI::err ne '' ){
            my $line = __LINE__;
            my $msg = $self->{SCRIPT_NAME} . " failed to connect to the database\n\nDBI ERROR: $DBI::errstr\n\nSCRIPT PATH: " . $self->{SCRIPT_PATH} . '/' . $self->{SCRIPT_NAME};
            $self->$_set_err(1,$msg);
            $self->send_email( "DAD Job Failure: " . $self->{SCRIPT_NAME}, $msg );
            return 0;
        }

        @u = $self->get_credentials( 'db_read' );
        $self->{DB_DAD_S} = DBI->connect( 'DBI:mysql:database=' . $self->{'>DAD_PREFS>DB>NAME'} . ';host='. $self->{'>DAD_PREFS>DB>SERVER'} . ';port=' . $self->{'>DAD_PREFS>DB>PORT'}, $u[0], $u[2] );
        if( $DBI::err ne '' ){
            my $line = __LINE__;
            my $msg = $self->{SCRIPT_NAME} . " failed to connect to the database\n\nDBI ERROR: $DBI::errstr\n\nSCRIPT PATH: " . $self->{SCRIPT_PATH} . '/' . $self->{SCRIPT_NAME};
            $self->$_set_err(1,$msg);
            $self->send_email( "DAD Job Failure: " . $self->{SCRIPT_NAME}, $msg );
            return 0;
        }

        $self->$_set_err(0);
        return 1;
    }


#sub email

####################
## %ini_values = $self->import_ini( $path_to_ini );
##    return 1 on success, 0 on failure.
##    check $self->err and $self->errstr for errors.
##
    sub import_ini{
	    my $self = shift;
        my $err;
        my $file_ini = shift;
        my $line;
        my @line;
        my $tmp;
        my %tmp;

        $self->$_set_err(0);

        if( ! -f$file_ini ){
            $self->$_set_err(1,"DAD::import_ini(): could not find INI: [$file_ini]");
            return undef;
        }
        $file_ini = lc($file_ini);
        $err = open(FILE_INI,"$file_ini");
        if(!$err){
            $self->$_set_err(1,"DAD::import_ini(): could not open INI: [$file_ini]");
            return undef;
        }
        INILINE: while($line=<FILE_INI>){
            chomp $line;
            next INILINE if $line!~/.+=.+/;
            @line = split(/=/,$line);
            $tmp = lc(shift @line);
            $_ = join('=',@line);
            ## get rid of leading and trailing spaces
            $tmp =~ s/\s*$//;
            $_   =~ s/\s*$//;
            $tmp =~ s/^\s*//;
            $_   =~ s/^\s*//;
            $tmp{$tmp} = $_;
        }
        close FILE_INI;
        %tmp;
    }


####################
## $err = $self->export_ini( $path_to_ini, %ini_values );
##
    sub export_ini{
	    my $self = shift;
        my $file_ini = shift;
        my %values = @_;
        my $err;

        $self->$_set_err(0);

        $err = open(FILE_INI,">$file_ini");
        if(!$err){
            $self->$_set_err(1,"DAD::export_ini(): Can't open for writing: [$file_ini]");
            return undef;
        }
        foreach( keys %values ){
            print FILE_INI "$_=$values{$_}\n" if $_ ne '';
        }
        close FILE_INI;
        %values;
    }

    
####################
## $self->ping();
## syntax: ($ret, $dur, $ip) = $self->ping( CLIENT => '10.1.1.100', TIMEOUT => '2' );
##    Pings host and returns success or fail, along with duration.
##      In scalar context, returns 1 or 0 (same as undef). In array context,
##      returns ($ret,$dur,$ip).
##       - CLIENT   - string - can either be DNS name or IP address
##       - TIMEOUT - float  - has to be great than zero
##       - $ret     - bit    - 0 || undef means the host is unreachable
##       - $dur     - float  - duration of ping (how long it too client to repsond
##       - $ip      - string - ip of host (in case you used DNS name in CLIENT value)
##
    sub ping{
        my $self    = shift;
        my %options = &$_import_options(@_);
        $self->$_set_err(0) if $self->{NESTED} != 1;
        if( $options{CLIENT} eq ''){
            $self->$_set_err(1,'DAD->ping() - CLIENT not specified');
        }else{
            return $self->{NET_PING}->ping( $options{CLIENT}, ( $options{TIMEOUT} > 0 ? $options{TIMEOUT} : 1 ) );
        }
    }



####################
## $return = $self->telnet_ping();
## syntax: $self->telnet_ping( HOST => '10.1.1.100', PORT => '80', TIMEOUT => 3 )
##   ( see Perl Net::Telnet for details on options for host, port, timeout (only options supported) )
##   - HOST    - string - either the IP or the DNS of the target. Required.
##   - PORT    - int    - the port number to connect to on the HOST. Default is 23.
##   - TIMEOUT - int    - the timeout to wait for giving up on trying to connect. Default is 10.
##   - $return - bit    - 0 for failure
##                        1 for success
##   - call $self->err and $self->errstr for returned errors
##
    sub telnet_ping{
        my $self = shift;
        my %options = &$_import_options(@_);
        my $o;
        my %opts;
        $self->$_set_err(0) if $self->{NESTED} != 1;
        if( $options{HOST} eq ''){
            $self->$_set_err(1,'DAD->telnet_ping() - HOST not specified');
        }else{
            foreach $o ( keys %options ){
                $opts{$o} = $options{$o} if $o=~/^(host|port|timeout)$/i;
            }
            undef $o;
            $opts{errmode}='return';
            $o = $self->{NET_TELNET}->open(%opts);
            $self->$_set_err(1,'DAD->telnet_ping() - ' . $self->{NET_TELNET}->errmsg) if !$o;
            return $o;
        }
    }


####################
##  $self->err();
##  syntax: $err_num = $send->err();
##    - $err_num - int - zero means no error [readonly]
##                       one or higher means there's an error. No real set of error codes defined yet
##                       use $self->errstr() to see description of error
##
    sub err{
        if( ref($_[0]) ne 'DAD' ){
            warn "DAD::err() can only be called via DAD->err()\n";
        }else{
            return $_[0]->{ERR};
        }
    }


####################
##  $self->errstr();
##  syntax: $err_str = $send->errstr();
##    - $err_str - string - text of the error [readonly]
##
    sub errstr{
        if( ref($_[0]) ne 'DAD' ){
            warn "DAD::errstr() can only be called via DAD->errstr()\n";
        }else{
            return $_[0]->{ERRSTR};
        }
    }


####################
##  $self->import_prefs();
##  syntax: $return = $self->import_prefs( FILE => 'full/path/to/prefs_file' );
##    - FILE    - string - full path to the prefs file. If empty, will check $self. If that's empty, will check current script directory for 'dad.prefs' file.
##    - $return - bit    - 1 for success
##                         0 for failure; see $self->errstr() for full error string
##
    sub import_prefs{
        my $self       = shift;
        my %options = &$_import_options(@_);
        if( $options{FILE} ){
            $self->prefs_path($options{FILE});
        }elsif( $self->prefs_path() ){
            $options{FILE} = $self->prefs_path();
        }elsif( -f "$self->{SCRIPT_PATH}/dad.prefs" ){
            $options{FILE} = "$self->{SCRIPT_PATH}/dad.prefs";
            $self->prefs_path($options{FILE});
        }else{
            $self->$_set_err(1,"DAD::import_prefs(): no preference file specified");
            return 0;
        }
        if( ! -f $options{FILE} ){
            $self->$_set_err(1,"DAD::import_prefs(): could not find preference file: [$options{FILE}]");
            return 0;
        }
        my $p = new XML::Parser(
            Handlers => {
                Start => sub{
                               $_[0]->{current_node} .= '>' . uc($_[1]);
                            },
                End   => sub{
                                my $n = uc($_[1]);
                                $_[0]->{current_node}=~s/>$n$//;
                            },
                Char  => sub{
                                ${$_[0]->{DAD}}->{$_[0]->{current_node}} = $_[1] if $_[1]=~/\S/;
                            }
            }
        );
        $p->{DAD} = \$self;
        eval{ $p->parsefile($options{FILE}); };
        if( $@ ){
            $self->$_set_err(1,"DAD::import_prefs(): parse errors in preference file [$options{FILE}]");
            return 0;
        }
        $self->$_set_err(0);
        return 1;
    }


####################
##  $self->prefs_path();
##    get: $path = $self->prefs_path();
##    put: $old_path = $self->prefs_path($new_path);
##    Return undef if file does not exist. Check $self->errstr for errors.
##
    sub prefs_path{
        my $self     = shift;
        my $new = shift;
        my $old;
        if( $new ){
            $new=~s|\\|\/|g;
            if( ! -f $new ){
                $self->$_set_err(1,"DAD::prefs_path(): could not find preference file: [$new]");
                return undef;
            }else{
                $old = $self->{PREFS_PATH};
                $self->{PREFS_PATH} = $new;
                return $old || ' ';
            }
        }else{
            return $self->{PREFS_PATH};
        }
    }


###########################
## 
    DESTROY{
        my $self = shift;
        my @tmp;
        my @time;

        $self->{PING}->close();
        @time = $self->get_date_time();

        ## update log entry with completion time
        @tmp = $self->{DB_DAD_S}->selectrow_array( "SELECT id_dad_adm_log FROM dad_adm_log WHERE id_dad_adm_log = " . $self->{JOB_ID} );
        if( $tmp[0] == $self->{JOB_ID} ){
            $self->{DB_DAD_I}->do( "UPDATE dad_adm_log SET jobstoptime = '$time[0] $time[1]' WHERE id_dad_adm_log = " . $self->{JOB_ID} );
        } else {
            #$obj{db_dad_I}->do( "INSERT INTO dad_adm_log( id_dad_adm_logtype, message, eventsource, eventtime, jobstarttime, jobstoptime ) VALUES ( '2', '$job_name', '$Bin/$Script', '$StartDate $StartTime', '$StartDate $StartTime', '$EndD $EndT' )" );
            $self->{DB_DAD_I}->do( "INSERT INTO dad_adm_log( id_dad_adm_logtype, message, eventsource, eventtime, jobstarttime, jobstoptime ) 
              VALUES ( 
                '2', 
                '" . $self->{SCRIPT_NAME} . "', 
                '" . $self->{SCRIPT_PATH} . '/' . $self->{SCRIPT_NAME} . "', 
                '" . $self->{START_DATE_TIME} . "', 
                '" . $self->{START_DATE_TIME} . "',
                '$time[0] $time[1]'
              )" 
            );
        }
        undef @tmp;

        ## call disconnects, etc.
        $self->{DB_DAD_S}->disconnect;
        $self->{DB_DAD_I}->disconnect;
        $self->{DS}->unbind();

    }



1;
__END__
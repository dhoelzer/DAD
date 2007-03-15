package DAD;
use strict;
use ActiveDS;
use DBI;
use FileACL;
use FindBin qw($Bin $Script);


#######################
##TODO: 
##      - get_date_time
##          - specify format of returned date/time
##          - specify UTC or not
##      - log_event
##



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
## $obj =  new( no_ldap => 1);
##   - options
##       - no_ldap - int - 0 will load connection to LDAP [default]
##                         1 will not load connection to LDAP
##
    sub new{
        my $proto   = shift;
        my $class   = ref( $proto ) || $proto;
        my %options = &$_import_options(@_);
        
        my @c;
        my $self = {};

        $self->{DB_NAME}     = 'DAD';
        $self->{DB_SERVER}   = 'USSRV124';
        $self->{DS}          = '';
        $self->{FILEACL}     = new FileACL;
        $self->{JOB_ID}      = '';
        $self->{SCRIPT_NAME} = $Script;
        $self->{SCRIPT_PATH} = $Bin;
        $self->{START_DATE}  = '';
        $self->{START_DATE_TIME}  = '';
        $self->{START_TIME}  = '';

        bless( $self, $class );

        ( $self->{START_DATE}, $self->{START_TIME} ) = $self->get_date_time();
        $self->{START_DATE_TIME} = $self->{START_DATE} . ' ' . $self->{START_TIME};

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

        $self->{JOB_ID} = $self->{DB_DAD_I}->{'mysql_insertid'};
        #ERR_Report( '3', "Job ID: [$job_id]" );

        @c = $self->get_credentials('domain');     #username, distinguishedname, password
        $self->{DS} = ActiveDS->new('',$c[1],$c[2]) if $options{'NO_LDAP'} != 1;

        $self;
    }


#####################
##  ($username, $dn, $pw) = get_credentials(which_credentials);
##      which_credentials:
##          - domain
##          - db_read
##          - db_change
##          - db_admin
    sub get_credentials{
        my $self   = shift;
        my $option = lc(shift);
        my $d;
        my $p;
        my $u;

        if ( $option eq 'domain' ){
            $d = 'cn=Username,cn=Container,dc=Domain,dc=Name,dc=net';
            $p = 'Password';
            $u = 'DAD Username';
        }elsif ( $option eq 'db_read' ){
            $d = '';
            $p = 'Password';
            $u = 'dad_read';
        }elsif ( $option eq 'db_change' ){
            $d = '';
            $p = 'Password';
            $u = 'dad_write';
        }elsif ( $option eq 'db_admin' ){
            $d = '';
            $p = 'Password';
            $u = 'dad_root';
        }else{
            return 0;
        }

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
        $eTo   = 'DAD@localdomain.com' if $eTo eq '';

        my $smtp = Net::SMTP->new('smtp.mail.server.com');

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
        $smtp->datasend("To: $eTo\n");
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
        my @u;

        @u = $self->get_credentials( 'db_change' );

        $self->{DB_DAD_I} = DBI->connect( 'DBI:mysql:database=' . $self->{DB_NAME} . ';host='. $self->{DB_SERVER} . ';port=3306', $u[0], $u[2] );
        if( $DBI::err ne '' ){
            my $line = __LINE__;
            $self->send_email( "DAD Job Failure: " . $self->{SCRIPT_NAME}, $self->{SCRIPT_NAME} . " failed to connect to the database\n\nDBI ERROR: $DBI::errstr\n\nSCRIPT PATH: " . $self->{SCRIPT_PATH} . '/' . $self->{SCRIPT_NAME} );
            return 0;
        }

        @u = $self->get_credentials( 'db_read' );
        $self->{DB_DAD_S} = DBI->connect( 'DBI:mysql:database=' . $self->{DB_NAME} . ';host='. $self->{DB_SERVER} . ';port=3306', $u[0], $u[2] );
        if( $DBI::err ne '' ){
            my $line = __LINE__;
            $self->send_email( "DAD Job Failure: " . $self->{SCRIPT_NAME}, $self->{SCRIPT_NAME} . " failed to connect to the database\n\nDBI ERROR: $DBI::errstr\n\nSCRIPT PATH: " . $self->{SCRIPT_PATH} . '/' . $self->{SCRIPT_NAME} );
            return 0;
        }

        return 1;
    }


#sub email

####################
## %ini_values = import_ini( $path_to_ini );
##
    sub import_ini{
	    my $self = shift;
        my $err;
        my $file_ini = shift;
        my $line;
        my @line;
        my $tmp;
        my %tmp;

        if( ! -f$file_ini ){
            print "import_ini: could not find INI: [$file_ini]\n";
            #( $file_ini ) = $Script=~/(.*)\.\w/g;
        }
        $file_ini = lc($file_ini);
        $err = open(FILE_INI,"$file_ini");
        return 0 if !$err;
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
## export_ini( $path_to_ini, %ini_values );
##
    sub export_ini{
	    my $self = shift;
        my $file_ini = shift;
        my %values = @_;
        my $err;

        $err = open(FILE_INI,">$file_ini");
        return "can't onen for writing: [$file_ini]\n" if !$err;
        foreach( keys %values ){
            print FILE_INI "$_=$values{$_}\n" if $_ ne '';
        }
        close FILE_INI;
        return 1;
    }


###########################
## 
    DESTROY{
        my $self = shift;
        my @tmp;
        my @time;

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
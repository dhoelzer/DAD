################################
## TO DO:
##   - allow file to file compare?
##   - use DBI to execute ALTER statements and check for errors. Sometimes with MODIFY <column>, the is a collision between existing data and the new column type.
##     will need to drop column and then add column if there is a collision.
##   - parse whole ALTER script and commit each statement via DBI to verify each statement's success


use strict;
use DBI;
use File::Copy;
use File::Temp;
use FindBin qw( $Bin );
require SQL::Translator;
use Term::ReadKey;
use threads;
use threads::shared;

my @alters;
my $file_schema_old;
my $flg_errors;
my $line;
my $mysql;
my $mysqldump : shared;
my %options;
my $return;
my $timestamp;
my $tmp;
my $v1;
my $v2;

###########
## import, sanatize, and verify command-line options
##  
    while( @ARGV ){
        $v1 = shift(@ARGV) if !$v1;
        $v2 = shift(@ARGV);
        if( $v2=~s/^--(.*)/$1/ ){
            $v1=~s/^--(.*)/$1/;
            $options{lc($v1)} = '';
            $v1 = '--' . $v2;
            undef $v2;
        }else{
            $v1=~s/^--(.*)/$1/;
            $options{lc($v1)} = $v2;
            undef $v1;
            undef $v2;
        }
    }
    if( $v1=~s/^--(.*)/$1/ ){
        $options{lc($v1)} = '';
    }
    ## HOST IP
    if( exists($options{'host'}) ){
        die "Invalid IP address: [$options{'host'}]\n" if $options{'host'}!~/^\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}$/;
    }else{
        $options{'host'} = '127.0.0.1';
    }
    ## NEW SCHEMA FILE
    if( exists($options{'new-schema'}) ){
        $options{'new_schema'}=~s|\\|\/|g;
        die "Cannot locate file: [$options{'new-schema'}]. Please specify full path.\n" if !-f$options{'new-schema'};
    }else{
        $options{'new-schema'} = "$Bin/Creates.sql";
    }
    ## DATABASE USER
    if( !exists($options{'user'}) ){
        $options{'user'} = 'root';
    }


    if( exists($options{'help'}) ){
        print "\nUsage: diff_shcema.pl [OPTIONS]\n";
        print "--help               Display this help and exit.\n";
        print "--new-schema {file}  {file} is full path to the new schema.\n";
        print "                     Default is current_dir/creates.sql.\n";
        print "--host {ip}          {ip} to the DAD server.\n";
        print "                     Default is 127.0.0.1.\n";
        print "--import             Import schema changes to DAD database.\n";
        print "                     Default is to create the file current_dir/alter.sql.\n";
        print "--user               The user account to connect to database as.\n";
        print "                     Default is root.\n";

        exit 1;
    }


###########
## prompt for root password
    print "$options{'user'} password for database: ";
    ReadMode 2;
    my $pw =<STDIN>;
    chomp($pw);
    ReadMode 0;
    print "\n\n";

    my $source = 'dbi:mysql:database=DAD;host=' . $options{'host'};
    my $dbh = DBI->connect($source, $options{'user'}, $pw);
    undef $source;
    die "Invalid username or password for database\n" unless $dbh;


###########
## find mysqldump.exe
    my $t = threads->create('thread_findfile','mysqldump.exe');
    $t->join;
    open STDERR, '>&STDOUT';        #had closed this in thread_findfile();
    undef $t;
    if( $mysqldump eq '' ){
        die "Cannont locate mysqldump.exe anywhere on C:\. mysqldump.exe must be on the local system.\n";
    }
    $mysqldump=~s|\/|\\|g;
    $mysql = $mysqldump;
    $mysqldump = "\"$mysqldump\" -u $options{'user'} --password=$pw --add-drop-table --create-options -h $options{'host'} --databases dad --no-data -q --compatible=mysql40";
    $mysql=~s/(.*)\\[^\\]+$/$1/;
    $mysql = '"' . $mysql . '\\mysql.exe"';


###########
## create tmp files
    my ($fh_schema_alter, $file_schema_alter) = File::Temp::tempfile(UNLINK => 0);
    my ($fh_schema_alter_tmp, $file_schema_alter_tmp) = File::Temp::tempfile(UNLINK => 0);
    my ($fh_schema_new_tmp, $file_schema_new_tmp) = File::Temp::tempfile(UNLINK => 0);
    my ($fh_schema_old, $file_schema_old) = File::Temp::tempfile(UNLINK => 0);


###########
## dump current db schema to disk
## sanatize - SQL::Translator does not handle some lines that MySQL 5 put in there.
    open(DUMP,"$mysqldump|");
    while( $line=<DUMP> ){
        if( $line=~/^\s*use\s+/i ){
            $line = "--$line";
        }elsif( $line=~/^\s*create database\s+/i ){
            $line = "--$line";
        }
        $line=~s/USING BTREE\s//i;
        $line=~s/comment[= ]'.*'//i;
        $line=~s/\) collate\s+\S+/\)/i;
        print $fh_schema_old $line;
    }
    close DUMP;
    close $fh_schema_old;
    undef $fh_schema_old;


###########
## sanatize new schema file - SQL::Translator does not handle some lines that MySQL 5 put in there.
    open(FILE,"$options{'new-schema'}") || die "Can't open $options{'new-schema'} for reading\n";
    while( $line=<FILE> ){
        if( $line=~/^\s*use\s+/i ){
            $line = "--$line";
        }elsif( $line=~/^\s*create database\s+/i ){
            $line = "--$line";
        }
        $line=~s/USING BTREE\s//i;
        $line=~s/comment[= ]'.*'//i;
        $line=~s/\) collate\s+\S+/\)/i;
        print $fh_schema_new_tmp $line;
    }
    close FILE;
    close $fh_schema_new_tmp;
    undef $fh_schema_new_tmp;


###########
## diff schema; produce alter script
    my $exe = "c:\\perl\\bin\\sqlt-diff \"$file_schema_old\"=MySQL \"$file_schema_new_tmp\"=MySQL";
    open(EXE,"$exe|");
    while($line=<EXE>){
        print $fh_schema_alter_tmp $line;
    }
    close EXE;
    close $fh_schema_alter_tmp;


###########
## sanatize ALTER script
##  - sqlt-diff for some reason changes the engine type to InnoDB no matter what is set on the table.
##    For now, we are forcing all tables to be MyISAM
##  - sqlt-diff uses CHANGE instead of MODIFY for ALTERs on columns; doing a substituion
    open($fh_schema_alter_tmp,$file_schema_alter_tmp) || die "Can't open $file_schema_alter_tmp for reading\n";
    while($line=<$fh_schema_alter_tmp>){
        $line=~s/type\s*=\s*innodb/Engine=MyISAM/i;
        if( $line=~/alter table/i ){
            $line=~s/\sCHANGE\s/ MODIFY /;
        }
        print $fh_schema_alter $line;
    }
	close $fh_schema_alter;
	undef $fh_schema_alter;
    close $fh_schema_alter_tmp;
    undef $fh_schema_alter_tmp;



###########
## handle alter script... import or copy to working dir; create backup file of current schema
    $timestamp = localtime(time);
    open(LOG,">>$Bin/diff_schema.log") || die "Can't open $Bin/diff_schema.log for writing\n";
    print LOG "$timestamp\tALTER file created\n";
    
    ## backup original schema to working dir
    my $tmp = 'schema_backup' . time . '.sql';
    $file_schema_old=~s|\\|\/|g;
    File::Copy::copy($file_schema_old,"$Bin/$tmp") || die $!;
    print LOG "$timestamp\tCurrent schema backed up to $Bin/$tmp";

    ## copy ALTER script to working dir
    print LOG "$timestamp\tALTER file copied to $Bin/alter.sql\n";
    File::Copy::copy($file_schema_alter,"$Bin/alter.sql");
    print "ALTER script located at: [$Bin/alter.sql]\n";
    
    ## pull out ALTER TABLES with MODIFY; have to jump through hoops if we're converting to certain column types (a.k.a - from CHAR to INT) 
    if( exists($options{'import'}) ){
        open( SCHEMA, $file_schema_alter );
        open( TMP, ">$file_schema_alter_tmp" );
        while( $line=<SCHEMA> ){
            if( $line=~/ALTER TABLE.*\sMODIFY\s/i ){
                chomp($line);
                push(@alters,$line);
            }else{
                print TMP $line;
            }
        }
        close TMP;
        close SCHEMA;

        print LOG "$timestamp\tALTER file applied to database\n";
        print LOG "$timestamp\tThe following lines were output from mysql.exe\n";
        print "Starting MySQL with \"$file_schema_alter_tmp\"\n";
        $file_schema_alter_tmp=~s|\/|\\|g;
        $exe = "$mysql dad -u $options{'user'} --password=$pw <\"$file_schema_alter_tmp\"";
        open(EXE,"$exe|");
        while($line=<EXE>){
            print LOG $line;
        }
        close EXE;
        print LOG "$timestamp\tmysql.exe complete\n";
        
        ## processing ALTER TABLE...MODIFY statements separately via DBI
        print LOG "$timestamp\tProcessing ALTER TABLE...MODIFY statements separately via DBI\n";
        foreach $line( @alters ){
            print LOG "$timestamp\tProcessing: $line\n";
            $dbh->do( $line );
            if( $dbh->errstr ){
                $tmp = $dbh->errstr;
                $tmp=~s/\n/; /g;
                print LOG "$timestamp\tERROR: $tmp\n";
                undef $tmp;
                my ($table, $col) = $line=~/alter table\s(.*)\smodify\s(.*)\s[^;]*;/i;
                print LOG "$timestamp\tDROPing column [$col]\n";
                $tmp = "ALTER TABLE $table DROP COLUMN $col";
                print LOG "$timestamp\tStatement: $tmp\n";
                $dbh->do( $tmp );
                if( $dbh->errstr ){
                    $tmp = $dbh->errstr;
                    $tmp=~s/\n/; /g;
                    print LOG "$timestamp\tERROR: $tmp\n";
                    $flg_errors = 1;
                }else{
                    $line=~s/MODIFY/ADD COLUMN/i;
                    print LOG "$timestamp\tStatement: $line\n";
                    $dbh->do( $line );
                    if( $dbh->errstr ){
                        $tmp = $dbh->errstr;
                        $tmp=~s/\n/; /g;
                        print LOG "$timestamp\tERROR: $tmp\n";
                        $flg_errors = 1;
                    }else{
                        print LOG "$timestamp\tSUCCESS ADDing column\n";
                    }
                }
            }else{
                print LOG "$timestamp\tSUCCESS\n";
            }
        }
        print LOG "$timestamp\tFinished processing ALTER TABLE statements\n";
    }

print LOG "$timestamp\tdiff_schema.pl script complete\n";
close LOG;

if( $flg_errors ){
    print "Script complete, but with errors.\nSee $Bin/diff_schema.log for errors\n";
}else{
    print "Script complete\n";
}


###########
## separate thread to find mysqldump.exe
##   I made a separate thread because I'm using File::Find; once this is invoked, you 
##   can't break it even if you found what you want. Thus, once we find the EXE, we 
##   populate a share variable and have the whole thread exit.
sub thread_findfile{
    use File::Find;
    my $my_file = shift;

    open STDERR, ">nul" or die "Can't dup stdout: $!";
    open(EXE,"$my_file|");
    close EXE;
    if($?){
        print "$my_file is not is the PATH environment varaible or in the current\n working dir. Will now try to find $my_file in standard MySQL\n locations.\n\n";
        File::Find::find(
            { wanted=>\&filename_match,
              #no_chdir=>1
            },
            ('c:/Program Files/MySQL','c:/MySQL')
        );

        ## if we get to here, we did not find it in standard MySQL locations. Will search root of c: ##
        print "$my_file is not in standard MySQL locations. Will search all of c:.\n\n";
        File::Find::find(
            { wanted=>\&filename_match,
              no_chdir=>1
            },
            ('c:/')
        );

        sub filename_match{
            if( $File::Find::name=~/$my_file$/i ){
                $mysqldump = $File::Find::name;
                print "Found $my_file at $mysqldump.\n\n";
                threads->exit();
            }
        }
    }else{
        $mysqldump = $my_file;
    }
    close STDERR;
}

DESTROY{
    unlink $file_schema_alter;
    unlink $file_schema_new_tmp;
    unlink $file_schema_old;
    unlink $file_schema_alter_tmp;
    $dbh->disconnect;
}


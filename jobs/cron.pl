use strict;

use DAD;
use DBI;
use Schedule::Cron;
use threads;
use threads::shared;

my $cron;
my $f_sql : shared;
my @job_stats;
my $null  : shared;
my @q_sql : shared;
my $t_cron;
my $t_cron_pid;
my $t_sql;
my $t_qry;
my @tmp;

$null = chr(0);

start_threads();

#############################
## Setup Cron and watch for job updates
    $cron = new Schedule::Cron(\&dispatcher);
    @job_stats = check_job_entries();
    load_jobs();
    $cron->run(detach => 1);
    while(1){
        @tmp = check_job_entries();
        if( $tmp[0] > $job_stats[0] || $tmp[1] != $job_stats[1] ){
print "reload jobs\n";
            @job_stats = @tmp;
print "CRON.PL: called stop\n";
            $cron->stop(1);
print "CRON.PL: heard back from stop\n";
            load_jobs();
            $t_cron = threads->create( sub{ $cron->run(detach => 1) } );
        }
        sleep 5;
    }
#############################
## Watch for new jobs
## check for updates to job mysql table
##   - kill $t_cron
##   - flush jobs and reload
##   - reload new cron thread 


sub load_jobs{
    my $job;
    my $k;
    my %ret;
    my $sql;

    $cron->clean_timetable();

    $sql = qq{SELECT id_dad_adm_job, length, job_type, path, package_name, user_name, distinguishedname, pword, 
               times_to_run, times_ran, start_date, start_time, last_ran, min, hour, d_of_m, m_of_y, d_of_w
              FROM dad_adm_job
              WHERE (times_to_run < times_ran
               OR times_to_run IS NULL)
    };
    %ret = run_sql( $sql );
    while( ($k,$job) = each(%ret) ){
        $cron->add_entry("${$job}[13] ${$job}[14] ${$job}[15] ${$job}[16] ${$job}[17] ",@{$job});
        print "${$job}[0]\t${$job}[3] [[${$job}[13] ${$job}[14] ${$job}[15] ${$job}[16] ${$job}[17]]]\n";
    }
}

sub check_job_entries{
    my %ret = run_sql( "SELECT (SELECT MAX(timeactive) FROM dad_adm_job) as 'max time', (SELECT count(*) FROM dad_adm_job) as 'count'" );
    return ( ${$ret{1}}[0], ${$ret{1}}[1] );
    undef %ret;
}


sub dispatcher{
    my @job = @_;
    run_sql( "UPDATE dad_adm_job SET last_ran = unix_timestamp(), times_ran = times_ran + 1 WHERE id_dad_adm_job = $job[0]" );
    require $job[3];
    $job[4]->main();
    my $t = localtime();
    print "DISPATCHER: $t\t$job[4]\n";
}


sub run_sql{
    my $sql  = shift;

    my $k;
    my %que : shared;
    my %r;

    {
        lock(@q_sql);
        push(@q_sql,\%que);
        push(@q_sql,$sql);
        $f_sql++;
    }
    while(1){
        sleep_mil(20);
        if( scalar keys %que > 0 ){
            if( $que{0} ne '' ){
                #HANDLE DBI ERROR
            }else{
                lock(%que);
                foreach $k (keys %que){
                    @{$r{$k}} = split(/$null/,$que{$k});
                }
                last;
            }
        }
    }
    return %r;
    undef $sql;
    undef %que;
}

sub thread_sql{
    my $cnt = 0;
    my $db;
    my $requestor;
    my $sql;
    my $stmt;
    my @row;
    {
        lock(@q_sql);
        $db = DBI->connect( 'DBI:mysql:database=DAD;host=ussrv124;port=3306', 'dad_write', '()nly2Write' );
    }

    while(1){
        if($f_sql){
            $requestor = shift @q_sql;
            lock($requestor);
            $sql = shift @q_sql;
            $f_sql--;
            if( $sql=~/^select/i ){
                $stmt = $db->prepare($sql);
                if( $DBI::err ){
                    ${$requestor}{0} = $DBI::err;
                }else{
                    $stmt->execute();
                    while( @row = $stmt->fetchrow_array ){
                        $cnt++;
                        ${$requestor}{$cnt} = join($null,@row);
                    }
                    $cnt = 0;
                    @row = [];
                }
            }else{
                $row[0] = $db->do($sql);
                if( $DBI::err ){
                    ${$requestor}{0} = $DBI::err;
                }else{
                    ${$requestor}{1} = $row[0];
                }
                @row = [];
            }
        }
        sleep_mil(10);
    }
}


sub sleep_mil{
    my $s = shift;
    if( $s=~/[^\d]/ ){
        print "sleep_mil() error: expected only digits!!\n";
        return 0;
    }
    $s = '0' . $s if length($s) == 1;    ## must have passed in "1" or "2", which in reality is one millisecond, which is equal to ".01" not ".1"; prepending a zero
    select(undef, undef, undef, ".$s");
    return 1;
}

sub start_threads{
    $t_sql = threads->create( \&thread_sql );
    $t_sql->detach();
    # $t_qry = threads->create( \&query_sql );
    # $t_qry->detach();
}

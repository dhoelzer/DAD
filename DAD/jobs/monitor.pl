################################
## Event Monitoring script.
##
##  TODO
##    - logging needed in db_err_handler_alert_handler();
##    - combine db_err_handler_alert_handler() and db_err_handler_main
##    - stmts should be in one hash, then when we add error handling for each statement, we can simply loop through hash
##       - that way we won't forget to push in error handling.
##    - sometype of handling for other DBI errors
##    - should we spin a second thread to dig through the missed events (which could be throttelled back), while the main thread starts at the present?
use strict;
use threads;
use threads::shared;
use Thread::Queue;
use DAD;

my %alert : shared;
my @alert_criteria;
my %alert_group : shared;
my $alert_flg;
my $alert_id;
my $cnt;
my @col;
my $col_criteria;
my $col_id;
my %col_position : shared;
my $comp_grp;
my %comp_grp;
my $criteria;
my $dad = new DAD(no_ldap=>1);
my $dad2;
my $event_record_len : shared;
my $event_que = new Thread::Queue;
my %events_to_alert;
my $fld;
my $flg_exit : shared;
my $flg_no_match;
my %ini;
my $ini_file;
my $max_id;
my $regex;
my $s_alert;
my $s_alert_criteria;
my $s_alert_group;
my $s_alert_message;
my $s_alert_supress;
my $s_alert_timeactive;
my $s_computer_group;
my $s_event;
my $s_max_id;
my %suppress_criteria : shared;
my $t;
my $time;
my $timestamp_ag    = 0;
my $timestamp_alert = 0;
my $timestamp_cg    = 0;
my $val;

$ini_file = "$dad->{SCRIPT_PATH}/monitor.ini";
%ini = $dad->import_ini( $ini_file );
if( $dad->err ){
    print $dad->errstr;
    die;
}

db_connect_main();
load_alert_criteria();

$t = threads->create('_ap');
$t->detach();
undef $t;


foreach my $computer_group ( keys %events_to_alert ){
    print "COMPUTER GROUP $computer_group\n";
    my %cri = %{$events_to_alert{$computer_group}};
    foreach my $alert_id ( keys %cri ){
        print "\t$alert_id\n";
        print "\t\t$_\n" foreach @{$cri{$alert_id}};
    }
}




## continuously loop through events
MAINLOOP: while(1){
    my $pos;
    $time = time;
	$s_max_id->execute();
	$max_id = $s_max_id->fetchrow_array();
	$s_max_id->finish;
    if( ($max_id - $ini{min_id}) > 200000 ){
        $max_id = $ini{min_id} + 200000;
        print "Monitor fell back way too far. Stepping 200k events at a time.\n";
    }
	$s_event->execute($ini{min_id},$max_id);
	$s_event->bind_columns( \$col[0], \$col[1], \$col[2], \$col[3], \$col[4], \$col[5], \$col[6], \$col[7], \$col[8], \$col[9], \$col[10], \$col[11], \$col[12], \$col[13], \$col[14], \$col[15], \$col[16], \$col[17], \$col[18], \$col[19], \$col[20], \$col[21], \$col[22], \$col[23], \$col[24], \$col[25], \$col[26], \$col[27], \$col[28], \$col[29], \$col[30], \$col[31], \$col[32], \$col[33], \$col[34] );

    if( !$event_record_len ){
        $cnt = 0;
        foreach( @{$s_event->{NAME_lc}} ){                                                   #build a hash of column names so that we know what positions a name column is in in the subsequent returned row/array
            $col_position{$_} = $cnt;
            $cnt++;
        }
        undef $cnt;
        $event_record_len = scalar keys %col_position;
    }

	while( $s_event->fetchrow_arrayref() ){                                              #foreach event
        undef $flg_no_match;
        $pos = $col_position{'systemid'};
        if( exists $comp_grp{$col[$pos]} ){                                                 #is this computer in any computer groups?
            foreach $comp_grp ( @{$comp_grp{$col[$pos]}} ){                                 #loop through each computer group that the computer is assigned to
        	    if( exists $events_to_alert{$comp_grp} ){                                      #does this computer group have any alerts bound to it?
                    undef $alert_id;
                    foreach $alert_id ( keys %{$events_to_alert{$comp_grp}} ){                 #each computer group can have one or more alerts bound to it; we will cycle through eacn of them
                        @alert_criteria = @{${$events_to_alert{$comp_grp}}{$alert_id}};        #grab array of criteria for the specific alert; criteria are in the order of [event_field,matching_value,event_field,matching_value,...]
                        while( @alert_criteria ){
                            $fld = shift(@alert_criteria);
                            $val = shift(@alert_criteria);
                            if( $col[$col_position{$fld}]!~/$val/i ){                         #we take the field name and translate it to the position number in the @col and then see if the given value matches
                                # print "SYSTEM: $col[1]\n";
                                # print "CRITERIA: $fld - $val\n\t$col[$col_position{$fld}]\n";
                                # print "\t$_\n" foreach @col;
                                # print "\n";
                                ## if we get to hear, it means the regular expression did not match the given value (a.k.a. !~//)
                                $flg_no_match = 1;
                            }
                        }
                        if( !$flg_no_match ){
                            ## this flg did not get set above, which means all the criteria for this alert were successfully matched.
                            #print "\t$_\n" foreach @col
                            $event_que->enqueue( $alert_id, @col );
                        }
                    }
        		}
            }
        }
	}
    $s_event->finish();

	print "Took ", (time-$time), " seconds to fetched the last ", ($max_id-$ini{min_id}), " records\n  Last record was $max_id\n";
	if( $ini{min_id} < $max_id ){
        $ini{min_id} = $max_id;
        $dad->export_ini($ini_file,%ini);
    }
    load_alert_criteria();
	sleep 5;
}



sub load_alert_criteria{
    my @cols;
    my $tmp;
    $s_alert_timeactive->execute();
    $tmp = $s_alert_timeactive->fetchrow_array();
    if( $tmp > $timestamp_alert ){
        $timestamp_alert = $tmp;

        ## build alert details hash ##
        undef %alert;
        $s_alert->execute();
        $s_alert->bind_columns( \$col[0], \$col[1], \$col[2], \$col[3], \$col[4], \$col[5] );    ## id_dad_adm_alert, id_dad_adm_computer_group, id_dad_adm_action, id_dad_adm_alert_group, supress_interval
        while( $s_alert->fetchrow_arrayref() ){
            $alert{$col[0]} = &share([]);
            push(@{$alert{$col[0]}},$col[1],$col[2],$col[3],$col[4],$col[5]);
        }
        $s_alert_supress->finish;
        undef @col;

        ## build alert criteria hash ##
        undef %events_to_alert;
        $s_alert_criteria->execute();
        $s_alert_criteria->bind_columns( \$cols[0], \$cols[1], \$cols[2], \$cols[3] );   ## id_dad_adm_alert, field, criteria, id_dad_adm_computer_group
        while( $s_alert_criteria->fetchrow_arrayref() ){
            push( @{${$events_to_alert{$cols[3]}}{$cols[0]}},lc($cols[1]),$cols[2] );     ## make sure that cols[1] (the field name) is lower case
        }
        $s_alert_criteria->finish;

        ## build suppress criteria hash ##
        undef %suppress_criteria;
        $s_alert_supress->execute();
        $s_alert_supress->bind_columns( \$col[0], \$col[1] );    ## id_dad_adm_alert, field_name
        while( $s_alert_supress->fetchrow_arrayref() ){
            if( exists $suppress_criteria{$col[0]} ){
                push( @{$suppress_criteria{$col[0]}}, lc($col[1]) );
            }else{
                $suppress_criteria{$col[0]} = &share([]);
                push( @{$suppress_criteria{$col[0]}}, lc($col[1]) );
            }
        }
        $s_alert_supress->finish;
        undef @col;

        print "RELOADED alert criteria\n";

    }

    ## build computer group hash ##
    $tmp = $dad->{DB_DAD_S}->selectrow_array( "SELECT max(timeactive) FROM dad_adm_computer_group" );
    if( $tmp > $timestamp_cg ){
        $timestamp_cg = $tmp;
        undef %comp_grp;
        $s_computer_group->execute();
        $s_computer_group->bind_columns( \$col[0], \$col[1] );    ## system_id, id_dad_adm_computer_group
        while( $s_computer_group->fetchrow_arrayref() ){
            push( @{$comp_grp{$col[0]}}, $col[1] );
        }
        $s_computer_group->finish;
        undef @col;
    }

    ## build alert group hash ##
    $tmp = $dad->{DB_DAD_S}->selectrow_array( "SELECT max(timeactive) FROM dad_adm_alert_group" );
    if( $tmp > $timestamp_ag ){
        $timestamp_ag = $tmp;
        undef %alert_group;
        $s_alert_group->execute();
        $s_alert_group->bind_columns( \$col[0], \$col[1] );    ## agm.id_dad_adm_alertgroup, au.emailaddress
        while( $s_alert_group->fetchrow_arrayref() ){
            $alert_group{$col[0]} .= $col[1] . ';';
        }
        $s_alert_group->finish;
        undef @col;
    }
}


##############
## alert processor
sub _ap{
    my $alert_group_id;
    my $alert_id;
    my $cnt;
    my @col;
    my $cri;
    my $flg_process;
    my @message;
    my $sleep;
    my $str;
    my %suppressed;
    ## %alert{alert_id} = [id_dad_adm_computer_group, id_dad_adm_action, id_dad_adm_alert_group, supress_interval, id_dad_adm_alert_message]

    db_connect_ap();

    while(!$flg_exit){
        $alert_id = $event_que->dequeue_nb();
        if( $alert_id ne '' ){
            ## build @col from shared queue, based on record length of SELECT statement (established in other thread)
            for( $cnt=0; $cnt<$event_record_len; $cnt++){
                $col[$cnt] = $event_que->dequeue();
            }
            $sleep = ${$alert{$alert_id}}[3];
            if( $sleep >= 1 ){
                ## build string of values that we're supposed to be suppressing against; this will be our key in our hash;
                foreach $cri ( @{$suppress_criteria{$alert_id}} ){
                    $str .= lc($col[$col_position{$cri}]) . ',';
                }
                if( exists $suppressed{$str} ){
                    ## if we've already suppressed one instance of this event, we want to see the details on the 
                    ##   first instance of the happening, not the last. So, we will simply increase the queue time 
                    ##   on the envent, but leave all the other details alone.
                    ${$suppressed{$str}}[0] = (time+($sleep*60));       ## convert minutes to seconds
                }else{
                    ## we have not suppressed this event yet, so we'll build the entry with all the details...
                    ## we will send alerts out the first time the event trips something, but will not there after until the envent falls out of the suppression queue
                    push( @{$suppressed{$str}}, (time+($sleep*60)), $alert_id );
                    $flg_process = 1;
                }
                undef $str;
            }else{
                print "we're supposed to act on this one immediately: $alert_id\n";
                $flg_process = 1;
            }
            if( $flg_process ){
                if( ${$alert{$alert_id}}[1] == 2 ){     ## ID 2 == EMAIL
                    if( !$s_alert_message->execute( ${$alert{$alert_id}}[4] ) ){      ## we try this twice because each statement has an error handler that will try to reconnect to the db if the connection is lost.
                        if( !$s_alert_message->execute( ${$alert{$alert_id}}[4] ) ){
## SEND ERROR EMAIL!! CAN'T RESTABLISH CONNECTION TO DB... SHOULD WE WAIT X MINUTES AND TRY AGAIN...?
                        }
                    }
                    @message = $s_alert_message->fetchrow_array;         ## subject, body 
                    $s_alert_message->finish;

                    ## we'll convert all time fields first to real timestamps
                    $message[0]=~s/\$(time[^\$]*?)\$/localtime($col[$col_position{$1}])/ge;
                    $message[1]=~s/\$(time[^\$]*?)\$/localtime($col[$col_position{$1}])/ge;
                    ## now we'll do the rest of the substitions
                    $message[0]=~s/\$([^\$]*?)\$/$col[$col_position{$1}]/ge;
                    $message[1]=~s/\$([^\$]*?)\$/$col[$col_position{$1}]/ge;

                    $alert_group_id = ${$alert{ $alert_id }}[2];
                    DAD::send_email( '', ## usually called via object oriented...
                        $message[0],
                        $message[1],
                        $alert_group{$alert_group_id}, 
                        'jkiebzak@usa.wtbts.net'
                    );
                    undef @message;
                    undef $alert_group_id;
                }elsif( ${$alert{$alert_id}}[1] == 3 ){     ## ID 3 == Rollback group change
                    
                }elsif( ${$alert{$alert_id}}[1] == 4 ){     ## ID 4 == Run Perl Module
                    
                }elsif( ${$alert{$alert_id}}[1] == 5 ){     ## ID 5 == Run Command Line
                    
                }elsif( ${$alert{$alert_id}}[1] == 6 ){     ## ID 6 == Diff text file
                    
                }
            }
            undef @col;
            undef $flg_process;
        }else{
            sleep 1;
        }

        ## loop through suppressed/queued events and delete anything that has passed its suppression time limit ##
        foreach $str ( keys %suppressed ){
            delete $suppressed{$str} if ${$suppressed{$str}}[0] < time;
        }
        undef $alert_id;
    }
}


sub db_connect_main{
    $dad = new DAD (no_ldap=>1);

    $s_max_id = $dad->{DB_DAD_S}->prepare( "SELECT max(dad_sys_events_id) FROM dad_sys_events" );
    $s_max_id->{HandleError} = sub{ db_err_handler_main(shift); };

    #                                              0                  1         2              3       4         5    6         7        8          9        10...
    $s_event  = $dad->{DB_DAD_S}->prepare( "SELECT dad_sys_events_id, systemid, timegenerated, source, category, sid, computer, eventid, eventtype, field_0, field_1, field_2, field_3, field_4, field_5, field_6, field_7, field_8, field_9, field_10, field_11, field_12, field_13, field_14, field_15, field_16, field_17, field_18, field_19, field_20, field_21, field_22, field_23, field_24, field_25
                                            FROM dad_sys_events where dad_sys_events_id > ? AND dad_sys_events_id < ?" );
    $s_event->{HandleError} = sub{ db_err_handler_main(shift); };

    $s_alert  = $dad->{DB_DAD_S}->prepare( "SELECT id_dad_adm_alert, id_dad_adm_computer_group, id_dad_adm_action, id_dad_adm_alert_group, supress_interval, id_dad_adm_alert_message FROM dad_adm_alert WHERE active = 1" );
    $s_alert->{HandleError} = sub{ db_err_handler_main(shift); };

    $s_alert_criteria = $dad->{DB_DAD_S}->prepare( "SELECT ac.id_dad_adm_alert, ac.field, ac.criteria, a.id_dad_adm_computer_group 
                                                    FROM dad_adm_alert_criteria AS ac 
                                                    INNER JOIN dad_adm_alert AS a 
                                                    ON ac.id_dad_adm_alert = a.id_dad_adm_alert
                                                    WHERE a.active = 1" );
    $s_alert_criteria->{HandleError} = sub{ db_err_handler_main(shift); };

    $s_alert_group = $dad->{DB_DAD_S}->prepare( "SELECT agm.id_dad_adm_alertgroup, au.emailaddress
                                                    FROM dad_adm_alert_group_member AS agm
                                                    LEFT JOIN dad_adm_alertuser AS au
                                                    ON agm.id_dad_adm_alertuser = au.id_dad_adm_alertuser" );
    $s_alert_group->{HandleError} = sub{ db_err_handler_main(shift); };
    
    $s_alert_supress = $dad->{DB_DAD_S}->prepare( "SELECT id_dad_adm_alert, field_name FROM dad_adm_alert_supress ORDER BY field_name" );
    $s_alert_supress->{HandleError} = sub{ db_err_handler_main(shift); };
    
    $s_alert_timeactive = $dad->{DB_DAD_S}->prepare( "SELECT max(timeactive) FROM dad_adm_alert" );
    $s_alert_timeactive->{HandleError} = sub{ db_err_handler_main(shift); };
    
    $s_computer_group = $dad->{DB_DAD_S}->prepare( "SELECT system_id, id_dad_adm_computer_group FROM dad_adm_computer_group_member" );
    $s_computer_group->{HandleError} = sub{ db_err_handler_main(shift); };
}


sub db_err_handler_main{
    ## $_[0] == Error string
    ## $_[1] == statement handle that raised the error.
    warn "ERROR: db_err_handler_main() engaged. DBI error num: ",$_[1],"\n";
    if( $_[1] eq '' ){                          ## sometimes when the connection is lost, it object becomes undefined...
        db_connect_main();             ## reestablish the connections, etc.
        #->{Database}
    }else{
        if( $_[1]->err == 2013 || $_[1]->err == 2006 ){
            ## err 2013 == loss db connection
            ## err 2006 == can execute statement
            db_connect_main();         ##reestablish the connections, etc.
        }else{
            die "ERROR connecting to db... something else happened: ",$_[1]->err,"\n";
## do some type of logging or something...
        }
    }
    next MAINLOOP;
    return -1;
}


sub db_connect_ap{
    undef $dad2 if $dad2 ne '';
    $dad2 = new DAD (no_ldap=>1);
    $s_alert_message = $dad2->{DB_DAD_S}->prepare( "SELECT subject, body FROM dad_adm_alert_message WHERE id_dad_adm_alert_message = ?" );
    $s_alert_message->{HandleError} = sub{ db_err_handler_ap(shift); };
}


sub db_err_handler_ap{
    ## $_[0] == Error string
    ## $_[1] == statement handle that raised the error.
    if( $_[1] eq '' ){                          ## sometimes when the connection is lost, it object becomes undefined...
        db_connect_ap();             ## reestablish the connections, etc.
    }else{
        if( $_[1]->err == 2013 || $_[1]->err == 2006 ){
            ## err 2013 == loss db connection
            ## err 2006 == can execute statement
            db_connect_ap();         ##reestablish the connections, etc.
        }else{
            die "ERROR connecting to db... something else happened: ",$_[1]->err,"\n";
## do some type of logging or something...
        }
    }
    return -1;
}



DESTROY{
    $flg_exit = 1;
    print "TOTAL TIME: ",(time-$^T), "\n";
}
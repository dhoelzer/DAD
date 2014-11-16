#   Report and Alert Library
#    Copyright (C) 2006, David Hoelzer/Cyber-Defense.org
#
#    This program is free software; you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation; either version 2 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program; if not, write to the Free Software
#    Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA
#################################################
#
# Functions:
#
# SendEmail( $eSub, $eBody, $eTo, $eFrom, $eCC, $eBCC )
#	Allows you to send an email to an arbitrary desination and with an arbitrary source.
#	You must properly configure the mail server value for this to function.
#
#  string GetEventsByStrings($TimeFrameInSeconds, $string1[, $string2[, ...]])
#	Allows you to quickly query the events database for all of the events in the given
#	time range (in seconds) that contain all of the specified words.  You must specify
#	at least one search term.  There may be future changes to this function to limit
#	the number of values returned.


# Modules for DB and Event logs.  POSIX is required for Unix time stamps
use DBI;
use POSIX;
#Read in and evaluate the configuration values
open(FILE,"../dbconfig.ph") or return "Could not find configuration file!\n";
foreach (<FILE>) { eval(); }
close(FILE);

sub GetEventsByStringsPosition
{
	my $TimeFrame = shift(@_);
	my $num_terms = @_;
	my $SearchTerms = "";
	my @Terms = ();
	my %Positions = {};
	
	if(($num_terms % 2) != 0 )
	{
		return "Format for GetEventsByStringsPostion is TimeFrame(in seconds), String, Position[,String, Position...]";
	}
	if($num_terms < 1)
	{
		return "No search terms present\n";
	}
	$num_terms /= 2;
	#$TimeFrame = time()-$TimeFrame;
	$Report = "";
	#print "Searching for events that occurred since $TimeFrame with the terms:\n";
	for($i=0; $i!= $num_terms; $i++)
	{
		$t = lc($_[$i * 2]);
		$p = $_[($i * 2) + 1];
		#print "$t - $p\n";
		$_ = $p;
		$Terms[$i] = $t;
		$Positions{$t} = $p  unless /\D/;	
		if(!$SearchTerms)
		{
			$SearchTerms = "'$t'";
		}
		else
		{
			$SearchTerms .= ",'$t'";
		}
	}

	# Events to find:	
	$SQL = q{
	SELECT * 
	FROM event_unique_strings 
	WHERE String IN ( }. $SearchTerms .q{ )
	};#print "$SQL\n";
	$results_ref = &SQL_Query($SQL);
	$num_results = @$results_ref;
	if($num_results < $num_terms)
	{
		return "Could only find $num_results out of $num_terms terms.  Search cancelled.\n";
	}
	$StringIDFilter = "";
	if($num_results)
	{
		while($row = shift(@$results_ref))
		{
			@this_row = @$row;
			#print $this_row[0]."-".$this_row[1]."-".$Positions{lc($this_row[1])}."\n";
			if(!$Positions{lc($this_row[1])})
			{ #print "\tNo Position\n";
				if($StringIDFilter eq "")
				{
					$table_ref = 'b';
					$StringIDFilter="\n$table_ref.String_ID=$this_row[0]";
					$JOINS="\nJOIN event_fields as $table_ref";
					$MATCHES="\nAND a.Events_ID=$table_ref.Events_ID";
				}
				else
				{
					$table_ref++;
					$StringIDFilter .= "\nAND $table_ref.String_ID=$this_row[0]";
					$JOINS.="\nJOIN event_fields as $table_ref";
					$MATCHES.="\nAND a.Events_ID=$table_ref.Events_ID";
				}
				next;
			}
			if($StringIDFilter eq "")
			{
				$table_ref = 'b';
				if($Positions{$this_row[1]} == int($Positions{$this_row[1]}))
				{
					$StringIDFilter = "\n($table_ref.String_ID=$this_row[0] AND $table_ref.Position=".$Positions{lc($this_row[1])}.")";
				}
				else
				{
					$StringIDFilter = "\n$table_ref.String_ID=$this_row[0]";
				}
				$JOINS="\nJOIN event_fields as $table_ref";
				$MATCHES="\nAND a.Events_ID=$table_ref.Events_ID";
			}
			else
			{			
				$table_ref++;
				if($Positions{$this_row[1]} == int($Positions{$this_row[1]}))
				{
					$StringIDFilter .= "\nAND ($table_ref.String_ID=$this_row[0] AND $table_ref.Position=".$Positions{lc($this_row[1])}.")";
				}
				else
				{
					$StringIDFilter .= "\nAND $table_ref.String_ID=$this_row[0]";
				}
				$JOINS.="\nJOIN event_fields as $table_ref";
				$MATCHES.="\nAND a.Events_ID=$table_ref.Events_ID";
			}
		}
		$SQL=q{
			SELECT DISTINCT a.Events_ID,a.Time_Written,a.Time_Generated
			FROM events as a
			}. $JOINS .q{
			WHERE }. $StringIDFilter . $MATCHES . 
			q{ AND a.Time_Written > }. $TimeFrame .q{ LIMIT 100};
print "$SQL\n";
			
		my $results_ref2 = &SQL_Query($SQL);
		$num_results = @$results_ref2;
		if($num_results)
		{
			my $Events_ID_in = "";
			while($trow = shift(@$results_ref2))
			{
				my @mrow = @$trow;
				if($Events_ID_in eq "")
				{
					$Events_ID_in = "$mrow[0]";
				}
				else
				{
					$Events_ID_in .= ", $mrow[0]";
				}
			}	
			$SQL = q{
				SELECT 
					f.Events_ID, 
					e.Time_Generated,
					systems.System_Name, 
					GROUP_CONCAT(s.String ORDER BY f.Position ASC separator ' ')
				FROM
					events as e,
					event_fields as f,
					event_unique_strings as s, 
					dad_sys_systems as systems
				WHERE
					e.Events_ID IN (}. $Events_ID_in .q{)
					AND f.Events_ID=e.Events_ID
					AND (
						f.String_ID=s.String_ID
						)
					AND systems.System_ID=e.System_ID
					GROUP BY f.Events_ID
					ORDER BY f.Events_ID,f.Position	, e.Time_Generated			
				};#print "$SQL\n";
			$event_detail_ref = &SQL_Query($SQL);
		}
	}
	return $event_detail_ref;

}

sub GetEventsByStringsPositionText
{
	$event_detail_ref = GetEventsByStringsPosition(@_);
	$num_results = @$event_detail_ref;
	if($num_results)
	{
		my $edrs;
		while($edrs=shift(@$event_detail_ref))
		{
			my @edra=@$edrs;
			$Report .= "$edra[1]|$edra[2]|$edra[3]\n";
		}
	}
	return "$Report\n";

}

sub GetEventsByStrings
{
	my $TimeFrame = shift(@_);
	my $num_terms = @_;
	my $SearchTerms = "";
	
	if($num_terms < 1)
	{
		return "No search terms present\n";
	}
	$TimeFrame = time()-$TimeFrame;
	$dsn = "DBI:mysql:host=$MYSQL_SERVER;database=dad";
	$dbh = DBI->connect ($dsn, "$MYSQL_USER", "$MYSQL_PASSWORD")
		or return "Could not connect to DB server to run alerting.\n";
	$Report = "";
	#print "Searching for events that occurred since $TimeFrame with the terms:\n";
	foreach(@_)
	{
		if($SearchTerms eq "")
		{
			$SearchTerms = "'$_'";
		}
		else
		{
			$SearchTerms .= ", '$_'";
		}
		#print "\t$_\n";
	}
	# Events to find:	
	$SQL = q{
	SELECT * 
	FROM event_unique_strings 
	WHERE String IN ( }. $SearchTerms .q{ )
	};#print "$SQL\n";
	$results_ref = &SQL_Query($SQL);
	$num_results = @$results_ref;
	if($num_results < $num_terms)
	{
		return "Could only find $num_results out of $num_terms terms.  Search cancelled.\n";
	}
	$StringIDFilter = "";
	if($num_results)
	{
		while($row = shift(@$results_ref))
		{
			@this_row = @$row;
			
			if($StringIDFilter eq "")
			{
				$table_ref = 'b';
				$StringIDFilter = "\n$table_ref.String_ID=$this_row[0]";
				$JOINS="\nJOIN event_fields as $table_ref";
				$MATCHES="\nAND a.Events_ID=$table_ref.Events_ID";
			}
			else
			{
				$table_ref++;
				$StringIDFilter .= "\nAND $table_ref.String_ID=$this_row[0]";
				$JOINS.="\nJOIN event_fields as $table_ref";
				$MATCHES.="\nAND a.Events_ID=$table_ref.Events_ID";
			}
		}
		$SQL=q{
			SELECT DISTINCT a.Events_ID,a.Time_Written,a.Time_Generated
			FROM events as a
			}. $JOINS .q{
			WHERE }. $StringIDFilter .q{ 
			}. $MATCHES .q{ };
#print "$SQL\n";
			
		my $results_ref2 = &SQL_Query($SQL);
		$num_results = @$results_ref2;
		if($num_results)
		{
			my $Events_ID_in = "";
			while($trow = shift(@$results_ref2))
			{
				my @mrow = @$trow;
				if($Events_ID_in eq "")
				{
					$Events_ID_in = "$mrow[0]";
				}
				else
				{
					$Events_ID_in .= ", $mrow[0]";
				}
			}	
			$SQL = q{
				SELECT 
					f.Events_ID, 
					e.Time_Generated,
					systems.System_Name, 
					GROUP_CONCAT(s.String ORDER BY f.Position ASC separator ' ')
				FROM
					events as e,
					event_fields as f,
					event_unique_strings as s, 
					dad_sys_systems as systems
				WHERE
					e.Events_ID IN (}. $Events_ID_in .q{)
					AND f.Events_ID=e.Events_ID
					AND (
						f.String_ID=s.String_ID
						)
					AND systems.System_ID=e.System_ID
					AND e.Time_Generated > }. $TimeFrame .q{
					GROUP BY f.Events_ID
					ORDER BY f.Events_ID,f.Position	, e.Time_Generated			
				};#print "$SQL\n";
			my $event_detail_ref = &SQL_Query($SQL);
			$num_results = @$event_detail_ref;
			if($num_results)
			{
				my $edrs;
				while($edrs=shift(@$event_detail_ref))
				{
					my @edra=@$edrs;
					$Report .= "$edra[1]|$edra[2]|$edra[3]\n";
				}
			}
		}
	}
	return "$Report\n";

}

####################
## send_email( $eSub, $eBody, $eTo, $eFrom, $eCC, $eBCC );
##
    sub SendEmail{
        use Net::SMTP;
        my( $eSub, $eBody, $eTo, $eFrom, $eCC, $eBCC ) = @_;

        $eFrom = $ENV{USER} if $eFrom eq '';
        $eFrom = $ENV{USERNAME} if $eFrom eq '';
        $eTo   = 'postmaster' if $eTo eq '';

        my $smtp = Net::SMTP->new('mail');#, Debug => 1);
        $smtp->mail(    $eFrom );
		my @recipients = split (/[;,]/,$eTo);
		$smtp->recipient(@recipients, { SkipBad => 1});
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
            $smtp->datasend("$_\n");
        }
        #$smtp->datasend("$eBody");
        $smtp->dataend();

        $smtp->quit;
        return 1;
    }

	##################################################
	#
	# SQL_Query - Does the legwork for all SQL queries including basic error checking
	# 	Takes a SQL string as an argument
	#
	##################################################
	sub SQL_Query
	{
		my $dsn = "DBI:mysql:host=$MYSQL_SERVER;database=dad";
		my $dbh = DBI->connect ($dsn, "$MYSQL_USER", "$MYSQL_PASSWORD")
		or return "Could not connect to DB server to run alerting.\n";

		my $SQL = $_[0];
#print "$SQL\n";		
		my $query = $dbh->prepare($SQL);
		$query -> execute();
		my $ref_to_array_of_row_refs = $query->fetchall_arrayref(); 
		$query->finish();
		return $ref_to_array_of_row_refs;
	}
	sub SQL_Insert
	{
		my $dsn = "DBI:mysql:host=$MYSQL_SERVER;database=dad";
		my $dbh = DBI->connect ($dsn, "$MYSQL_USER", "$MYSQL_PASSWORD")
		or return "Could not connect to DB server to run alerting.\n";
		my $SQL = $_[0];
#		my $query = $dbh->prepare($SQL);
		if($DEBUG){return; print"$SQL\n";return;}
#		$query -> execute();
#		$query->finish();

		my $result;
		$dbh->do($SQL) or die;
		$result = $dbh->{ q{mysql_insertid}};
		return $result;

	}

sub ManualAlert
{
$AlertDesc = shift;
$Severity = shift;
$event_data = "$AlertDesc";
$SQL = "INSERT INTO dad_alerts SET Alert_Time=".time().", Event_Time='".time()."', ".
		"Event_Data='".substr($event_data, 0, 199)."', Acknowledged=FALSE, Severity=$Severity";
&SQL_Insert($SQL);
}

sub Alert
{
# Grab all matching events that have occured since last alert job ran.
$AlertDesc = shift;
$Severity = shift;
$LastChecked = shift;
$results_ref = GetEventsByStringsPosition($LastChecked, @_); 
$num_results = @$results_ref;
	if($num_results)
	{
		while($row = shift(@$results_ref))
		{
			@this_row = @$row;
			$event_data = "$AlertDesc<br>".$this_row[3];
			$SQL = "INSERT INTO dad_alerts SET Alert_Time=".time().", Event_Time='".$this_row[1]."', ".
				"Event_Data='".substr($event_data, 0, 199)."', Acknowledged=FALSE, Severity=$Severity";
			&SQL_Insert($SQL);
		}
	}
}
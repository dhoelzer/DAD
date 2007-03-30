<?php
// This is the log analysis builder. - 5/2006 - DSH

function show_existing_queries()
{
global $Global;
global $_GET;
    $strURL  = getOptionURL(OPTIONID_EXISTING_QUERIES);
	$strSQL = 'SELECT Query_ID, Query, Name, Description, Category FROM dad_sys_queries ORDER BY Category,Name';
	$Queries = runQueryReturnArray( $strSQL );
	$strHTML = <<<END
		<form id=frmExistingQueries name="ExistingQueries" action="$strURL" method="post" style="position:relative; top:25px;">
		<table cellspacing=4 border=1>
END;
	$last_category = "None";
	$column=0;
	foreach($Queries as $Query)
	{
		if($last_category != $Query["Category"])
		{
			$last_category = $Query["Category"];
			if($column != 0) { $strHTML .= "</tr>"; }
			$strHTML .= <<<END
			<tr colspan=5><th colspan=4>$last_category</th></tr><tr>
END;
			$column = 1;
		}
		$ID = $Query["Query_ID"];
		$Name = $Query["Name"];
		$Description = $Query["Description"];
		if($column % 5 == 0)
		{
			$strHTML .= "</tr>\n<tr>";
			$column = 1;
		}
		$strHTML .= <<<END
				<td><a href="$strURL&SubmittedQuery=$ID" title="$Description">$Name</a></td>
END;
	$column++;
	}
	$strHTML .= "</table></form>";
	add_element($strHTML);
	if(isset($_GET["SubmittedQuery"]))
	{
		$QueryID = $_GET["SubmittedQuery"];
		$strSQL = "SELECT Query, Name FROM dad_sys_queries WHERE Query_ID='$QueryID'";
		$result = runQueryReturnArray($strSQL);
		$strSQL = stripslashes($result[0][0]);
		$QueryName = $result[0][1];
		$Popup_Contents = <<<END
			<STYLE TYPE='text/css'><!--.PopupTable{	font-size:8pt;}	--> </STYLE>
END;
		$Popup_Contents .= Query_to_Table($strSQL, 1, "PopupTable");
		Popup($QueryName, $Popup_Contents, 980, 650, 5, 5);
	}
}

function show_log_stats() 
{

    global $gaLiterals;

    $strSQL   = 'SELECT COUNT(*) FROM dad_sys_events';;
    $events = runQueryReturnArray( $strSQL );
	$num_events = $events[0][0];
    $strSQL   = 'SELECT COUNT(*) FROM dad_sys_systems';
    $systems = runQueryReturnArray( $strSQL );
    $strSQL   = 'SELECT COUNT(*) FROM dad_sys_services';
    $services = runQueryReturnArray( $strSQL );
	$FreeSpace = disk_free_space("d:");
	$TotalSpace = disk_total_space("d:");
	$MoreEvents = $FreeSpace/(($TotalSpace-$FreeSpace) / ($num_events + 1)+1);
	$PercentFree = round((($FreeSpace/($TotalSpace + 1)) * 100), 2);
	$PercentUsed = 100 - $PercentFree;
	
	$strHTML = "Disk Utilization: <img src='/images/percent.php?percent=$PercentUsed' valign=top halign=left> $PercentFree% Free";
	$strHTML .= "<br />There are a total of ".number_format($events[0][0])." events from ".
		number_format($systems[0][0])." systems reporting on ".number_format($services[0][0])." services.";
	$strHTML .= "<p>The database volume currently has ".number_format($FreeSpace)." bytes free (".
		$PercentFree."%).  ".
	    "This should be enough space for approximately ".number_format($MoreEvents)." more events.";
	$strHTML .= "<p><h3>Aggregate Log Statistics</h3><img src='/Stats/Aggregate.gif'>";
	$strHTML .= "<p><h3>BSRV2 Log Statistics</h3><img src='/Stats/BSRV2.gif'>";
	$strHTML .= "<p><h3>USDC007 Log Statistics</h3><img src='/Stats/USDC007.gif'>";
	$strHTML .= "<p><h3>USDC008 Log Statistics</h3><img src='/Stats/USDC008.gif'>";
	
    add_element($strHTML);
}

/*
 *	Query builder takes care of the dynamic interactive web interface for creating simple SQL
 *	queries.  Initially, some time was invested in creating an interface that would also support joins.
 *	This has been abandoned, but the initial code still exists, it simply needs to be re-enabled and
 *	completed.  The only piece remaining is to either programmatically determine where the tables
 *	should be joined, perhaps based on common field names, or to present the user with additional
 *	selection boxes to create the joins.
 *	5/06 - DSH
 */
function show_query_builder()
{
	global $Global;
	global $HTTP_POST_VARS;

	$PrimaryTable = isset($Global["primary_table"]) ? $Global["primary_table"] : NULL;

# Added special case to pop up a window with the field name contents if we're looking at dad_sys_events
	if($PrimaryTable == "dad_sys_events")
	{
		$Popup_Contents = <<<END
			<STYLE TYPE='text/css'><!--.PopupTable{	font-size:7pt;}	--> </STYLE>
END;
		$Popup_Contents .= Query_to_Table("SELECT dad_sys_field_descriptions.Service_ID, dad_sys_services.Service_Name, ".
			"Field_0_Name, Field_1_Name, Field_2_Name, Field_3_Name, Field_4_Name, ".
			"Field_5_Name, Field_6_Name, Field_7_Name, Field_8_Name, Field_9_Name ".
			"FROM dad_sys_field_descriptions,dad_sys_services WHERE dad_sys_field_descriptions.Service_ID=dad_sys_services.Service_ID",
			1, "PopupTable");
		Popup("Field Mappings for Events", $Popup_Contents, 800, 100);
	}
	# Retrieve the table names to populate the table selectors
	$aResults = runQueryReturnArray("SHOW TABLES LIKE 'dad%'");
	foreach($aResults as $row)
	{
		if($PrimaryTable == $row[0]) { $selected = " selected"; } else { $selected = ""; }
		$OptionList .= "<option value=\"$row[0]\"$selected>$row[0]";
	}

    $strURL  = getOptionURL(OPTIONID_QUERY_BUILDER);

/* We've decided to make the pain stop.  Secondary tables for joins are here but not completed:
	# Build the secondary table lists
	for($num_tables = 0; isset($HTTP_POST_VARS["table_$num_tables"]); $num_tables++)
	{
		$tables_selected[$num_tables] = $HTTP_POST_VARS["table_$num_tables"];
	}

	$num_tables = ($num_tables < 1 ? 0 : $num_tables-=1);
	for($i=0;$i != $num_tables+2;$i++)
	{
		foreach($aResults as $row)
		{
			if($tables_selected[$i] == $row[0]) { $selected = " selected";} else { $selected = ""; }
			$TablesList[$i] .= "<option value=\"$row[0]\"$selected>$row[0]";
		}
	}

	#Add one to the visible fields if we're actively adding a visible field with the last click
	if($HTTP_POST_VARS["Operation"] == "Add Table") { $num_tables++; }
*/
	# Retrieve the currently posted options for visible columns in the result set
	for($num_visible_fields = 0; isset($HTTP_POST_VARS["visible_fields_$num_visible_fields"]); $num_visible_fields++)
	{
		$visible_fields_selected[$num_visible_fields] = $HTTP_POST_VARS["visible_fields_$num_visible_fields"];
	}

	$num_visible_fields = ($num_visible_fields < 1 ? 0 : $num_visible_fields-=1);
	#Add one to the visible fields if we're actively adding a visible field with the last click
	if($HTTP_POST_VARS["Operation"] == "Add Field") { $num_visible_fields++; }

	#Retrieve the currently posted options for the filters in the result set
	for($num_filters = 0; isset($HTTP_POST_VARS["filter_$num_filters"]); $num_filters++)
	{
		$filters_selected[$num_filters] = $HTTP_POST_VARS["filter_$num_filters"];
		$filter_types[$num_filters] = $HTTP_POST_VARS["filter_type_$num_filters"];
		$filter_values[$num_filters] = $HTTP_POST_VARS["filter_value_$num_filters"];
	}

	$num_filters = ($num_filters < 1 ? 0 : $num_filters-=1);
	if($HTTP_POST_VARS["Operation"] == "Add Filter") { $num_filters++; }
	if($HTTP_POST_VARS["Operation"] == "Remove Filter") { $num_filters--;  add_element("Remove");}
	
# Set the javascript preamble for postbacks
	# The JavaScript below is intended to simulate the "Postback" functionality that ASP.NET has
	$strHTML .= <<<END
		<script language="javascript">  
		<!--  
		function PostBack() 
		{
			var theform = document.QueryBuilder;  
			theform.submit();  
		}  
		// --> 
		</script>
END;


	
/* First we put out the primary table selector */
	$strHTML .= <<<END
	
		<font align=center size=+1>Please use the query builder below to create new searches</font>
		<form id=frmQueryBuilder name="QueryBuilder" action="$strURL" method="post" style="position:relative; top:25px;">
		<table cellpadding=5>
			<tr>
				<td colspan=2 bgcolor="#ddddff"><center>Primary Table</center></td>
			</tr>
			<tr>
				<td>Primary table to select from</td>
				<td><select OnChange="PostBack()" name="primary_table">$OptionList</select></td>
			</tr>
END;

	if($PrimaryTable)
	{

		$SelectedTables[0] = $PrimaryTable;
/*		for($i=0; $i!=$num_tables+1; $i++)
		{
			$SelectedTables[$i+1] = $tables_selected[$i];
		}
*/
		for($field_num = 0; $field_num != $num_visible_fields+1; $field_num++)
		{
			foreach($SelectedTables as $Table_Name)
			{
				$aResults = SQLListFields($Table_Name);
				foreach($aResults as $row)
				{
					if($visible_fields_selected[$field_num] == "$Table_Name.$row[0]") { $selected = " selected"; } else { $selected = ""; }
					$FieldOptionList[$field_num] .= "<option value=\"$Table_Name.$row[0]\"$selected>$Table_Name.$row[0]";
				}
			}
		}
/*		$strHTML .= <<<END
			<tr>
				<td colspan=2 bgcolor="#ddddff"><center>Secondary Tables</center></td>
			</tr>
END;
		for($i=0; $i <= $num_tables; $i++)
		{
			$enabled = ($i == $num_tables ? "" : " disabled");
			$strHTML .= <<<END
			<tr>
				<td><select OnChange="PostBack()" name="table_$i">$TablesList[$i]</select></td>
				<td><input name="Operation" type=submit value="Add Table" $enabled></td>
			</tr>
END;
		}
*/
		$strHTML .= <<<END
			<tr>
				<td colspan=2 bgcolor="#ddddff"><center>Select Fields to Display in Results</center></td>
			</tr>
END;
		$goto = $num_visible_fields;
		for($i = 0; $i <= $num_visible_fields; $i++)
		{
			$enabled = ($i == $num_visible_fields ? "" : " disabled");
			$strHTML .= <<<END
			<tr>
				<td><select name="visible_fields_$i">$FieldOptionList[$i]</td>
				<td><input name="Operation" type=submit value="Add Field" $enabled></td>
			</tr>
END;
		}
	}
/* Next we set the filter conditions */
	if($PrimaryTable) # If we have visible column fields then we must have at least one field selected even if it's only the default
	{
		$Options[0] = "EQUALS";
		$Options[1] = "GREATER";
		$Options[2] = "LESS";
		$Options[3] = "CONTAINS";
		$Options[4] = "NOT EQUAL";
		$Options[5] = "DOES NOT CONTAIN";
		for($filter_num = 0; $filter_num != $num_filters+1; $filter_num++)
		{
			$aResults = SQLListFields($PrimaryTable);
			foreach($aResults as $row)
			{
				if($filters_selected[$filter_num] == $row[0]) { $selected = " selected"; } else { $selected = ""; }
				$FilterOptionList[$filter_num] .= "<option value=\"$row[0]\"$selected>$row[0]";
			}
			for($i = 0; $i != 6; $i++)
			{
				$selected = ( $filter_types[$filter_num] == $i ? " selected" : ""); 
				$Filter_Type_List[$filter_num] .= "<option value=\"$i\"$selected>$Options[$i]";
			}
		}
		$strHTML .= <<<END
			<tr>
				<td colspan=2 bgcolor="#ddddff"><center>Select Filters to Apply to the Results</center></td>
			</tr>
END;
		$goto = $num_filters;
		$strHTML .= "<tr><td colspan=2><table cellpadding=2>";
		for($i = 0; $i <= $num_filters; $i++)
		{
			$enabled = ($i == $num_filters ? "" : " disabled");
			$enabled2 = (($i == 0) || ($i != $num_filters) ? "disabled" : "");
			$strHTML .= <<<END
			<tr>
				<td><select name="filter_$i">$FilterOptionList[$i]</td>
				<td><select name="filter_type_$i">$Filter_Type_List[$i]</td>
				<td><input type="text" name="filter_value_$i" value="$filter_values[$i]" width=15></td>
				<td>
					<input name="Operation" type=submit value="Add Filter" $enabled>
					<input name="Operation" type="submit" OnClick="PostBack()" value="Remove Filter"$enabled2>
				</td>
			</tr>
END;
		}
		$strHTML .= "</table></td></tr>";
	
	}
/* And finally we choose grouping and sorting options */	

/* Last of all, we process a submitted query */
	$strHTML .= <<<END
		<tr bgcolor="#ddddff">
			<td colspan=2>
				<center>
					<input name="Operation" type=submit value="Process Result Set">
					<input type="submit" name="btnSave" value="Save Query">
				</center>
			</td>
		</tr>
END;
	add_element($strHTML . "</table><hr>");
	if(isset($HTTP_POST_VARS["Operation"]) and $HTTP_POST_VARS["Operation"] == "Process Result Set")
	{
		for($i=0; $i!=$num_visible_fields+1; $i++)
		{
			$fields .= ($i ? ",". $visible_fields_selected[$i] : $visible_fields_selected[$i]);
		}
		for($i=0; $i!=$num_filters+1; $i++)
		{
			switch($filter_types[$i]) {
				case 0:
					$expr = "$filters_selected[$i]='$filter_values[$i]' ";
					break;
				case 1:
					$expr = "$filters_selected[$i]>'$filter_values[$i]' ";
					break;
				case 2:
					$expr = "$filters_selected[$i]<'$filter_values[$i]' ";
					break;
				case 3:
					$expr = "$filters_selected[$i] LIKE '%".$filter_values[$i]."%' ";
					break;
				case 4:
					$expr = "NOT $filters_selected[$i]='$filter_values[$i]' ";
					break;
				case 5:
					$expr = "NOT $filters_selected[$i] LIKE '%".$filter_values[$i]."%' ";
					break;
				}
			if($i > 0) { $TheFilter .= "AND "; }
			$TheFilter .= $expr;
		}
		$flag = 0;
		foreach($SelectedTables as $Table)
		{
			if($flag++ > 0) { $Tables .= ","; }
			$Tables .= "$Table";
		}
		add_element(query_to_table("SELECT $fields FROM $Tables WHERE $TheFilter"));
	}
}

/*
 *	The show_sql_query function handles the dynamic creation and execution of SQL queries through
 *	the web interface.  This function also provides a button to allow you to save a query for later use through
 *	the "Saved Queries" interface.
 *	5/06 - DSH
 */
function show_sql_query()
{
    global $Global;
	global $HTTP_POST_VARS;

    $strURL  = getOptionURL(OPTIONID_SQL_QUERY);   
    // Get post variables from $Globals array
    $strSQLQuery = isset($Global["txtSQLQuery"]) ? $Global["txtSQLQuery"] : NULL;
	if(isset($Global["btnSave"]))
	{
		$ButtonName = (isset($Global["txtQueryName"]) ? $Global["txtQueryName"] : "");
		$QueryDescription = (isset($Global["txtQueryDescription"]) ? $Global["txtQueryDescription"] : "");
		if($ButtonName == "" or $QueryDescription == "") 
		{
			add_element("<h4>You must set a name and a description to save a query.</h4>");
		}
		else
		{
			$strSQL = "INSERT INTO dad_sys_queries (Query, Description, Name) ".
				"VALUES ('$strSQLQuery', '$QueryDescription', '$ButtonName')";
			$intRowsAffected = runSQLReturnAffected($strSQL);
			if ($intRowsAffected < 1)
			{
			$MYSQL_ERRNO = mysql_errno();
            $MYSQL_ERROR = mysql_error();
				add_element("<h4>Error inserting new saved query! $MYSQL_ERRNO : $MYSQL_ERROR</h4>");
			}
			else
			{
				add_element("<h4>Saved '$ButtonName'!</h4>");
			}
		}
	}
	$strSQLQuery = stripslashes($strSQLQuery);
	$output = (isset($Global["btnProcess"]) ? 1 : 0);
	if(!$strSQLQuery) { $strSQLQuery = "SELECT COUNT(*) FROM dad_sys_events"; }
	$strHTML = <<<END
		<form id="frmSQLQuery" action="$strURL" method="post" style="position:relative; top:25px;">
			<table cellpadding=5>
			<tr>
				<td colspan="2"><h2>Raw SQL Query</h2></td>
			</tr>
			<tr>
				<td valign=top>Please enter query here:</td>
				<td><textarea id="txtSQLQuery" cols="60" rows="8" name="txtSQLQuery">$strSQLQuery</textarea></td>
			</tr>
			<tr>
				<td>Query Name: <input type=text size=15 name="txtQueryName"></td>
				<td><textarea name="txtQueryDescription" rows=2 cols=60>Description</textarea>
			</tr>
			<tr>
				<td colspan=2>
					<center>
						<input type="submit" name="btnProcess" value="Process Query">
						<input type="submit" name="btnSave" value="Save Query">
					</center>
				</td>
			</tr>
			</table>               
		</form><br>
END;
	$strHTML .= "<hr>";
	if($output) 
	{ 
		$strHTML .= query_to_table($strSQLQuery);
	}
	add_element($strHTML);
}

/*
  query_to_table(SQL Expression[, Quiet[, TableClass]])
  
	This function processes a SQL expression and returns the result set as an HTML table with column headings
*/
function query_to_table($QueryString, $quiet=0, $TableClass="default")
{
global $Global;

	$retval = "";
	$aResults = runQueryReturnArray($QueryString);
	if(! $quiet){ $retval .="<h3>Query results for:</h3>$QueryString<p>"; }
	$retval .= build_table_from_query($aResults,"*","2","1","1","#dddddd","#ffaaaa", $TableClass);
	return($retval);		
}

function another_func()
{
global $HTTP_GET_VARS;

$start = (isset($HTTP_GET_VARS["start"]) ? $HTTP_GET_VARS["start"] : 0);

$result_id = mysql_query("SELECT DISTINCT dad_sys_systems.System_Name as SystemName, dad_sys_events.Timestamp as Timestamp, ".
	"dad_sys_services.Service_Name as ServiceName, dad_sys_events.Field_4 as DomainUser, dad_sys_events.Field_6 as Message ".
	"FROM dad_sys_systems, dad_sys_events, dad_sys_services ".
	"WHERE ".
		"dad_sys_services.Service_ID = dad_sys_events.Service_ID and ".
		"dad_sys_systems.System_ID = dad_sys_events.System_ID and ".
		"dad_sys_events.Service_ID=1994 and ".
		"dad_sys_events.Field_6 NOT LIKE 'Login%' and ".
		"dad_sys_events.Field_6 NOT LIKE 'ERROR: #1024%' and ".
		"dad_sys_events.Field_6 NOT LIKE 'Failed login%'");
$i = 0;
$row_count = mysql_num_rows($result_id);
if($start < 0 or $start > $row_count)
{
	print "<h3>Illegal starting point:  $start</h3>";
	mysql_free_result($result_id);
	exit;
}
if($start > 0) 
{ 
	if($start >= 500) { $prev_start = $start - 500; } else { $prev_start = 0; }
	$next = "<a href='?start=$prev_start'>Previous</a> ";
}
else { $next = "Previous "; }
if($start < $row_count)
{
	if($row_count - $start > 500) 
	{
		$next_start = $start + 500;
		$next .= "<a href='?start=$next_start'>Next</a><hr>";
	}
	else { $next .= "Next<hr>"; }
}
else { $next .= "Next<hr>"; $start=$row_count - 500; }

?>
<?=$next?>
<h3>Rows <?=$start?> to <?=($start+500 > $row_count ? $row_count : $start+500)?> out of <?=$row_count?> rows</h3>
<table border=1 cellpadding=3 cellspacing=3>
	<tr><td>System</td><td>Time</td><td>Service</td><td>Domain/User</td><td>Event</td></tr>
	<?php

	while($i++ < $start and $row = mysql_fetch_row($result_id)){;}
	while($i++ < $start+500 and $row = mysql_fetch_row($result_id))
	{
	
?>
		<tr><td><?=$row[0]?></td>
		<td><?=$row[1]?></td>
		<td><?=$row[2]?></td>
		<td><?=$row[3]?></td>
		<td><?=$row[4]?></td></tr>
<?php		
		
	}
	mysql_free_result($result_id);

}
?>
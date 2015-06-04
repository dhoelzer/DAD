Feature: Adding alerts
When alerts are generated and added to the database,
we expect there to be a number of behaviors that are true.

Scenario: Adding a new alert
	Given that there is an event in the databases
	And there is a job that will generate an alert
	When the job runs
	And finds one event that matches
	Then an alert will be generated
	And that alert will include that event

Scenario: Adding an alert with multiple events
	Given that there are multiple events in the databases
	And there is a job that will generate an alert
	When the job runs
	And finds more than one event that matches
	Then an alert will be generated
	And that alert will includes all of those events
	
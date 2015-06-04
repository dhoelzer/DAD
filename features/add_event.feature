Feature: Adding events
As a system,
	I want to be able to generate events with words,
	so that each word is stored only one time.

Scenario: Adding a new word
	Given Im adding an event made up of words
	When I add a word
	And that word is new
	Then the word is added to the list of words

Scenario: Adding an existing word
	Given Im adding an event made up of words
	When I add a word
	And that word is already in the table
	Then the word is not added to the list of words

Scenario: Storing an event
	Given a new event has occurred
	When the event text is sent to the Event model
	And the event is processed
	Then the event will be retrievable and roughly equivalent to the original
	
Scenario: Searching for an event that is in the correct time frame
	Given an event has been stored previously
	When someone searches for the words in that event
	Then the event will be found

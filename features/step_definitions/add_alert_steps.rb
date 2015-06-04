Given(/^that there is an event in the databases$/) do
  eventString = "50.16.29.46 Jun  1 14:07:16 ip-10-159-49-236 sshd[26938]: Received disconnect from 173.246.41.99: 11: Bye Bye [preauth]"
  event_count = Event.all.count
  Event.storeEvent(eventString)
  expect(Event.all.count - event_count).to eq 1
end

Given(/^there is a job that will generate an alert$/) do
  pending # express the regexp above with the code you wish you had
end

When(/^the job runs$/) do
  pending # express the regexp above with the code you wish you had
end

When(/^finds one event that matches$/) do
  pending # express the regexp above with the code you wish you had
end

Then(/^an alert will be generated$/) do
  pending # express the regexp above with the code you wish you had
end

Then(/^that alert will include that event$/) do
  pending # express the regexp above with the code you wish you had
end

Given(/^that there are multiple events in the databases$/) do
  pending # express the regexp above with the code you wish you had
end

When(/^finds more than one event that matches$/) do
  pending # express the regexp above with the code you wish you had
end

Then(/^that alert will includes all of those events$/) do
  pending # express the regexp above with the code you wish you had
end

eventString = "50.16.29.46 Jun  1 14:07:16 ip-10-159-49-236 sshd[26938]: Received disconnect from 173.246.41.99: 11: Bye Bye [preauth]"
words = Array.new
word = ""
existing_word = ""

Given(/^Im adding an event made up of words$/) do
end

When(/^I add a word$/) do
  words = eventString.split(/\s+/)
  word = words[0]
end

When(/^that word is new$/) do
  expect(Word.where(text: word.downcase).count).to eq 0
end

Then(/^the word is added to the list of words$/) do
  Word.create(text: word)
  expect(Word.where(text: word).count).to eq 1
end

When(/^that word is already in the table$/) do
  Word.create(text: word)
  existing_word = Word.where(text: word).first
  expect(existing_word.nil?).to eq false
end

Then(/^the word is not added to the list of words$/) do
  new_words = Word.where(text: word)
  expect(new_words.count).to eq 1
end


Given(/^a new event has occurred$/) do
end

When(/^the event text is sent to the Event model$/) do
  @startingEvents = Event.count
  Event.storeEvent(eventString)
end

When(/^the event is processed$/) do
  expect(Event.count - @startingEvents).to eq 1
end

Then(/^the event will be retrievable and roughly equivalent to the original$/) do
  etext = Event.last.inspect.gsub(/\s+/, '')
  otext = eventString.gsub(/\s+/, '')
  expect(etext.include?(otext)).to eq true
end



Given(/^an event has been stored previously$/) do
  Event.storeEvent("1.1.1.1 Jun 1 00:00:00 this-is-a-test testservice[123]: This is just a test event")
end

When(/^someone searches for the words in that event$/) do
  @results = Event.search("This is just a test event", 0)
end

Then(/^the event will be found$/) do
  expect(@results.count).to eq 1
end

class FixGeneratedColumnDefaults < ActiveRecord::Migration
  def up
    # The original migrations passed `:default => Time.now`, which bakes the
    # timestamp of *that* migration run into the column. Every later
    # `rake db:migrate` therefore dumps a different schema.rb, and a row
    # inserted without an explicit `generated` silently gets a 2014/2015
    # timestamp. Nothing in the app relies on the default -- storeEvent's raw
    # INSERTs and the fixtures always supply `generated` -- so drop it and let
    # NOT NULL surface the mistake instead.
    change_column_default :events, :generated, nil
    change_column_default :events_words, :generated, nil
  end

  def down
    change_column_default :events, :generated, Time.now
    change_column_default :events_words, :generated, Time.now
  end
end

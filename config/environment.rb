# Load the Rails application.
require File.expand_path('../application', __FILE__)

# Override innoDB default
require 'active_record/connection_adapters/mysql2_adapter'
module ActiveRecord
  module ConnectionAdapters
    class Mysql2Adapter
      def create_table(table_name, options = {}) #:nodoc:
        super(table_name, options.reverse_merge(:options => "ENGINE=MyISAM"))
      end
    end
  end
end

# Initialize the Rails application.
Events::Application.initialize!

# Load the Rails application.
require File.expand_path('../application', __FILE__)

# Override innoDB default
module ActiveRecord
        module ConnectionAdapters
                class Mysql2Adapter < AbstractAdapter
                        def create_table(table_name, options = {}) #:nodoc:
                                super(table_name, options.reverse_merge(:options => "ENGINE=MyISAM"))
                        end
                end
        end
end

# Initialize the Rails application.
Events::Application.initialize!

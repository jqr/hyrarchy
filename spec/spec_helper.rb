require 'rubygems'
gem 'sqlite3-ruby'
require 'spec'
require 'activerecord'
require 'yaml'
require 'narray'

# Load and activate Hyrarchy.
$: << File.join(File.dirname(__FILE__), '..', 'lib')
require 'hyrarchy'
Hyrarchy.activate!

# Set up a logger.
log_path = File.join(File.dirname(__FILE__), 'log')
File.unlink(log_path) rescue nil
ActiveRecord::Base.logger = ActiveSupport::BufferedLogger.new(log_path)
ActiveRecord::Base.logger.add 0, "\n"

# Connect to the test database.
db_specs = YAML.load_file(File.join(File.dirname(__FILE__), 'database.yml'))
which_spec = ENV['DB'] || 'mysql'
ActiveRecord::Base.establish_connection(db_specs[which_spec])

# Create a model class for testing.
class Node < ActiveRecord::Base
  is_hierarchic
  connection.execute("TRUNCATE TABLE #{quoted_table_name}") rescue delete_all
  def inspect; name end
end

# Runs a block and returns how long it took in seconds (with subsecond
# precision).
def measure_time(&block)
  start_time = Time.now
  yield
  Time.now - start_time
end

# Calculates the slope and offset of a data set.
def linear_regression(data)
  sxx = sxy = sx = sy = 0
  data.length.times do |x|
    y = data[x]
    sxy += x*y
    sxx += x*x
    sx  += x
    sy  += y
  end
  slope = (data.length * sxy - sx * sy) / (data.length * sxx - sx * sx)
  offset = (sy - slope * sx) / data.length
  [slope, offset]
end

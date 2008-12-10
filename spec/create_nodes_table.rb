require 'rubygems'
require 'activerecord'
require 'yaml'

$: << File.join(File.dirname(__FILE__), '..', 'lib')
require 'hyrarchy'
Hyrarchy.activate!

db_spec = YAML.load_file(File.join(File.dirname(__FILE__), 'database.yml'))
ActiveRecord::Base.establish_connection(db_spec)

class CreateNodesTable < ActiveRecord::Migration
  def self.up
    create_table :nodes do |t|
      t.string :name, :null => false
    end
    add_hierarchy :nodes
  end
  
  def self.down
    drop_table :nodes
  end
end

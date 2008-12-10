$dir = File.dirname(__FILE__)

desc "Run all unit tests"
task :test do
  tests = FileList["#{$dir}/test/*_test.rb"]
  tests.each {|t| require t}
end

desc "Run all specs"
task :spec do
  system('spec', '-c', "#{$dir}/spec")
end

namespace "migrate" do
  desc "Run the migration for the specs"
  task :up do
    require "#{$dir}/spec/create_nodes_table"
    CreateNodesTable.up
  end
  
  desc "Revert the migration for the specs"
  task :down do
    require "#{$dir}/spec/create_nodes_table"
    CreateNodesTable.down
  end
end

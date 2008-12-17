require 'rake/gempackagetask'
$dir = File.dirname(__FILE__)

task :default => :package

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

spec = eval(IO.read("#{$dir}/hyrarchy.gemspec"))
gem_pkg_task = Rake::GemPackageTask.new(spec) do |pkg|
  pkg.need_tar = false
end

desc "Install the gem with sudo"
task :install => :package do
  system('sudo', 'gem', 'install', "#{$dir}/#{gem_pkg_task.package_dir}/#{gem_pkg_task.gem_file}")
end

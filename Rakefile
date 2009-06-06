require 'rake/gempackagetask'
$dir = File.dirname(__FILE__)

task :default => :package

task :test => :spec

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

task :sqlite do
  ENV['DB'] = 'sqlite'
end

task :performance do
  ENV['PERFORMANCE'] = 'true'
end
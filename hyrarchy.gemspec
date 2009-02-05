Gem::Specification.new do |s| 
  s.name = 'hyrarchy'
  s.version = '0.3.2'
  s.author = 'Dana Danger'
  s.homepage = 'http://github.com/DanaDanger/hyrarchy'
  s.platform = Gem::Platform::RUBY
  s.summary = 'A gem and Rails plugin for working with hierarchic data.'
  s.files = [
    'lib/hyrarchy.rb',
    'lib/hyrarchy/collection_proxy.rb',
    'lib/hyrarchy/encoded_path.rb',
    'lib/hyrarchy/awesome_nested_set_compatibility.rb',
    'rails_plugin/init.rb',
    'README.rdoc',
    'spec/create_nodes_table.rb',
    'spec/database.yml',
    'spec/hyrarchy_spec.rb',
    'spec/spec_helper.rb',
    'test/encoded_path_test.rb',
    'test/test_helper.rb'
  ]
  s.test_files = [
    'spec/create_nodes_table.rb',
    'spec/database.yml',
    'spec/hyrarchy_spec.rb',
    'spec/spec_helper.rb',
    'test/encoded_path_test.rb',
    'test/test_helper.rb'
  ]
  s.has_rdoc = true
  s.extra_rdoc_files = ['README.rdoc', 'LICENSE']
  s.rdoc_options << '--all' << '--inline-source' << '--line-numbers'
end

Gem::Specification.new do |spec|
  spec.name        = 'enumancer'
  spec.version     = '2.0.0'
  spec.summary     = 'Closed enums and algebraic data types for Ruby.'
  spec.description = <<DESC
    Enumancer provides plain enums, backed enums, and algebraic data types
    with typed fields and exhaustive matching.
DESC
  spec.authors     = ['Łasačka']
  spec.email       = 'saikinmirai@gmail.com'
  spec.files = Dir['lib/**/*.rb'] + ['readme.md', 'CHANGELOG.md', 'LICENSE']
  spec.homepage    = 'https://github.com/lasaczka/enumancer'

  spec.metadata['changelog_uri'] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata['bug_tracker_uri'] = "#{spec.homepage}/issues"
  spec.metadata['documentation_uri'] = "https://rubydoc.info/gems/enumancer/#{spec.version}"

  spec.license       = 'BSD-3-Clause-Attribution'
  spec.required_ruby_version = '>= 4.0'
end

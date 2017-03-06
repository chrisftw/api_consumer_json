Gem::Specification.new do |s|
  s.name        = 'api_consumer_json'
  s.version     = '0.0.8'
  s.date        = '2017-03-06'
  s.summary     = "Consume all the APIs"
  s.description = "Easy to use API consumer - Setup your API connection in a yaml file, and use the helper methods to make easy access APIs calls"
  s.authors     = ["Chris Reister"]
  s.email       = 'chris@chrisreister.com'
  s.files       = ["lib/api_consumer.rb"]
  s.homepage    = 'https://github.com/chrisftw/api_consumer_json'
  s.license     = 'MIT'
  
  s.add_runtime_dependency 'uber_cache', '~> 0.0'

  # might work with older development_dependencies.
  s.add_development_dependency 'rspec', '~> 3.0'
  s.add_development_dependency 'fakeweb', '~> 1.3'
end

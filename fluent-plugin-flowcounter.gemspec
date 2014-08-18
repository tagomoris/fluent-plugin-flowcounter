# -*- encoding: utf-8 -*-
Gem::Specification.new do |gem|
  gem.name        = "fluent-plugin-flowcounter"
  gem.version     = "0.2.1"
  gem.authors     = ["TAGOMORI Satoshi"]
  gem.email       = ["tagomoris@gmail.com"]
  gem.summary     = %q{Fluent plugin to count message flow}
  gem.description = %q{Plugin to counts messages/bytes that matches, per minutes/hours/days}
  gem.homepage    = "https://github.com/tagomoris/fluent-plugin-flowcounter"
  gem.license     = "APLv2"

  gem.files         = `git ls-files`.split($\)
  gem.executables   = gem.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  gem.test_files    = gem.files.grep(%r{^(test|spec|features)/})
  gem.require_paths = ["lib"]

  gem.add_development_dependency "rake"
  gem.add_runtime_dependency "fluentd"
  gem.add_runtime_dependency "fluent-mixin-config-placeholders", ">= 0.3.0"
end

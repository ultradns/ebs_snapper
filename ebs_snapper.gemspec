# -*- encoding: utf-8 -*-
require File.expand_path('../lib/ebs_snapper/version', __FILE__)

Gem::Specification.new do |s|
  s.authors       = ["ultradns"]
  s.email         = ["ultradns@neustar.biz"]

  s.description   = %q{Manage snapshots of EBS volumes}
  s.summary       = %q{Manage snapshots of EBS volumes}
  s.homepage      = "https://github.com/ultradns/ebs_snapper"

  s.files         = `git ls-files`.split($\)
  s.executables   = s.files.grep(%r{^bin/}).map{ |f| File.basename(f) }
  s.test_files    = s.files.grep(%r{^(test|spec|features)/})
  s.name          = "ebs_snapper"
  s.require_paths = ["lib"]
  s.version       = EbsSnapper::VERSION
  
  s.add_runtime_dependency "aws-sdk", "~> 1.11.3"
  
  s.add_development_dependency "rake"
  s.add_development_dependency "rspec"
  s.add_development_dependency "fakeweb"
  
end

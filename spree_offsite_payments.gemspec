# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'spree_offsite_payments/version'

Gem::Specification.new do |spec|
  spec.name          = "spree_offsite_payments"
  spec.version       = SpreeOffsitePayments::VERSION
  spec.authors       = ["叶树剑"]
  spec.email         = ["yeshujian@shiguangcaibei.com"]
  spec.summary       = %q{This gem integrates Shopify Offsite_Payments gem with Spree Commerce.}
  spec.description   = %q{This is to replace the "spree_alipay" gem.}
  spec.homepage      = ""
  spec.license       = "MIT"

  spec.files         = `git ls-files -z`.split("\x0")
  spec.executables   = spec.files.grep(%r{^bin/}) { |f| File.basename(f) }
  spec.test_files    = spec.files.grep(%r{^(test|spec|features)/})
  spec.require_paths = ["lib"]

  spec.add_development_dependency "bundler", "~> 1.7"
  spec.add_development_dependency "rake", "~> 10.0"
  spec.add_development_dependency "rspec"
end

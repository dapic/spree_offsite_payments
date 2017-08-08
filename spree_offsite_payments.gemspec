# coding: utf-8
lib = File.expand_path('../lib', __FILE__)
$LOAD_PATH.unshift(lib) unless $LOAD_PATH.include?(lib)
require 'spree_offsite_payments/version'

Gem::Specification.new do |spec|
  spec.name          = "spree_offsite_payments"
  spec.version       = SpreeOffsitePayments::VERSION
  spec.authors       = ["叶树剑", "Arkhitech"]
  spec.email         = ["yeshujian@shiguangcaibei.com", "online@arkhitech.com"]

  spec.summary       = %q{This gem integrates Shopify Offsite_Payments gem with Spree Commerce.}
  spec.description   = %q{This is to replace the "spree_alipay" gem.}

  # Prevent pushing this gem to RubyGems.org. To allow pushes either set the 'allowed_push_host'
  # to allow pushing to a single host or delete this section to allow pushing to any host.
  if spec.respond_to?(:metadata)
    spec.metadata['allowed_push_host'] = "TODO: Set to 'http://mygemserver.com'"
  else
    raise "RubyGems 2.0 or newer is required to protect against " \
      "public gem pushes."
  end

  spec.files         = `git ls-files -z`.split("\x0").reject do |f|
    f.match(%r{^(test|spec|features)/})
  end
  spec.bindir        = "exe"
  spec.executables   = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = ["lib"]


  spec.add_dependency 'spree_core', '>= 3.0.10'
  spec.add_dependency 'offsite_payments'
  spec.add_dependency 'rqrcode-rails3'
  spec.add_dependency 'redis'
  spec.add_runtime_dependency 'weixin_authorize'
  spec.add_runtime_dependency 'mini_magick'

  spec.add_development_dependency 'capybara', '>= 2.1'
  spec.add_development_dependency 'coffee-rails'
  spec.add_development_dependency 'database_cleaner'
  spec.add_development_dependency 'factory_girl', '>= 4.4'
  spec.add_development_dependency 'ffaker'
  
  spec.add_development_dependency 'rspec-rails',  '>= 2.13'
  spec.add_development_dependency "bundler", ">= 1.14"
  spec.add_development_dependency "rake", ">= 10.0"
  spec.add_development_dependency "rspec"
  
  spec.add_development_dependency 'sass-rails'
  spec.add_development_dependency 'selenium-webdriver'
  spec.add_development_dependency 'simplecov'
  spec.add_development_dependency 'sqlite3'
  spec.add_development_dependency 'guard-rspec'
  
end

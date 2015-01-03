# encoding: UTF-8
require './lib/spree_offsite_payments/version'
Gem::Specification.new do |s|
  s.platform    = Gem::Platform::RUBY
  s.name        = 'spree_offsite_payments'
  s.version     = SpreeOffsitePayments::VERSION
  s.authors       = ["叶树剑"]
  s.email         = ["yeshujian@shiguangcaibei.com"]
  s.summary       = %q{This gem integrates Shopify Offsite_Payments gem with Spree Commerce.}
  s.description   = %q{This is to replace the "spree_alipay" gem.}
  s.license     = 'New BSD'
  s.required_ruby_version = '>= 1.9.3'

  s.files         = `git ls-files -z`.split("\x0")
  s.executables   = s.files.grep(%r{^bin/}) { |f| File.basename(f) }
  s.test_files    = s.files.grep(%r{^(test|spec|features)/})
  s.require_path = 'lib'
  s.requirements << 'none'

  s.add_dependency 'spree_core', '~> 2.4'
  s.add_dependency 'offsite_payments'
  s.add_dependency 'rqrcode-rails3'

  s.add_development_dependency 'capybara', '~> 2.1'
  s.add_development_dependency 'coffee-rails'
  s.add_development_dependency 'database_cleaner'
  s.add_development_dependency 'factory_girl', '~> 4.4'
  s.add_development_dependency 'ffaker'
  s.add_development_dependency 'rspec-rails',  '~> 2.13'
  s.add_development_dependency 'sass-rails', '~> 4.0.2'
  s.add_development_dependency 'selenium-webdriver'
  s.add_development_dependency 'simplecov'
  s.add_development_dependency 'sqlite3'
end

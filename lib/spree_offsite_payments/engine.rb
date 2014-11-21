module SpreeOffsitePayments
  class Engine < Rails::Engine
    require 'spree/core'
    isolate_namespace Spree
    engine_name 'spree_offsite_payments'
    config.autoload_paths += %W(#{config.root}/lib)

    # use rspec for tests
    config.generators do |g|
      g.test_framework :rspec
    end

    def self.activate
      Dir.glob(File.join(File.dirname(__FILE__), '../../app/**/*.rb')) do |c|
        Rails.configuration.cache_classes ? require(c) : load(c)
      end
    end

    config.to_prepare &method(:activate).to_proc

    config.after_initialize do |app|
      require 'offsite_payments/action_view_helper'
      ActionView::Base.send(:include, OffsitePayments::ActionViewHelper)

      app.config.spree.payment_methods += [
        Spree::BillingIntegration::Alipay,
        Spree::BillingIntegration::Tenpay
      ]
    end
  end
end

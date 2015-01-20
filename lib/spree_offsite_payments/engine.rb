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
      #Explicitly setting the order here is to make sure models and services are loaded before controllers
      %w(models services *).each do |partial_path|
        Dir.glob(File.join(File.dirname(__FILE__), '../../app/', partial_path, '/**/*.rb')) do |c|
          Rails.configuration.cache_classes ? require(c) : load(c)
        end
      end
    end

    config.to_prepare &method(:activate).to_proc

    config.after_initialize do |app|
      require 'offsite_payments/action_view_helper'
      ActionView::Base.send(:include, OffsitePayments::ActionViewHelper)

      app.config.spree.payment_methods += [
        Spree::BillingIntegration::Alipay,
        Spree::BillingIntegration::AlipayWap,
        Spree::BillingIntegration::Wxpay,
        Spree::BillingIntegration::Tenpay
      ]
    end
  end
end

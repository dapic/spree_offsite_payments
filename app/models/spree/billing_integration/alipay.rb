module Spree
  class BillingIntegration::Alipay < BillingIntegration
    preference :partner, :string
    preference :sign, :string
    preference :email, :string
    preference :using_direct_pay_service, :boolean, :default => false #CREATE_DIRECT_PAY_BY_USER
    preference :server, :string
    preference :test_mode, :boolean, :default => true
     
    def provider_class
      ::OffsitePayments::Integrations::Alipay
    end
    
    def key
      preferred_sign
    end
        
  end
end

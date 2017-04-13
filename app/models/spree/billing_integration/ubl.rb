module Spree
  class BillingIntegration::UBL < BillingIntegration
    preference :test_mode, :boolean, :default => true
     
    def provider_class
      ::OffsitePayments::Integrations::UBL
    end
    
    def key
      preferred_sign
    end
        
  end
end
module Spree
  class BillingIntegration::UBL < BillingIntegration
    preference :test_mode, :boolean, :default => true
     
    def provider_class
      ::OffsitePayments::Integrations::Ubl
    end
    
    def key
      preferred_sign
    end
        
  end
end
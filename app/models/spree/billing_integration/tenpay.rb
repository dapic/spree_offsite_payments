module Spree
  class BillingIntegration::Tenpay < BillingIntegration
    preference :partner, :string
    preference :partner_key, :string
     
    def provider_class
      OffsitePayments::Integrations::Tenpay
    end
        
  end
end

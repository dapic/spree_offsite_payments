module Spree
  class BillingIntegration::Tenpay < BillingIntegration
    preference :partner, :string
    preference :partner_key, :string
     
    def provider_class
      ::OffsitePayments::Integrations::Tenpay
    end
        
    def key
      preferred_partner_key
    end
  end
end

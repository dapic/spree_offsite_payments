module Spree
  class BillingIntegration::AlipayWap < BillingIntegration
    preference :partner, :string
    preference :key, :string
    preference :email, :string

    def provider_class
      ::OffsitePayments::Integrations::AlipayWap
    end
        
  end
end

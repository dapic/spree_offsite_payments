module Spree
  class BillingIntegration::Wxpay < BillingIntegration
    preference :appid, :string
    preference :appsecret, :string
    preference :api_key, :string
    preference :mch_id, :string
     
    def provider_class
      ::OffsitePayments::Integrations::Wxpay
    end
        
    def key
      preferred_api_key
    end
  end
end

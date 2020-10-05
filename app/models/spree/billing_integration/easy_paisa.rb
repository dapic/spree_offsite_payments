module Spree
  class BillingIntegration::EasyPaisa < BillingIntegration
    preference :test_mode, :boolean, default: true
    preference :store, :integer
    preference :hash, :string
    preference :partner_username, :string
    preference :partner_password, :string
    preference :partner_wsdl, :string
     
    def provider_class
      ::OffsitePayments::Integrations::EasyPaisa
    end
    
    def test?
      preferred_test_mode
    end
    
    def store_id
      preferred_store
    end
    
    def hash_key
      preferred_hash
    end
    def source_required?
      false
    end
       
    def partner_username
      preferred_partner_username
    end

    def partner_password
      preferred_partner_password
    end
    
    def partner_wsdl
      preferred_partner_wsdl.presence || 'https://easypay.easypaisa.com.pk/easypay-service/PartnerBusinessService/META-INF/wsdl/partner/transaction/PartnerBusinessService.wsdl'
    end
    
  end
end
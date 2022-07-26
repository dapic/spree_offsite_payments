module Spree
  class BillingIntegration::JazzCash < BillingIntegration
    preference :test_mode, :boolean, default: true
    preference :store, :integer
    preference :hash, :string
     
    def provider_class
      ::OffsitePayments::Integrations::JazzCash
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
        
  end
end
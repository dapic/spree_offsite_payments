module OffsitePayments
  module PaymentDecorator
    def self.prepended(base)
      base.alias_attribute :payment_url, :avs_response
      base.alias_attribute :foreign_transaction_id, :cvv_response_code
      base.alias_attribute :prepay_id, :cvv_response_message    
    end
    Spree::Payment.prepend self  
  end
end

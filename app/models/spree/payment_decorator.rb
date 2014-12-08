Spree::Payment.class_eval do
  #we reuse this field to store the payment_url
  #avs_response if only used for creditcard payments, not offsite payments
  alias_attribute :payment_url, :avs_response
  alias_attribute :foreign_transaction_id, :cvv_response_code
end

FactoryGirl.define do
  factory :wxpay_payment, class: Spree::Payment do
    association(:payment_method, factory: :wxpay_payment_method)
    association(:order, factory: :order_with_line_items)
    state 'checkout'
  end

end

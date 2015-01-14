FactoryGirl.define do
  factory :wxpay_payment_method, class: Spree::BillingIntegration::Wxpay do
    name "微信支付"
    environment 'test'
    preferred_appid 'wxpay_app_id'
    preferred_appsecret 'wxpay_app_secret'
    preferred_mch_id 'wxpay_mch_id'
    preferred_api_key 'wxpay_api_key'
  end
end

Spree::Core::Engine.routes.draw do
  resources :orders do
    resource :checkout, :controller => 'checkout' do
      member do
        get :ubl_checkout_payment
      end
    end
  end

  # These routes are for all payment methods
  match '/payment/*method/return', to: 'offsite_payments_status#return', as: :return, via: [:get, :post]
  match '/payment/*method/notify', to: 'offsite_payments_status#notification', as: :notify, via: [:get, :post]
  match '/payment/:payment_id/status', to: 'offsite_payments_status#status_update', as: :payment_status, via: :get

  match '/payment/:payment_id/qrcode', to: 'checkout#payment_qrcode', as: :payment_qrcode, via: :get
  match '/payment/wxpay/jsapi/:payment_id', to: 'checkout#wcpay_code', as: :wcpay_code, via: :get
end

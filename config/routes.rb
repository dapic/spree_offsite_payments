Spree::Core::Engine.routes.draw do
  resources :orders do
    resource :checkout, :controller => 'checkout' do
      member do
        get :alipay_checkout_payment
        get :tenpay_checkout_payment
      end
    end
  end

  # Add your extension routes here
  match '/alipay_checkout/done', to: 'checkout#alipay_done', as: :alipay_done, via: [:get, :post]
  match '/alipay_checkout/notify',to: 'checkout#alipay_notify', as: :alipay_notify, via: [:get, :post]

  match '/tenpay_checkout/done', to: 'checkout#tenpay_done', as: :tenpay_done, via: [:get, :post]
  match '/tenpay_checkout/notify',to: 'checkout#tenpay_notify', as: :tenpay_notify, via: [:get, :post]
end

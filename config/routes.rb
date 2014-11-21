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
  match '/payment/*method/return', to: 'offsite_payments_status#return', as: :return, via: [:get, :post]
  match '/payment/*method/notify', to: 'offsite_payments_status#notification', as: :notify, via: [:get, :post]
end

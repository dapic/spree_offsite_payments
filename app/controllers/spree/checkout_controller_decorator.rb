#encoding: utf-8
require 'offsite_payments'

module Spree
  CheckoutController.class_eval do
    include ::OffsitePayments::Integrations::Ubl
    include ::OffsitePayments::Integrations::EasyPaisa
    
    skip_before_action :load_user, only: [:offsite]
    prepend_before_action :load_offsite_order, only: [:offsite]
    
    def load_offsite_order
      @spree_current_user = @current_api_user = Spree.user_class.find_by(spree_api_key: params[:token])
      if @current_api_user
        sign_in @current_api_user
        @current_order = @current_api_user.orders.friendly.find(params[:order_id])      
      end
    end
    
    private :load_offsite_order
    
    #/shops/chain-mart/checkout/offsite?payment_method=ubl #&order=ordernumber
    def offsite
      @payment_method = PaymentMethod.find(params[:payment_method])
      @caller="mobile"
      unless @order.next_step_complete?
        render nothing: true
      end
      @payment = @order.payments.processing.find_or_create_by(amount: @order.outstanding_balance, payment_method: @payment_method)
      case @payment_method.class.name
      when Spree::BillingIntegration::UBL.name
        render :ubl_checkout_payment
      when Spree::BillingIntegration::EasyPaisa.name
        render :easy_paisa_checkout_payment
      end
    end

  end

end

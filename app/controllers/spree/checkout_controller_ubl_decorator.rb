#encoding: utf-8
require 'offsite_payments'

module Spree
  CheckoutController.class_eval do
    include ::OffsitePayments::Integrations::Ubl
    before_action :ubl_checkout_hook, only: [:update]
    
    private
    def ubl_checkout_hook
      @caller="web"
      #support step confirmation 
      return unless ( @order.next_step_complete? && is_ubl? )
      @payment = @order.payments.processing.find_or_create_by(amount: @order.outstanding_balance, payment_method: @payment_method)
      render :ubl_checkout_payment      
    end

    def is_ubl?
      @payment_method = PaymentMethod.find(params[:order][:payments_attributes].first[:payment_method_id]) if params[:order] && params[:order][:payments_attributes]
      Spree::BillingIntegration::UBL == @payment_method.class rescue false
    end

  end

end

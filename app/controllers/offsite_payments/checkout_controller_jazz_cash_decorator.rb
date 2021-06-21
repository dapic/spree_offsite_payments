#encoding: utf-8
# require 'offsite_payments'
module OffsitePayments
  module CheckoutControllerJazzCashDecorator
    def self.prepended(base)
      base.include ::OffsitePayments::Integrations::JazzCash
      base.before_action :jazz_cash_checkout_hook, only: [:update]
    end
    
    private
    def jazz_cash_checkout_hook
      @caller = 'web'
      #support step confirmation
      return unless ( @order.next_step_complete? && is_jazz_cash? )
      @payment = @order.payments.processing.find_or_create_by(amount: @order.outstanding_balance, payment_method: @payment_method)
      render :jazz_cash_checkout_payment
    end

    def is_jazz_cash?
      @payment_method = Spree::PaymentMethod.find(params[:order][:payments_attributes].first[:payment_method_id]) if params[:order] && params[:order][:payments_attributes]
      Spree::BillingIntegration::JazzCash == @payment_method.class rescue false
    end
    
    Spree::CheckoutController.prepend self
  end
end
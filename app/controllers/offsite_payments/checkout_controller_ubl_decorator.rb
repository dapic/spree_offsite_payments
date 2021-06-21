module OffsitePayments
  module CheckoutControllerUblDecorator
    def self.prepended(base)
      base.include ::OffsitePayments::Integrations::Ubl
      base.before_action :ubl_checkout_hook, only: [:update]
    end

    private
    def ubl_checkout_hook
      @caller = 'web'
      #support step confirmation 
      return unless ( @order.next_step_complete? && is_ubl? )
      @payment = @order.payments.processing.find_or_create_by(amount: @order.outstanding_balance, payment_method: @payment_method)
      render :ubl_checkout_payment      
    end

    def is_ubl?
      @payment_method = Spree::PaymentMethod.find(params[:order][:payments_attributes].first[:payment_method_id]) if params[:order] && params[:order][:payments_attributes]
      Spree::BillingIntegration::Ubl == @payment_method.class rescue false
    end

    Spree::CheckoutController.prepend self
  end
end

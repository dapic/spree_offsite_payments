module OffsitePayments
  module CheckoutControllerEasyPaisaDecorator
    def self.prepended(base)
      base.include ::OffsitePayments::Integrations::EasyPaisa
      base.before_action :easy_paisa_checkout_hook, only: [:update]  
    end
    
    private
    def easy_paisa_checkout_hook
      @caller = 'web'
      #support step confirmation 
      return unless ( @order.next_step_complete? && is_easy_paisa? )
      @payment = @order.payments.processing.find_or_create_by(amount: @order.outstanding_balance, payment_method: @payment_method)
      render :easy_paisa_checkout_payment      
    end

    def is_easy_paisa?
      @payment_method = Spree::PaymentMethod.find(params[:order][:payments_attributes].first[:payment_method_id]) if params[:order] && params[:order][:payments_attributes]
      Spree::BillingIntegration::EasyPaisa == @payment_method.class rescue false
    end

    Spree::CheckoutController.prepend self
  end
end

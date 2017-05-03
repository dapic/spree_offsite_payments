#encoding: utf-8
require 'offsite_payments'

module Spree
  CheckoutController.class_eval do
    include ::OffsitePayments::Integrations::Ubl
    before_action :ubl_checkout_hook, only: [:update]
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
#    skip_before_action :ensure_order_not_completed, only: [:offsite]
#    skip_before_action :ensure_checkout_allowed, only: [:offsite]
#    skip_before_action :ensure_sufficient_stock_lines, only: [:offsite]
#    skip_before_action :ensure_valid_state, only: [:offsite]
#    skip_before_action :setup_for_current_state, only: [:offsite]
    
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
      end
    end
    
    private
    def ubl_checkout_hook
      @caller="web"
      #support step confirmation 
      return unless ( @order.next_step_complete? && is_ubl? )
      @payment = @order.payments.processing.find_or_create_by(amount: @order.outstanding_balance, payment_method: @payment_method)
      render :ubl_checkout_payment      
    end

    def is_ubl?
      @payment_method = PaymentMethod.find(params[:order][:payments_attributes].first[:payment_method_id])
      Spree::BillingIntegration::UBL == @payment_method.class rescue false
    end

  end

end

#encoding: utf-8
require 'offsite_payments'

module Spree
  CheckoutController.class_eval do
    include ::OffsitePayments::Integrations::Ubl
    include ::OffsitePayments::Integrations::EasyPaisa
    
    prepend_before_action :load_offsite_order, only: [:offsite]
    skip_before_action :ensure_order_not_completed, only: [:offsite]
    before_action :ensure_order_not_paid, only: [:offsite]
    
    def ensure_order_not_paid
      redirect_to spree.cart_path, error: "Payment is already completed for order: #{@order.number}" if @order.paid?
    end
    private :ensure_order_not_paid
    
    def load_offsite_order
      if try_spree_current_user
        @current_order = Spree::Order.find_by!(number: params[:order_id])
        authorize! :read, @current_order
      else
        #Currently call for offsite payments in mobiles uses token in browser to authenticate user
        @current_spree_user = @current_api_user = Spree.user_class.find_by(spree_api_key: params[:token])
        if @current_spree_user
          sign_in @current_spree_user
          @current_order = Spree::Order.accessible_by(current_ability).find_by!(number: params[:order_id])
        end
      end
    end    
    private :load_offsite_order
    
    #/shops/chain-mart/checkout/offsite?payment_method=ubl #&order=ordernumber
    def offsite
      #byebug
      @payment_method = PaymentMethod.find(params[:payment_method])
      @caller = 'mobile'
      #not requiring next_step_complete anymore as ensure_order_not_paid has been added
#      unless @order.next_step_complete?
#        render body: nil
#        return
#      end
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

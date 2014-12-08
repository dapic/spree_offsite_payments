#encoding: utf-8
module Spree
  CheckoutController.class_eval do
    before_filter :wxpay_checkout_hook, :only => [:update]
    
    # this is called when user choose "wxpay" and clicks "next" or sth equivalent
    # which would go to the "update" action in checkout controller
    def wxpay_checkout_hook
      #TODO support step confirmation 
      return unless params['state'] == 'payment' # @order.next_step_complete?
      #return unless @order.next_step_complete?
      payment_method = PaymentMethod.find(params[:order][:payments_attributes].first[:payment_method_id])
      Rails.logger.debug ("found #{payment_method.name}")
      return unless Spree::BillingIntegration::Wxpay == payment_method.class
      @payment = @order.payments.processing.find_or_create_by(amount: @order.outstanding_balance, payment_method: payment_method)
      #@payment_url = @payment.payment_url || get_payment_url(@payment).tap{|url| @payment.payment_url = url; @payment.save!}
      begin
        Spree::OffsitePayments::Wxpay::Manager.new().get_payment_url(@payment, request )
      rescue Spree::OffsitePayments::Wxpay::BusinessError => e
        flash[:warn] = e.message
        redirect_to order_url(@order) and return
      rescue ::OffsitePayments::Integrations::Wxpay::CommunicationError,
              ::OffsitePayments::Integrations::Wxpay::CredentialMismatchError,
              ::OffsitePayments::Integrations::Wxpay::UnVerifiableResponseError => e
        Rails.logger.error(e.message)
        flash[:error] = Spree.t(:comm_error)
      end
      render :edit
    end

    def payment_qrcode
      @payment_url = Payment.find(params[:payment_id]).payment_url
      respond_to do |format|
        format.html { render qrcode: @payment_url }
        format.svg  { render :qrcode => @payment_url, :level => :l, :unit => 10 }
        format.png  { render :qrcode => @payment_url }
        format.gif  { render :qrcode => @payment_url }
        format.jpeg { render :qrcode => @payment_url }
      end
    end

  end
end

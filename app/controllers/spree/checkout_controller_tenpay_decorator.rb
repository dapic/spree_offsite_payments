#encoding: utf-8
module Spree
  CheckoutController.class_eval do
    before_filter :tenpay_checkout_hook, :only => [:update]
    
    # this is called when user choose "tenpay" and clicks "next" or sth equivalent
    # which would go to the "update" action in checkout controller
    def tenpay_checkout_hook
      #TODO support step confirmation 
      return unless params['state'] == 'payment' # @order.next_step_complete?
      #return unless @order.next_step_complete?
      payment_method = PaymentMethod.find(params[:order][:payments_attributes].first[:payment_method_id])
      Rails.logger.debug ("found #{payment_method.name}")
      return unless Spree::BillingIntegration::Tenpay == payment_method.class
      #return unless (params[:state] == "payment") && params[:order][:payments_attributes]

      # new logic --stanley
      # if already exists a tenpay payment for this order, use it
      # otherwise create it
      # then do redirect   
      payment = @order.payments.processing.find_or_create_by(amount: @order.outstanding_balance, payment_method: payment_method)
      redirect_to tenpay_full_service_url(payment, payment_method)
    end

    def tenpay_full_service_url( payment, payment_method )
      order = payment.order
      helper = ::OffsitePayments::Integrations::Tenpay::Helper.new(create_out_trade_no(payment), payment_method.preferred_partner, key: payment_method.preferred_partner_key)
      helper.total_fee (( order.total * 100).to_i)
      helper.body "#{order.products.collect(&:name).join(';').to_s}" #String(400) 
      helper.return_url return_url(method: :tenpay)
      helper.notify_url notify_url(method: :tenpay)
      helper.charset "utf-8"
      helper.payment_type 1
      helper.remote_ip request.remote_ip
      helper.sign
      url = URI.parse(::OffsitePayments::Integrations::Tenpay.service_url)
      url.query = ( Rack::Utils.parse_nested_query(url.query).merge(helper.form_fields) ).to_query
      Rails.logger.debug "full_service_url to be encoded is #{url.to_s}"
      url.to_s
    end

    private
    def create_out_trade_no( payment )
      "#{payment.order.number}_#{payment.identifier}"
    end

  end
end

#encoding: utf-8
module Spree
  CheckoutController.class_eval do
    before_action :alipay_checkout_hook, :only => [:update]

    def alipay_checkout_hook
      #TODO support step confirmation 
      return unless ( @order.next_step_complete? && is_alipay? )
      @payment = @order.payments.processing.find_or_create_by(amount: @order.outstanding_balance, payment_method: @payment_method)
      redirect_to alipay_full_service_url and return
    end

    private

    def is_alipay?
      @payment_method = PaymentMethod.find(params[:order][:payments_attributes].first[:payment_method_id])
      Spree::BillingIntegration::Alipay == @payment_method.class rescue false
    end
      # all payments through alipay has these states:
      #  * checkout -- when first created, not used
      #  * pending  -- not used
      #  * processing -- when redirect is made
      #  * completed -- when we receive return/notify from Alipay and _confirmed_ it
      #  * void  -- when price changed and this is no longer a valid payment, before "processing" #or when we did not receive return/notify in 24 hours
      #  TODO: we should stop price from being changed after "processing"
      #  * failed --  when we receive return/notify saying the payment failed, or _confirmation_ failed

    # TODO: we the code only supports "create_direct_pay_by_user" as of now (2014-11-14)
    def alipay_full_service_url
      helper = ::OffsitePayments::Integrations::Alipay::Helper.new(Spree::OffsitePayments.create_out_trade_no(@payment), @payment_method.preferred_partner, key: @payment_method.preferred_sign)
      helper.total_fee @order.total
      helper.service ::OffsitePayments::Integrations::Alipay::Helper::CREATE_DIRECT_PAY_BY_USER
      helper.seller :email => @payment_method.preferred_email
      helper.return_url return_url(method: :alipay)
      helper.notify_url notify_url(method: :alipay)
      helper.body @order.products.collect(&:name).to_s #String(400) 
      helper.charset "utf-8"
      helper.payment_type 1
      helper.subject "订单编号:#{@order.number}"
      helper.sign
      url = URI.parse(::OffsitePayments::Integrations::Alipay.service_url)
      url.query = (Rack::Utils.parse_nested_query(url.query).merge(helper.form_fields)).to_query
      url.to_s
    end
  end

end

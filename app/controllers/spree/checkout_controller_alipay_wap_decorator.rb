#encoding: utf-8
module Spree
  CheckoutController.class_eval do
    before_action :alipay_wap_checkout_hook, :only => [:update]

    # this is called when user choose "alipay_wap" and clicks "next" or sth equivalent
    # which would go to the "update" action in checkout controller
    def alipay_wap_checkout_hook
      #TODO: support step confirmation
      return unless params['state'] == 'payment' && is_alipay_wap? # && request.user_agent.match(/Mobile/)
      @payment = @order.payments.processing.find_or_create_by(amount: @order.outstanding_balance, payment_method: @payment_method)
      redirect_to alipay_wap_auth_and_execute_url() and return
    end

    private

    def is_alipay_wap?
      @payment_method = PaymentMethod.find(params[:order][:payments_attributes].first[:payment_method_id])
      Spree::BillingIntegration::AlipayWap == @payment_method.class rescue false
    end

    def alipay_wap_auth_and_execute_url
      @payment_method.provider_class.logger = Rails.logger
      ::OffsitePayments::Integrations::AlipayWap.credentials = {
          key: @payment_method.preferred_key,
          pid: @payment_method.preferred_partner,
          seller: { email: @payment_method.preferred_email }
      }
      Rails.logger.debug("alipay_wap payload #{assemble_payload}")
      Rails.logger.debug("payment method #{@payment_method}")
      request_token = @payment_method.provider_class::CreateDirectHelper.new(assemble_payload).process.request_token
      Rails.logger.debug("got request token #{request_token}")
      @payment_method.provider_class::AuthAndExecuteHelper.new(request_token: request_token).request_url.tap{|url|Rails.logger.debug("alipay auth_and_execute url is #{url}")}
    end

    def assemble_payload
      {
          subject:             "订单编号:#{@order.number}",
          out_trade_no:        Spree::OffsitePayments.create_out_trade_no(@payment),
          total_fee:           @order.total,
          seller_account_name: @payment_method.preferred_email,
          call_back_url:       return_url(host: request.host, method: :alipay_wap),
          notify_url:          notify_url(host: request.host, method: :alipay_wap),
          out_user:            @order.user_id,
          merchant_url:        request.host,
          pay_expire:          3600,
      }
    end
  end
end

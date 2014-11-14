#encoding: utf-8
module Spree
  module AlipayDecorator

    # triggered when user is redirected back to our website after completing payment on the 3rd party website
    def alipay_done
      #@payment_method = Spree::BillingIntegration::Alipay.new
      #payment_return = OffsitePayments::Integrations::Alipay::Return.new(request.query_string, @payment_method.preferred_sign)
      #unless payment_return.acknowledge
      #alipay_retrieve_order(payment_return.order)
      if @return.is_payment_complete?
        #TODO: The following logic need to be revised
        #FIXME: what if the amount paid is not enough for the whole order?
        @order.payments.where(:state => ['processing', 'pending', 'checkout']).first.complete!
        @order.state='complete'
        @order.finalize!
        session[:order_id] = nil
        redirect_to completion_route
      else
        #TODO: added this to tx log too
        redirect_to edit_order_checkout_url(@order, :state => "payment")
      end
    end
    
    # triggered when Alipay sends a notification request unbeknownst to the user, from Alipay server to our server
    def alipay_notify
      if valid_alipay_notification?(@notification,@order.payments.first.payment_method.preferred_partner)
        if @notification.is_payment_complete?
          @order.payment.first.complete!
        else
          @order.payment.first.failure!
        end
        render text: "success" 
      else
        render text: "fail" 
      end
    rescue
      render text: "fail"
    end
    
    def alipay_checkout_hook
      #TODO support step confirmation 
      return unless @order.next_step_complete?
      return unless params[:order][:payments_attributes].present?
      if @order.update_attributes(alipay_payment_params) #it would create payments
        if params[:order][:coupon_code] and !params[:order][:coupon_code].blank? and @order.coupon_code.present?
          fire_event('spree.checkout.coupon_code_added', :coupon_code => @order.coupon_code)
        end
      end
      if alipay_pay_by_billing_integration?
      #Rails.logger.debug "--->before alipay_handle_billing_integration"
        alipay_handle_billing_integration
      end
    end

    #This overrides the method in CheckoutController
    def wrong_load_order_with_lock

      Rails.logger.debug "#{__LINE__}:#{request.path_parameters[:action]}"
      
      #alipay_load_order
      super unless @order.present? 
    rescue RuntimeError => e
      Rails.logger.error("alipay_load_order failed since: #{e.message}")
      render text: 'fail'
    end

    # This is done in the default checkout_controller filter chain
    def alipay_load_order
      raise "'out_trade_no' requird to load the order" unless params.key?('out_trade_no')
      order_number = parse_alipay_out_trade_no(params['out_trade_no'])[:payment_order_number]
      @order  = Order.find_by_number(order_number) #if request.referer=~/alipay.com/
      unless @order.present?
        raise RuntimeError, "Could not find order #{order_number}"
      end
    end
    
  private

    def ensure_valid_alipay_request
      #@payment_method = Spree::BillingIntegration::Alipay.new()
      @payment_method = Spree::PaymentMethod.find_by(type: Spree::BillingIntegration::Alipay)
      Rails.logger.debug "key is #{@payment_method.inspect}"
      Rails.logger.debug "key is #{@payment_method.preferred_sign}"
      case request.path_parameters[:action]
      when 'alipay_notify'
        begin
          @notification = OffsitePayments::Integrations::Alipay.notification(request.raw_post, key: @payment_method.preferred_sign)
          @notification.acknowledge
        rescue RuntimeError => e
          Rails.logger.warn(e)
          render text: 'failure'
        end
      when 'alipay_done'
        begin
        @return = OffsitePayments::Integrations::Alipay.return(request.query_string, key: @payment_method.preferred_sign) 
        #@return.acknowledge
        rescue RuntimeError => e
          Rails.logger.warn(e)
          flash[:error] = Spree.t('illegal_sign_in_request')
          redirect_to spree.root_path
        end
      else
        raise RuntimeError, "Configuration error. It shouldn't get here"
      end
    end

    def parse_alipay_out_trade_no(out_trade_no)
      case 
      when 18 == out_trade_no.length
        return { payment_order_number: out_trade_no[0..-9], payment_identifier: out_trade_no[-8,8] }
      when 10 == out_trade_no.length
        return { payment_order_number: out_trade_no, payment_identifier: ''}
      else  
        Rails.logger.warn "Suspecious out_trade_no #{out_trade_no}"
        return { payment_order_number: out_trade_no, payment_identifier: ''}
      end
    end
    
    def valid_alipay_notification?(notification, account)
      url = "https://mapi.alipay.com/gateway.do?service=notify_verify"
      result = HTTParty.get(url, query: {partner: account, notify_id: notification.notify_id}).body
      result == 'true'
    end
    
    # TODO: we the code only supports "create_direct_pay_by_user" as of now (2014-11-14)
    def alipay_full_service_url( order, alipay)
      #Rails.logger.debug "alipay gateway is configured to be #{alipay.inspect}"
      raise ArgumentError, 'require Spree::BillingIntegration::Alipay' unless alipay.is_a? Spree::BillingIntegration::Alipay
      #url = OffsitePayments::Integrations::Alipay.service_url+'?'
      helper = OffsitePayments::Integrations::Alipay::Helper.new(order.number, alipay.preferred_partner, key: alipay.preferred_sign)
      #Rails.logger.debug "helper is #{helper.inspect}"

      if alipay.preferred_using_direct_pay_service
        helper.total_fee order.total
        helper.service OffsitePayments::Integrations::Alipay::Helper::CREATE_DIRECT_PAY_BY_USER
      else
        helper.price order.item_total
        helper.quantity 1
        helper.logistics :type=> 'EXPRESS', :fee=>order.adjustment_total, :payment=>'BUYER_PAY' 
        helper.service OffsitePayments::Integrations::Alipay::Helper::TRADE_CREATE_BY_BUYER
      end
      helper.seller :email => alipay.preferred_email
      #url_for is controller instance method, so we have to keep this method in controller instead of model
      #Rails.logger.debug "helper is #{helper.inspect}"
      helper.notify_url url_for(:only_path => false, :action => 'alipay_notify')
      helper.return_url url_for(:only_path => false, :action => 'alipay_done')
      helper.body order.products.collect(&:name).to_s #String(400) 
      helper.charset "utf-8"
      helper.payment_type 1
      helper.subject "订单编号:#{order.number}"
      Rails.logger.debug "order--- #{order.inspect}"
      Rails.logger.debug "signing--- #{helper.inspect}"
      helper.sign
      url = URI.parse(OffsitePayments::Integrations::Alipay.service_url)
      #Rails.logger.debug "query from url #{url.query}"
      #Rails.logger.debug "query from url parsed #{Rack::Utils.parse_nested_query(url.query).inspect}"
      #Rails.logger.debug "helper fields #{helper.form_fields.to_query}"
      url.query = ( Rack::Utils.parse_nested_query(url.query).merge(helper.form_fields) ).to_query
      #Rails.logger.debug "full_service_url to be encoded is #{url.to_s}"
      url.to_s
    end

    def alipay_pay_by_billing_integration?
      #Rails.logger.debug "current orderrrr: #{@order.inspect}"
      if @order.next_step_complete?
        #Rails.logger.debug "pending paymentssss: #{@order.pending_payments.inspect}"
        if @order.pending_payments.first.payment_method.kind_of? BillingIntegration 
          return true
        end
      end
      return false
    end
    
    # handle all supported billing_integration
    def alipay_handle_billing_integration      
      payment_method = @order.pending_payments.first.payment_method
      if payment_method.kind_of?(BillingIntegration::Alipay)
        redirect_to alipay_full_service_url(@order, payment_method)
      end
    end
    
    #patch spree_auth_devise/checkout_controller_decorator
    def alipay_skip_state_validation?
      %w(registration update_registration).include?(params[:state])
    end

    def alipay_payment_params
      params.require(:order).permit(:authenticity_token, {:payments_attributes => [ :payment_method_id]} , :coupon_code)
    end
  end

  CheckoutController.send(:prepend, AlipayDecorator)
  CheckoutController.class_eval do
    SKIP_FILTERS_FOR = [:alipay_notify, :alipay_done]
    before_action :alipay_checkout_hook, :only => [:update]
    skip_before_action :verify_authenticity_token, only: SKIP_FILTERS_FOR 
    # these two actions is from spree_auth_devise
    skip_before_action :check_registration, :check_authorization, only: SKIP_FILTERS_FOR 
    prepend_before_action :ensure_valid_alipay_request, :alipay_load_order, only: SKIP_FILTERS_FOR 
  end

end

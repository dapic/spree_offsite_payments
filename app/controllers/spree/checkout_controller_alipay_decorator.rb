#encoding: utf-8
module Spree
  module AlipayDecorator

    # triggered when user is redirected back to our website after completing payment on the 3rd party website
    def alipay_done
      #@payment_method = Spree::BillingIntegration::Alipay.new
      #payment_return = OffsitePayments::Integrations::Alipay::Return.new(request.query_string, @payment_method.preferred_sign)
      #unless payment_return.acknowledge
      #alipay_retrieve_order(payment_return.order)
      Rails.logger.debug("payment return is #{@return.inspect}")
      if @order.completed?  
        flash.notice = Spree.t(:order_processed_already)
        redirect_to completion_route
      elsif @return.is_payment_complete?
        # TODO: verify this!!!
        # @payment should have already been set. if it's nil, then we find it here
        @payment ||= @order.payments.where(:state => ['processing', 'pending', 'checkout'], payment_method: @payment_method ).first
        unless @payment.amount == @return.amount
          Rails.logger.warn("payment return shows different amount than was recorded in the payment. it should be #{@payment.amount} but is actually #{@return.amount}") 
          @payment.amount = @return.amount
        end
        #@payment.record_response(@return) #this creates log entries
        @payment.log_entries.create!(:details => @return.to_yaml)
        @payment.complete!
        #TODO: The following logic need to be revised
        #FIXME: what if the amount paid is not enough for the whole order?
        #@order.payments.where(:state => ['processing', 'pending', 'checkout']).first.complete!
        #@order.state='complete'
        #@order.complete!
        @order.update_attributes(:state => "complete", :completed_at => Time.now)
        @order.finalize!
        session[:order_id] = nil
        flash.notice = Spree.t(:order_processed_successfully)
        Rails.logger.debug("#{@order.inspect}")
        redirect_to completion_route
      else
        #TODO: added this to tx log too
        Rails.logger.debug("checkout #{order.number}")
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
      #return unless params[:order][:payments_attributes].present?

      # all payments through alipay has these states:
      #  * checkout -- when first created, not used
      #  * pending  -- not used
      #  * processing -- when redirect is made
      #  * completed -- when we receive return/notify from Alipay and _confirmed_ it
      #  * void  -- when price changed and this is no longer a valid payment, before "processing" #or when we did not receive return/notify in 24 hours
      #  TODO: we should stop price from being changed after "processing"
      #  * failed --  when we receive return/notify saying the payment failed, or _confirmation_ failed
      #payment_method = PaymentMethod.find(params[:payment_method_id])
      payment_method = PaymentMethod.find_by(type: Spree::BillingIntegration::Alipay)
      payment = @order.payments.processing.find_or_create_by(amount: @order.outstanding_balance, payment_method: payment_method)
      redirect_to alipay_full_service_url(@order, payment_method, identifier: payment.identifier)
      #if @order.update_attributes(alipay_payment_params) #it would create payments
      #  if params[:order][:coupon_code] and !params[:order][:coupon_code].blank? and @order.coupon_code.present?
      #    fire_event('spree.checkout.coupon_code_added', :coupon_code => @order.coupon_code)
      #  end
      #end
#      payment = @order.payments.where(state: :pending, payment_method: payment_method ).try(:first) ||
#        @order.payments.create( amount: @order.total,
#                                payment_method: payment_method)
#      # update it here because the total could have changed since this payment is created
#      payment.amount = @order.total
#      payment.pend!
#
#        unless @order.payments.where(:source_type => 'Spree::BillingIntegration::Alipay').present?
#          payment_method = PaymentMethod.find(params[:payment_method_id])
#          skrill_transaction = SkrillTransaction.new
#
#          payment = @order.payments.create({:amount => @order.total,
#                                            :source => skrill_transaction,
#                                            :payment_method => payment_method},
#                                            :without_protection => true)
#          payment.started_processing!
#          payment.pend!
#        end
#
#        if alipay_pay_by_billing_integration?
#          #Rails.logger.debug "--->before alipay_handle_billing_integration"
#          alipay_handle_billing_integration
#        end
    end

    private

    # This is put at the front of the filter chain for "return" and "notification" requests
    # Loading order is after this step so we have to get the payment_method by class name, instead of
    # getting it from the order
    def ensure_valid_alipay_request
      #@payment_method = Spree::BillingIntegration::Alipay.new()
      @payment_method = Spree::PaymentMethod.find_by(type: Spree::BillingIntegration::Alipay)
      #Rails.logger.debug "key is #{@payment_method.inspect}"
      Rails.logger.debug "#{__LINE__} key is #{@payment_method.preferred_sign}"
      case request.path_parameters[:action]
      when 'alipay_notify'
        begin
          @notification = OffsitePayments::Integrations::Alipay.notification(request.raw_post, key: @payment_method.preferred_sign)
          @notification.acknowledge
        rescue RuntimeError, OffsitePayments::ActionViewHelperError => e
          Rails.logger.warn("#{e} in request: #{request.env['REQUEST_URI']}")
          render text: 'failure'
        end
      when 'alipay_done'
        begin
          @return = OffsitePayments::Integrations::Alipay.return(request.query_string, key: @payment_method.preferred_sign) 
          @return.acknowledge
        rescue RuntimeError, OffsitePayments::ActionViewHelperError => e
          Rails.logger.warn("#{e} in request: #{request.env['REQUEST_URI']}")
          flash[:error] = Spree.t('invalid_alipay_request')
          redirect_to spree.root_path
        end
      else
        raise RuntimeError, "Configuration error. It shouldn't get here"
      end
    end

    # This is done in the default checkout_controller filter chain
    def alipay_load_order
      Rails.logger.debug "#{__LINE__} alipay_load_order called "
      raise "'out_trade_no' requird to load the order" unless params.key?('out_trade_no')
      #order_number = parse_alipay_out_trade_no(params['out_trade_no'])[:payment_order_number]
      order_number, payment_identifier = parse_alipay_out_trade_no(params['out_trade_no'])
      @order  = Order.find_by_number(order_number) #if request.referer=~/alipay.com/
      @payment = Payment.find_by(identifier: payment_identifier)
      #@current_order = @order
      unless @order.present?
        raise RuntimeError, "Could not find order #{order_number}"
      end
      Rails.logger.debug "#{__LINE__} alipay_load_order called and order is found #{@order.inspect}"
    end

    def parse_alipay_out_trade_no(out_trade_no)
      return out_trade_no.split('_')
#      case 
#      when 18 == out_trade_no.length
#        return { payment_order_number: out_trade_no[0..-9], payment_identifier: out_trade_no[-8,8] }
#      when 10 == out_trade_no.length
#        return { payment_order_number: out_trade_no, payment_identifier: ''}
#      else  
#        Rails.logger.warn "Suspecious out_trade_no #{out_trade_no}"
#        return { payment_order_number: out_trade_no, payment_identifier: ''}
#      end
    end

    def valid_alipay_notification?(notification, account)
      url = "https://mapi.alipay.com/gateway.do?service=notify_verify"
      result = HTTParty.get(url, query: {partner: account, notify_id: notification.notify_id}).body
      result == 'true'
    end

    # TODO: we the code only supports "create_direct_pay_by_user" as of now (2014-11-14)
    def alipay_full_service_url( order, alipay, identifier: nil)
      #Rails.logger.debug "alipay gateway is configured to be #{alipay.inspect}"
      raise ArgumentError, 'require Spree::BillingIntegration::Alipay' unless alipay.is_a? Spree::BillingIntegration::Alipay
      #url = OffsitePayments::Integrations::Alipay.service_url+'?'
      helper = OffsitePayments::Integrations::Alipay::Helper.new([order.number, identifier].join('_'), alipay.preferred_partner, key: alipay.preferred_sign)
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
      payment_method = PaymentMethod.find(params[:payment_method_id])
      payment = @order.pending_payments.first
      #payment_method = @order.pending_payments.first.payment_method
      if payment.payment_method.kind_of?(BillingIntegration::Alipay)
        #pay
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
    append_before_action :alipay_checkout_hook, :only => [:update]
    skip_before_action :verify_authenticity_token, only: SKIP_FILTERS_FOR 
    # these two actions is from spree_auth_devise
    skip_before_action :check_registration, :check_authorization, only: SKIP_FILTERS_FOR 
    skip_before_action :load_order_with_lock, :ensure_checkout_allowed, :ensure_order_not_completed, only: SKIP_FILTERS_FOR 
    prepend_before_action :ensure_valid_alipay_request, :alipay_load_order, only: SKIP_FILTERS_FOR 
  end

end

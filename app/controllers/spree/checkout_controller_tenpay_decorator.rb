#encoding: utf-8
module Spree
  CheckoutController.class_eval do
    cattr_accessor :tenpay_skip_payment_methods
    self.tenpay_skip_payment_methods = [:tenpay_notify, :tenpay_done]#, :tenpay_notify, :tenpay_done
    before_filter :tenpay_checkout_hook, :only => [:update]
    #invoid WARNING: Can't verify CSRF token authenticity
    skip_before_filter :verify_authenticity_token, :only => self.tenpay_skip_payment_methods
    # these two filters is from spree_auth_devise
    skip_before_filter :check_registration, :check_authorization, :only=> self.tenpay_skip_payment_methods

    # this is called when tenpay server/website redirects the user's browser back to our site
    def tenpay_done
      payment_return = OffsitePayments::Integrations::Tenpay::Return.new(request.query_string)
      #TODO check payment_return.success
      tenpay_retrieve_order(payment_return.order)
#      Rails.logger.info "payment_return=#{payment_return.inspect}"
      if @order.present?
        @order.payments.where(:state => ['processing', 'pending', 'checkout']).first.complete!
        @order.state='complete'
        @order.finalize!
        session[:order_id] = nil
        redirect_to completion_route
      else
        #Strange, Failed trying to complete pending payment!
        redirect_to edit_order_checkout_url(@order, :state => "payment")
      end
    end

    # this is called when tenpay server posts a notification to the "notify_url"
    def tenpay_notify
      # create the notify object
      notification = OffsitePayments::Integrations::Tenpay::Notification.new(request.raw_post)
      # check that the notify message is authentic
      render text: "fail" unless notification.authenticated?
      # if authentic, process the notify message
      process_payment_notification(notification)
      # if process successful, return "success!"
      render text: "success!"
      # else, return "fail"
      #tenpay_retrieve_order(notification.out_trade_no)
      #if @order.present? and notification.acknowledge() and valid_tenpay_notification?(notification,@order.payments.first.payment_method.preferred_partner)
      #  if notification.complete?
      #    @order.payment.first.complete!
      #  else
      #    @order.payment.first.failure!
      #  end
      #  render text: "success" 
      #else
      #  render text: "fail" 
      #end
    rescue RuntimeException => e
      log.error(e.message)
      render text: "fail"
    end

    def process_payment_notification(notification)
      order_id, identifier = parse_out_trade_no(notification.out_trade_no)
      tenpay_retrieve_order(order_id)
      raise RuntimeException("no order found with #{notification.out_trade_no}") unless @order.present? 
      matching_payment_list = @order.payments.where(:source_type => 'Spree::BillingIntegration::Tenpay', identifier: identifier )

      case matching_payment_list.length
      when 0
        # create new payment from notification
      when 1
         this_payment = matching_payment_list.first
      else 
         log.warn "found more than one payments with identifier #{identifier}" if cur_pay.length > 1
         this_payment = matching_payment_list.first
      end

      unless this_payment.completed? 
        this_payment.started_processing!
        if notification.complete?
          this_payment.complete!
        else
          this_payment.failure!
        end
      end
    end

    def parse_out_trade_no(out_trade_no)
      return { payment_order_id: out_trade_no[0..-9], payment_identifier: out_trade_no[-8,8] }
    end
  
    #https://github.com/flyerhzm/donatecn
    #demo for activemerchant_patch_for_china
    #since tenpay_full_service_url is working, it is only for debug for now.
    def tenpay_checkout_payment
      payment_method =  PaymentMethod.find(params[:payment_method_id])
      #Rails.logger.debug "@payment_method=#{@payment_method.inspect}"       
      Rails.logger.debug "tenpay_full_service_url: "+tenpay_full_service_url(@order, payment_method)
      # notice that load_order would call before_payment, if 'http==put' and 'order.state == payment', the payments will be deleted. 
      # so we have to create payment again
      @order.payments.create(:amount => @order.total, :payment_method_id => payment_method.id)
      #redirect_to_tenpay_gateway(:subject => "donatecn", :body => "donatecn", :amount => @donate.amount, :out_trade_no => "123", :notify_url => pay_fu.tenpay_transactions_notify_url)
    end

    private
    
    def load_order_with_lock_with_tenpay_return      
      if request.referer=~/tenpay.com/
        payment_return = OffsitePayments::Integrations::Tenpay::Return.new(request.query_string)
        @current_order = tenpay_retrieve_order(payment_return.order)                  
      end      
      load_order_with_lock_without_tenpay_return
    end
    
    #because of PR below, load_order is renamed to load_order_with_lock
    #https://github.com/spree/spree/commit/45eabed81e444af3ff1cf49891f64c85fdd8d546
    alias_method_chain :load_order_with_lock, :tenpay_return
     
    # this is called when user choose "tenpay" and clicks "next" or sth equivalent
    # which would go to the "update" action in checkout controller
    def tenpay_checkout_hook
      #logger.debug "----before tenpay_checkout_hook"    
      #all_filters = self.class._process_action_callbacks
      #all_filters = all_filters.select{|f| f.kind == :before}
      #logger.debug "all before filers:"+all_filters.map(&:filter).inspect 
      #TODO support step confirmation 
      #Rails.logger.debug "--->tenpay_checkout_hooking?"

      #return unless @order.next_step_complete?
      #return unless params[:order][:payments_attributes].present?
      return unless (params[:state] == "payment") && params[:order][:payments_attributes]

      # new logic --stanley
      # if already exists a tenpay payment for this order, use it
      # otherwise create it
      # then do redirect   
      payment_method = PaymentMethod.find(params[:payment_method_id])
      payment = @order.payments.where(:state => "pending",
                                      :payment_method_id => payment_method).first \
                || @order.payments.create(:amount => @order.total, :payment_method => payment_method)
      payment.started_processing!
      redirect_to tenpay_full_service_url(@order, payment_method)
  
      #Rails.logger.info "--->before update_attributes"
      #Rails.logger.info "paramsss #{params.inspect}"
      #if @order.update_attributes(object_params) #it would create payments
      #Rails.logger.debug "payment params returned: #{tenpay_payment_params}"
      #if @order.update_attributes(tenpay_payment_params) #it would create payments
      #  if params[:order][:coupon_code] and !params[:order][:coupon_code].blank? and @order.coupon_code.present?
      #    fire_event('spree.checkout.coupon_code_added', :coupon_code => @order.coupon_code)
      #  end
      #end
      #if tenpay_pay_by_billing_integration?
      #Rails.logger.debug "--->before tenpay_handle_billing_integration"
      #  tenpay_handle_billing_integration
      #end
    end

    def tenpay_retrieve_order(order_number)
      @order = Spree::Order.find_by_number(order_number)
      if @order
        #@order.payment.try(:payment_method).try(:provider) #configures ActiveMerchant
      end
      @order
    end

    def valid_tenpay_notification?(notification, account)
      url = "https://mapi.tenpay.com/gateway.do?service=notify_verify"
      result = HTTParty.get(url, query: {partner: account, notify_id: notification.notify_id}).body
      result == 'true'
    end

    def offsite_payment_service_url(payment_method)
      payment_method.helper.create_service_url(@order)
    end

    def tenpay_full_service_url( order, tenpay)
      #Rails.logger.debug "tenpay gateway is configured to be #{tenpay.inspect}"
      raise ArgumentError, 'require Spree::BillingIntegration::Tenpay' unless tenpay.is_a? Spree::BillingIntegration::Tenpay
      #url = OffsitePayments::Integrations::Tenpay.service_url+'?'
      helper = OffsitePayments::Integrations::Tenpay::Helper.new(order.number, tenpay.preferred_partner)
      #helper.service_version 1
      #Rails.logger.debug "helper is #{helper.inspect}"
      #using_direct_pay_service = tenpay.preferred_using_direct_pay_service

      #if using_direct_pay_service
        helper.total_fee (( order.total * 100).to_i)
      #  helper.service OffsitePayments::Integrations::Tenpay::Helper::CREATE_DIRECT_PAY_BY_USER
      #else
      #  helper.price order.item_total
      #  helper.quantity 1
      #  helper.logistics :type=> 'EXPRESS', :fee=>order.adjustment_total, :payment=>'BUYER_PAY' 
      #  helper.service OffsitePayments::Integrations::Tenpay::Helper::TRADE_CREATE_BY_BUYER
      #end
      #helper.seller :email => tenpay.preferred_email
      #url_for is controller instance method, so we have to keep this method in controller instead of model
      #Rails.logger.debug "helper is #{helper.inspect}"
      helper.body "#{order.products.collect(&:name).join(';').to_s}" #String(400) 
      helper.notify_url url_for(:only_path => false, :action => 'tenpay_notify')
      helper.return_url url_for(:only_path => false, :action => 'tenpay_done')
      helper.partner tenpay.preferred_partner
      helper.charset "utf-8"
      helper.payment_type 1
      helper.remote_ip request.remote_ip
      helper.sign
      url = URI.parse(OffsitePayments::Integrations::Tenpay.service_url)
      #Rails.logger.debug "query from url #{url.query}"
      #Rails.logger.debug "query from url parsed #{Rack::Utils.parse_nested_query(url.query).inspect}"
      #Rails.logger.debug "helper fields #{helper.form_fields.to_query}"
      url.query = ( Rack::Utils.parse_nested_query(url.query).merge(helper.form_fields) ).to_query
      Rails.logger.debug "full_service_url to be encoded is #{url.to_s}"
      url.to_s
    end

    def tenpay_pay_by_billing_integration?
     
      #Rails.logger.debug "current orderrrr: #{@order.inspect}"
      if @order.next_step_complete?
        #Rails.logger.debug "pending paymentssss: #{@order.pending_payments.inspect}"
        if @order.pending_payments.first.payment_method.kind_of? BillingIntegration 
          return true
        end
      end
      return false
    end
    
    # handle_tenpay_billing_integration (also called "offsite payment" in newer shopify modules)
    #def handle_tenpay_billing_integration 
        #helper_klass = OffsitePayments::Integrations::Tenpay::Helper
        #helper_klass.send(:remove_const, :KEY) if helper_klass.const_defined?(:KEY)
        #tenpay_helper_klass.const_set(:KEY, payment_method.preferred_partner_key)
    #end
 
    # handle all supported billing_integration
    def tenpay_handle_billing_integration      
      payment_method = @order.pending_payments.first.payment_method
      if payment_method.kind_of?(BillingIntegration::Tenpay)
        # set_tenpay_constant_if_needed 
        # OffsitePayments::Integrations::Tenpay::KEY
        # OffsitePayments::Integrations::Tenpay::ACCOUNT
        # gem activemerchant_patch_for_china is using it.
        # should not set when payment_method is updated, after restart server, it would be nil
        # TODO fork the activemerchant_patch_for_china, change constant to class variable
        tenpay_helper_klass = OffsitePayments::Integrations::Tenpay::Helper
        tenpay_helper_klass.send(:remove_const, :KEY) if tenpay_helper_klass.const_defined?(:KEY)
        tenpay_helper_klass.const_set(:KEY, payment_method.preferred_partner_key)

        #redirect_to(tenpay_checkout_payment_order_checkout_url(@order, :payment_method_id => payment_method.id))
        redirect_to tenpay_full_service_url(@order, payment_method)
      end
    end
    
    #patch spree_auth_devise/checkout_controller_decorator
    def tenpay_skip_state_validation?
      %w(registration update_registration).include?(params[:state])
    end

    def tenpay_payment_params
      params.require(:order).permit(:authenticity_token, {:payments_attributes => [ :payment_method_id]} , :coupon_code)
    end
  end
end

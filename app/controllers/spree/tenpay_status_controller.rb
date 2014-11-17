#encoding: utf-8
module Spree
  class TenpayStatusController < ApplicationController
    before_action :ensure_valid_tenpay_request, :tenpay_load_order

    # this is called when tenpay server/website redirects the user's browser back to our site
    def tenpay_done
      process_payment_notification
      session[:order_id] = nil
      redirect_to spree.order_path(@order)
    rescue RuntimeError => e
      log.error(e.message)
      redirect_to edit_order_checkout_url(@order, :state => "payment")
    end

    # this is called when tenpay server posts a notification to the "notify_url"
    def tenpay_notify
      process_payment_notification
      render text: "success!"
    rescue RuntimeError => e
      log.error(e.message)
      render text: "fail"
    end

    def process_payment_notification
      @payment.log_entries.create!(:details => @notification.to_yaml)#this creates log entries
      if @order.completed?  
        flash.notice = Spree.t(:order_processed_already)
        return
      end
      if @notification.is_payment_complete?
        unless @payment.amount == @notification.amount
          Rails.logger.warn("payment return shows different amount than was recorded in the payment. it should be #{@payment.amount} but is actually #{@notification.amount}") 
          @payment.amount = @notification.amount
        end
        @payment.complete!
        #TODO: The following logic need to be revised
        if 0.0 == @order.outstanding_balance
          @order.update_attributes(:state => "complete", :completed_at => Time.now) 
          @order.finalize!
        end
      else
        Rails.logger.debug("trade state: #{@notification.params['trade_state']}")
        Rails.logger.debug("checkout #{@order.number}")
        @payment.failure!
        redirect_to edit_order_checkout_url(@order, :state => "payment")
      end
    end

    def valid_tenpay_notification?(notification, account)
      url = "https://mapi.tenpay.com/gateway.do?service=notify_verify"
      result = HTTParty.get(url, query: {partner: account, notify_id: notification.notify_id}).body
      result == 'true'
    end

    private

    # This is put at the front of the filter chain for "return" and "notification" requests
    # Loading order is after this step so we have to get the payment_method by class name, instead of
    # getting it from the order
    def ensure_valid_tenpay_request
      @@payment_method ||= Spree::PaymentMethod.find_by(type: Spree::BillingIntegration::Tenpay)
      Rails.logger.debug("#{request.params}")
      @notification = OffsitePayments::Integrations::Tenpay.notification(request.query_parameters, key: @@payment_method.preferred_partner_key)
      @notification.acknowledge

      # TODO: add confirmation checking here. send "notify_id" to tenpay server to verify
    rescue RuntimeError, OffsitePayments::ActionViewHelperError => e
      Rails.logger.debug("#{@notification.inspect}")
      Rails.logger.warn("#{e} in request: #{request.env['REQUEST_URI']}")
      case request.path_parameters[:action]
      when ['tenpay_done','',nil]
        flash[:error] = Spree.t('invalid_alipay_request')
        redirect_to spree.root_path
      when 'tenpay_notify'
        render text: 'failure'
      else
        redirect_to spree.root_path
      end
    end

    # This is done in the default checkout_controller filter chain
    def tenpay_load_order
      Rails.logger.debug "#{__LINE__} tenpay_load_order called "
      raise "'out_trade_no' requird to load the order" unless params.key?('out_trade_no')
      order_number, payment_identifier = parse_tenpay_out_trade_no(params['out_trade_no'])
      @order  = Order.find_by_number(order_number)
      @payment = Payment.find_by(identifier: payment_identifier)
      raise RuntimeError, "Could not find order #{order_number}" unless @order.present?
      raise RuntimeError, "Could not find payment #{payment_identifier}" unless @payment.present?
      Rails.logger.debug "#{__LINE__} tenpay_load_order called and order is found #{@order.inspect}"
    end

    def parse_tenpay_out_trade_no(out_trade_no)
      out_trade_no.split('_')
    end
  end
end

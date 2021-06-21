#encoding: utf-8
#require 'services/offsite_payments'
module Spree
  class OffsitePaymentsStatusController < ApplicationController
    layout "spree/layouts/spree_offsite_payment"
    before_action :load_processor, except: :status_update
    skip_before_action :verify_authenticity_token, only: [:notification, :return]

    rescue_from Spree::OffsitePayments::InvalidRequestError,
                 Spree::OffsitePayments::UnVerifiableNotifyError,
                 Spree::OffsitePayments::InvalidOutTradeNoError,
                 Spree::OffsitePayments::PaymentNotFoundError do |error|
      logger.warn(error.message)
      redirect_to spree.root_path
    end

    def return
      @result = @processor.process
      #logger.debug("session contains: #{session.inspect}")
      @order = @processor.order
      @payment ||= @processor.payment
      unless @payment
        @payment = Spree::Payment.find_by_id(request.params[:orderRefNumber] || request.params[:identifier])
      end
      @order ||= @payment.order if @payment
      logger.debug("received result of #{@result.to_s} for payment #{@payment&.id} of order #{@order&.number}")
     
      case @result
      when :payment_processed_already
        # if it's less than a minute ago, maybe it's processed by the "notification"
        flash[:notice] = 'Payment Processed Already' if ((Time.now - @payment.updated_at) > 1.minute)
        redirect_to spree.order_path(@order) if params[:caller] != 'mobile'
      when :order_completed
        flash[:notice] = 'Order Completed'
        #session[:order_id] = nil
        if @order.is_package_order?
          redirect_to business_dashboard_path(id: @order.package.id) if params[:caller] != 'mobile'
        else
          redirect_to store_order_path(@order.store.code, @order) if params[:caller] != 'mobile'
        end
      when :payment_success_but_order_incomplete
        flash[:warn] = 'Payment success but order incomplete'
        #redirect_to edit_order_checkout_url(@order, state: "payment")
        redirect_to store_checkout_state_url(store_id: @order.store.code, state: 'payment') if params[:caller]!="mobile"
      when :payment_failure
        unless @processor.response.errors.blank?
          flash[:error] = "Payment failed - #{@processor.response.errors.join("\n")}"
        else
          flash[:error] = 'Payment failed'
        end
        #redirect_to edit_order_checkout_url(@order, state: "payment")
         redirect_to store_checkout_state_url(store_id: @order&.store&.code, state: 'payment') if params[:caller]!="mobile"
      else
         redirect_to spree.order_path(@order) if params[:caller] != 'mobile'
      end
    end

    def notification
      result = @processor.process
      logger.debug("content_type::::::#{request.content_type}")
      case result
      when Symbol 
        render text: 'success'
      else
        logger.error "Unexpected result #{result} of type #{result.class}: #{@processor.order.number}"
        render text: 'success'
      end
    end

    def publish_internal_update(payment)
      $redis||=Redis.new
      $redis.publish('payment.update', "payment_paid:#{payment.id}")
    end

    include ActionController::Live
    def status_update
      response.headers['Content-Type'] = 'text/event-stream'
      redis = Redis.new
      redis.subscribe('payment.update', 'heartbeat') do |pu|
        pu.message do |channel, message|
          case channel
          when 'heartbeat'
            response.stream.write("event: heart_beat\n")
            response.stream.write("data: #{message}\n\n")
          when 'payment.update'
            payment_id = message.match(/payment_paid:(.*)/)[1]
            logger.debug("payment update received for #{payment_id}")
            if payment_id == request.params['payment_id']
              logger.debug("sending update to client for payment")
              response.stream.write("event: order_paid\n")
              response.stream.write("data: #{payment_id}\n\n")
            else 
              logger.debug("payment update received for #{payment_id}")
            end
          end
        end
      end
      render nothing: true
    rescue IOError
      logger.warn("Client connection closed")
    ensure
      redis.quit
      response.stream.close
    end

    private

    def load_processor
      if request.params[:method] == 'easy_paisa' && request.params[:auth_token]
        @payment = Spree::Payment.find_by_id(request.params[:orderRefNumber] || request.params[:identifier])
        @checkout_token = request.params[:auth_token]
        @caller = request.params[:caller]
        render :easy_paisa_confirm
      else
        @processor = Spree::OffsitePayments.load_for(request)
        @processor.log = logger
      end
    end
  end
end

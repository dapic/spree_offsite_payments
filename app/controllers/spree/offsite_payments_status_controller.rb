#encoding: utf-8
#require 'services/offsite_payments'
module Spree
  class OffsitePaymentsStatusController < ApplicationController
    before_action :load_processor, except: :status_update
    skip_before_action :verify_authenticity_token, only: :notification

    rescue_from Spree::OffsitePayments::InvalidRequestError,
                 Spree::OffsitePayments::UnVerifiableNotifyError,
                 Spree::OffsitePayments::InvalidOutTradeNoError,
                 Spree::OffsitePayments::PaymentNotFoundError do |error|
      logger.warn(error.message)
      redirect_to spree.root_path
    end

    def return
      result = @processor.process
      logger.debug("received result of #{result.to_s} for payment #{@processor.payment.identifier} of order #{@processor.order.number}")
      #logger.debug("session contains: #{session.inspect}")
      case result
      when :payment_processed_already
        # if it's less than a minute ago, maybe it's processed by the "notification"
        flash[:notice] = Spree.t(result) if ((Time.now - @processor.payment.updated_at) > 1.minute)
        redirect_to spree.order_path(@processor.order)
      when :order_completed
        flash[:notice] = Spree.t(result)
        #session[:order_id] = nil
        redirect_to spree.order_path(@processor.order)
      when :payment_success_but_order_incomplete
        flash[:warn] = Spree.t(result)
        redirect_to edit_order_checkout_url(@processor.order, state: "payment")
      when :payment_failure
        flash[:error] = Spree.t(result)
        redirect_to edit_order_checkout_url(@processor.order, state: "payment")
      else
        redirect_to spree.order_path(@processor.order)
      end
    end

    def notification
      result = @processor.process
      logger.debug("content_type::::::#{request.content_type}")
      case result
      when ::OffsitePayments::Integrations::Wxpay::ApiResponse::NotificationResponse
        logger.info "responding with xml: #{result.to_xml}"
        logger.info "#{Spree.t(result)}: #{@processor.order.number}"
        publish_internal_update(@processor.payment)
        render xml: result
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
      @processor = Spree::OffsitePayments.load_for(request)
      @processor.log = logger
    end
  end
end

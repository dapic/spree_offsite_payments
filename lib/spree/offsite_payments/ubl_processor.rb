require 'spree/offsite_payments/processor'

module Spree::OffsitePayments
  class UblProcessor < Processor
    attr_accessor :log
    attr_reader :order, :payment
    def initialize(request)
      @request = request
      #@request.params[:method].upcase! #TODO to change 'ubl' to UBL
      load_provider
    end

    def response
      @notify
    end
    
    def parse_request
      @notify = ::OffsitePayments::Integrations::Ubl::Notification.new(@request.params)
    end
      
    
    def load_payment
      @payment = Spree::Payment.find_by(id: @notify.order_id) ||
        raise(PaymentNotFoundError, "Could not find payment with identifier #{Spree::OffsitePayments.parse_out_trade_no(@notify.out_trade_no)[1]}")
      @order = @payment.order
    end
    
    def verify_notify
      ( raise UnVerifiableNotifyError, "Could not verify the 'notify' request without transaction_id") if @notify.transaction_id.blank?
    end
        
    def process
      parse_request
      verify_notify
      
      result = catch(:done) {
        if process_payment
          process_order
        else
          #TODO show errors in processing payment
          :payment_failure
        end
      }
      log.debug("@notify is #{ @notify.inspect}")
      if @notify.respond_to?(:api_response) 
        @notify.api_response(:success)
      else
        result
      end
    end
    
    def update_payment_amount
      return unless @notify.respond_to?(:amount)
      # Payment.amount is a BigNum and @notify.amount is an instance of Money
      unless @notify.amount.amount == @payment.amount
        log.warn(Spree.t(:payment_notify_shows_different_amount, expected: @payment.amount, actual: @notify.amount.amount ))
        @payment.amount = @notify.amount.amount
        #@payment.currency = @notify.amount.currency
      end
    end
    
    def process_payment
      if @notify.acknowledge
        load_payment
        ensure_payment_not_processed
        create_payment_log_entry
        update_payment_amount 
        update_payment_status
        true
      else
        #TODO show error response to user
        false
      end
    end
    
    private
    def load_provider
      @provider = OffsitePayments::Integrations::Ubl::Notification.new(@request.params)
      @provider.params = @request.params
    end
    
  end
end

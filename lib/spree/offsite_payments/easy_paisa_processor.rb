require 'spree/offsite_payments/processor'
module Spree::OffsitePayments
  class EasyPaisaProcessor < Processor
    attr_accessor :log
    attr_reader :order, :payment
    def initialize(request)
      @request = request
      load_provider
    end

    def response
      @notify
    end
    
    def parse_request
      @notify = ::OffsitePayments::Integrations::EasyPaisa::Notification.new(@request.params)
    end
      
    
    def load_payment
      @payment = Spree::Payment.find_by(id: @notify.order_ref_number) ||
        raise(PaymentNotFoundError, "Could not find payment with order_ref_number #{@notify.order_ref_number}")
      @order = @payment.order
    end
            
    def process
      parse_request
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
        
    
    def update_payment_status
      #if @payment.payment_method.auto_capture?
        @payment.send(:handle_response, @notify, :complete, :failure)
        if @notify.success?
          @payment.process!
          #capture the payment not just authorize
          @payment.capture!
        end
        #@payment.complete!
      #else
      #  @payment.send(:handle_response, @notify, :pend, :failure)
      #end
      throw :done, :payment_failure if @payment.failed?
    end
    
    def process_payment
      return false if @notify.order_ref_number.blank?
      load_payment
      if @notify.acknowledge(@payment.payment_method.hash_key)
        ensure_payment_not_processed
        create_payment_log_entry
        update_payment_status
        true
      else
        #TODO show error response to user
        false
      end
    end
    
  end
end

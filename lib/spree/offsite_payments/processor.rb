module Spree::OffsitePayments
  class Processor
    attr_accessor :log
    attr_reader :order, :payment
    def initialize(request)
      @request = request
      load_provider
    end

    def process
      @notify = ''
      parse_request
      verify_notify
      result = catch(:done) {
        process_payment
        process_order
      }
      log.debug("@notify is #{ @notify.inspect}")
      if @notify.respond_to?(:api_response) 
        @notify.api_response(:success)
      else
        result
      end
    end

    private
    def load_provider
      payment_method_name = "Spree::BillingIntegration::#{@request.params[:method].camelize}"
      @payment_method = Spree::PaymentMethod.find_by(type: payment_method_name)
      @payment_provider = @payment_method.provider_class #this is actually a module
      #@payment_provider.logger ||= log
    end

    def parse_request
      payload = @request.post? ? @request.raw_post : @request.query_string
      @notify = @payment_provider.send(@request.path_parameters[:action].to_sym, 
                                       payload, key: @payment_method.key)
    rescue RuntimeError => e
      log.debug("request is: #{@request.inspect}")
      raise InvalidRequestError, "Error when processing #{@request.url}. \n#{e.message}"
    end

    def verify_notify
      ( raise UnVerifiableNotifyError, "Could not verify the 'notify' request with notify_id #{@notify.notify_id}" unless @notify.verify ) if @notify.respond_to?(:verify)
    end

    def process_payment
      load_payment
      ensure_notify_acknowledged
      ensure_payment_not_processed
      create_payment_log_entry
      update_payment_amount 
      update_payment_status
    end

    def load_payment
      @payment = Spree::Payment.find_by(identifier: Spree::OffsitePayments.parse_out_trade_no(@notify.out_trade_no)[1]) ||
        raise(PaymentNotFoundError, "Could not find payment with identifier #{Spree::OffsitePayments.parse_out_trade_no(@notify.out_trade_no)[1]}")
      @order = @payment.order
    end

    def ensure_notify_acknowledged
      @notify.acknowledge
    rescue SecurityError => e
      throw :done, :notify_not_acknolwedgable
    end

    def ensure_payment_not_processed
      throw :done, :payment_processed_already if @payment.completed? && @notify.success?
    end

    def create_payment_log_entry
      #TODO: better log message
      @payment.log_entries.create!( details: @notify.to_yaml)
      #@payment.log_entries.create!( details: @notify.to_log_entry )
    end

    def update_payment_amount
      return unless @notify.respond_to?(:amount)
      # Payment.amount is a BigNum and @notify.amount is an instance of Money
      unless @notify.amount == Money.new(@payment.amount * 100, @payment.currency)
        log.warn(Spree.t(:payment_notify_shows_different_amount, expected: @payment.amount, actual: @notify.amount ))
        @payment.amount = @notify.amount.amount
        @payment.currency = @notify.amount.currency
      end
    end

    def update_payment_tx_id
      @payment.foreign_transaction_id = @notify.transaction_id if @notify.transaction_id
    end

    def update_payment_status
      if @payment.payment_method.auto_capture?
        @payment.send(:handle_response, @notify, :complete, :failure)
        if @notify.success?
          #@payment.capture_events.create!(amount: @notify.amount)
          begin
            @payment.process!
            #capture the payment not just authorize
            @payment.capture!
          rescue Core::GatewayError => ex
            Raven.capture_exception(ex)
            @payment.capture_events.create!(amount: @notify.amount)            
          end
        end
        #@payment.complete!
      else
        @payment.send(:handle_response, @notify, :pend, :failure)
      end
      throw :done, :payment_failure if @payment.failed?
    end

    def process_order
      if @order.outstanding_balance > 0
        throw :done, :payment_success_but_order_incomplete
      else
        #TODO: The following logic need to be revised
        unless @order.passed_checkout_step?('complete')
          @order.next!
        else
          @order.finalize!          
        end
        throw :done, :order_completed 
      end
    end

  end
end

module Spree::OffsitePayments
  class InvalidRequestError < RuntimeError; end
  class UnVerifiableNotifyError < RuntimeError; end
  class InvalidOutTradeNoError < RuntimeError; end
  class PaymentNotFoundError < RuntimeError; end
  #class PaymentFailureError     < RuntimeError; end

  # TODO: add object caching later
  def self.load_for(request)
    Processor.new(request)
  end

  class Processor
    attr_accessor :log
    attr_reader :order
    def initialize(request)
      @request = request
      load_provider
    end

    def process
      parse_request
      verify_notify
      process_payment
      process_order
    end

    def order
      @order ||= @payment.order
    end

    private
    def load_provider
      payment_method_name = Spree::PaymentMethod.providers
      .find {|p| p.parent.name.demodulize == 'BillingIntegration' &&
             p.name.demodulize.downcase == @request.params[:method].downcase }
      #.select {|p| p.parent.name.demodulize == 'BillingIntegration' 
      #}.map(&:new)
      #.find {|p| p.method_type == @request.parameters[:payment_method] }
      @payment_method = Spree::PaymentMethod.find_by(type: payment_method_name)
      @payment_provider = @payment_method.provider_class #this is actually a module
    rescue NoMethodError
      #log.warn("The payment method '#{@request.path_parameters[:controller]}' is not supported. full request is :#{@request.url}")
      puts("The payment method '#{@request.path_parameters[:controller]}' is not supported. full request is :#{@request.url}")
    end
   
    def parse_request
      log.debug("pm is #{@payment_method.inspect}")
      log.debug("key is #{@payment_method.key}")
      @notify = @payment_provider.send(@request.path_parameters[:action].to_sym, 
                                      @request.query_string, key: @payment_method.key)
    rescue RuntimeError => e
      raise InvalidRequestError, "Error when processing #{@request.url}. \n#{e.message}"
    end

    def verify_notify
      ( raise UnVerifiableNotifyError, "Could not verify the 'notify' request with notify_id #{@notify.notify_id}" unless @notify.verify ) if @notify.respond_to?(:verify)
    end

    def process_payment
      load_payment
      ensure_payment_not_processed
      create_payment_log_entry
      update_payment_amount 
      update_payment_status
    end

    def load_payment
      @payment = Spree::Payment.find_by(identifier: parse_out_trade_no(@notify.out_trade_no)[1]) ||
        raise(PaymentNotFoundError, "Could not find payment with identifier #{parse_out_trade_no(@notify.out_trade_no)[1]}")
      @order = @payment.order
    end

    def ensure_payment_not_processed
      throw :done, :payment_processed_already if @payment.completed? == @notify.success?
    end

    def create_payment_log_entry
      #TODO: better log message
      @payment.log_entries.create!( details: @notify.to_yaml)
      #@payment.log_entries.create!( details: @notify.to_log_entry )
    end

    def update_payment_amount
      #log.warn("payment return shows different amount than was recorded in the payment. it should be #{@payment.amount} but is actually #{@notify.amount}") unless @payment.amount.to_money(@payment.currency) == @notify.amount
      log.warn(Spree.t(:payment_notify_shows_different_amount, expected: @payment.amount, actual: @notify.amount )) unless @payment.amount.to_money(@payment.currency) == @notify.amount
      @payment.amount = @notify.amount
    end

    def update_payment_status
      @notify.success? ? @payment.complete! : @payment.failure! 
      throw :done, :payment_failure if @payment.failed?
    end

    def process_order
      if @order.outstanding_balance >= 0
        throw :done, :payment_success_but_order_incomplete
      else
        #TODO: The following logic need to be revised
        @order.update_attributes(:state => "complete", :completed_at => Time.now) 
        @order.finalize!
        throw :done, :order_completed
      end
    end

    # should return [ordernumber, payment_identifier]
    def parse_out_trade_no(out_trade_no)
      out_trade_no.split('_').tap { |oid, pid| raise InvalidOutTradeNoError, "Invalid out_trade_no #{out_trade_no}" unless pid }
    end
#    def load_data
#      ordernumber, payment_identifier = parse_out_trade_no(@notify.out_trade_no)
#      @payment = Payment.find_by(identifier: payment_identifier)
#      @order = @payment.order
#    end

  end
end



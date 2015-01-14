module Spree::OffsitePayments
  #this module encapsulates the business logic of handling payments with Wxpay
  module Wxpay

    class BusinessError < RuntimeError; end
    MODEL_CLASS = Spree::BillingIntegration::Wxpay
    mattr_reader :payment_method, :payment_provider

    #delegate self.:url_helpers, to: 'Rails.application.routes' 
    def self.payment_method
      @@payment_method ||= Spree::PaymentMethod.find_by(type: Wxpay::MODEL_CLASS)
    end

    def self.payment_provider
      @@payment_provider ||= self.payment_method.provider_class
    end

    def self.set_provider_credentials
      self.payment_provider.credentials = {
        appid: payment_method.preferred_appid,
        mch_id: payment_method.preferred_mch_id,
        key: payment_method.key
      } if self.payment_provider.credentials.nil?
    end

    def self.send_request(api_type, payment, options = {})
      #Rails.logger.debug("#{__LINE__}:#{api_type}, #{payment.identifier}, options: #{options}")
      payload = self.assemble_payload(api_type, payment, options)
      self.send_api_request(api_type, payload)
      .tap {|resp| Rails.logger.debug("#{api_type} response: #{resp.inspect}") }
    end

    def self.assemble_payload(api_type, payment, options={})
      params = {}
      case api_type
      when :unifiedorder
        order = payment.order
        params[:nonce_str] =  SecureRandom.hex
        params[:body] = "#{order.products.collect(&:name).join(';').to_s}"
        params[:out_trade_no] = Spree::OffsitePayments.create_out_trade_no(payment)
        params[:total_fee] = ((order.total*100).to_i)
        params[:spbill_create_ip] = order.last_ip_address #request.remote_ip
        #params[:notify_url] = Spree::Core::Engine.routes.url_helpers.notify_url(method: :wxpay)
        #params[:notify_url] = options[:request].notify_url(method: :wxpay)
        params[:notify_url] = Spree::Core::Engine.routes.url_helpers.notify_url(
          host: options[:request].host, method: :wxpay)
        params[:trade_type] = 'NATIVE'
      when :orderquery
        params[:out_trade_no] = Spree::OffsitePayments.create_out_trade_no(payment)
        params[:transaction_id] = payment.foreign_transaction_id
      else
        raise RuntimeError, "Unsupported api_type #{api_type}"
      end
      params
    end

    def self.send_api_request(api_type, payload)
      @helper = payment_provider.get_helper(api_type, payload)
      @helper.sign
      @helper.process
    end

    class Manager
      def initialize
        Wxpay.set_provider_credentials
        Wxpay.payment_provider.logger = Rails.logger
      end

      def get_payment_url(payment, request)
      #Rails.logger.debug("#{__FILE__}-#{__LINE__}:#{payment.identifier}, #{request.inspect}")
        if payment.payment_url
          resp = Wxpay.send_request(:orderquery, payment )
          case resp.trade_state
          when 'NOTPAY','NOPAY'
            #resp.pay_url
            payment.payment_url
          when 'SUCCESS', 'USERPAYING'
            update_payment(payment, resp)
            update_order(payment,resp)
            raise BusinessError, "order #{payment.order.number} already paid"
          else
            raise RuntimeError, "Don't know what to do with trade_state #{resp.trade_state}"
          end
        else
          resp = Wxpay.send_request(:unifiedorder, payment, request: request)
          payment.log_entries.create!(details: resp.to_yaml)
          if resp.biz_success?
            payment.payment_url = resp.pay_url
            #payment.foreign_transaction_id = resp.prepay_id
            payment.save!
            resp.pay_url
          else
            case resp.biz_failure_code
            when 'ORDERPAID'
              resp = Wxpay.send_request(:orderquery, payment)
              update_payment(payment,resp)
              update_order(payment,resp)
              raise BusinessError, "order #{payment.order.number} already paid"
            else
              raise RuntimeError, "Don't know what to do with #{resp.biz_failure_code}"
            end
          end
        end
      end

      # response should be an "orderquery" response
      def update_payment(payment, response)
        case response.trade_state
        when 'SUCCESS'
          payment.amount = response.total_fee
          payment.foreign_transaction_id ||= response.transaction_id 
          payment.complete!
        else
          raise RuntimeError, "Don't know what to do with trade_state #{response.trade_state}"
        end
      end

      def update_order(payment, response)
        order = payment.order
        unless order.outstanding_balance > 0
          #TODO: The following logic need to be revised
          order.update_attributes(:state => "complete", :completed_at => Time.now)
          order.finalize!
        end
      end

      def transaction_status(payment)    
        resp = Wxpay.send_request(:orderquery, payment)
      end

      # TODO: assuming the payment_url expires in 1 hour
      def payment_url_expired?(payment)
        ((Time.now - payment.updated_at) > 1.hour)
      end

    end
  end
end

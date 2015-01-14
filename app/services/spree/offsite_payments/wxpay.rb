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
        appsecret: payment_method.preferred_appsecret,
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

    def self.assemble_payload(api_type, payment, request: nil, wx_trade_type: 'NATIVE', client_openid: nil)
      params = {}
      case api_type
      when :unifiedorder
        order = payment.order
        params[:nonce_str] =  SecureRandom.hex
        params[:body] = "#{order.products.collect(&:name).join(';').to_s}"
        params[:out_trade_no] = Spree::OffsitePayments.create_out_trade_no(payment)
        params[:total_fee] = ((order.total*100).to_i)
        params[:spbill_create_ip] = ( request.remote_ip || order.last_ip_address )
        #params[:notify_url] = Spree::Core::Engine.routes.url_helpers.notify_url(method: :wxpay)
        #params[:notify_url] = options[:request].notify_url(method: :wxpay)
        params[:notify_url] = Spree::Core::Engine.routes.url_helpers.notify_url(
          host: request.host, method: :wxpay)
        params[:trade_type] = wx_trade_type
        params[:openid] = client_openid if client_openid
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

      def get_payment_url(payment, request )
        #Rails.logger.debug("#{__FILE__}-#{__LINE__}:#{payment.identifier}, #{request.inspect}")
        if payment.payment_url && payment_url_valid?(payment)
          payment.payment_url
        else
          resp = Wxpay.send_request(
            :unifiedorder, 
            payment, 
            request: request,
            wx_trade_type: 'NATIVE',
          )
          puts "ppppppp#{resp.inspect}"
          payment.log_entries.create!(details: resp.to_yaml)
          if resp.biz_success?
            #payment.payment_url = resp.pay_url
            #payment.foreign_transaction_id = resp.prepay_id
            #payment.save!
            return resp.pay_url
          else
            handle_biz_failure(resp)
          end
        end
      end

      def payment_url_valid?(payment)
        resp = Wxpay.send_request(:orderquery, payment )
        case resp.trade_state
        when 'NOTPAY','NOPAY'
          true
        when 'SUCCESS', 'USERPAYING'
          update_payment(payment, resp)
          update_order(payment,resp)
          raise BusinessError, "order #{payment.order.number} already paid"
        else
          raise RuntimeError, "Don't know what to do with trade_state #{resp.trade_state}"
        end
      end

      def get_authorize_url(redirect_uri) #,  state)
        Wxpay.payment_provider.auth_client.authorize_url(redirect_uri, 'snsapi_base', 'payment')
      end

      def get_client_openid(code)
        @access_token_result = Wxpay.payment_provider.auth_client.get_oauth_access_token(code)
      end

      def get_prepay_id(payment, request, client_openid)
        resp = Wxpay.send_request(
          :unifiedorder, 
          payment, 
          request: request,
          wx_trade_type: 'JSAPI',
          client_openid: client_openid
        )
        payment.log_entries.create!(details: resp.to_yaml)
        if resp.biz_success?
          return resp.biz_payload['prepay_id']
        else
        end
      end

      def get_wcpay_request_payload(prepay_id)
        Wxpay.payment_provider.get_helper(:get_brand_wcpay, prepay_id).payload
      end

      def handle_biz_failure(resp)
        case resp.biz_failure_code
        when 'ORDERPAID'
          resp = Wxpay.send_request(:orderquery, payment)
          update_payment(payment,resp)
          update_order(payment,resp)
          raise BusinessError, "order #{payment.order.number} already paid"
        when 'OUT_TRADE_NO_USED'
          # need to get a new 'out_trade_no'
          binding.pry
          raise "#{resp.biz_failure_code} should not happen as we always create new payments now"
        else
          raise RuntimeError, "Don't know what to do with #{resp.biz_failure_code}"
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

      def auth_client
        @auth_client ||= Wxpay.payment_provider.auth_client
      end
    end
  end
end

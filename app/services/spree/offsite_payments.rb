require 'spree/offsite_payments/processor'
require 'spree/offsite_payments/easy_paisa_processor'
require 'spree/offsite_payments/jazz_cash_processor'
require 'spree/offsite_payments/ubl_processor'
module Spree::OffsitePayments
  class InvalidRequestError < RuntimeError; end
  class UnVerifiableNotifyError < RuntimeError; end
  class InvalidOutTradeNoError < RuntimeError; end
  class PaymentNotFoundError < RuntimeError; end

  # TODO: add object caching later
  def self.load_for(request)
    if request.params[:method] == 'ubl'
      UblProcessor.new(request)
    elsif request.params[:method] == 'easy_paisa'
      EasyPaisaProcessor.new(request)
    elsif request.params[:method] == 'jazz_cash'
      JazzCashProcessor.new(request)
    else
      Processor.new(request)
    end
  end

  def self.create_out_trade_no( payment )
    "#{payment.order.number}_#{payment.identifier}"
  end

  # should return [ordernumber, payment_identifier]
  def self.parse_out_trade_no(out_trade_no)
    out_trade_no.split('_').tap { |oid, pid| raise InvalidOutTradeNoError, "Invalid out_trade_no #{out_trade_no}" unless pid }
  end
end

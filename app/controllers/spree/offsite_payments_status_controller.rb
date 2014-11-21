#encoding: utf-8
#require 'services/offsite_payments'
module Spree
  class OffsitePaymentsStatusController < ApplicationController
#    include OffsitePayment::Processing

    before_action :load_processor

    rescue_from Spree::OffsitePayments::InvalidRequestError,
                 Spree::OffsitePayments::UnVerifiableNotifyError,
                 Spree::OffsitePayments::InvalidOutTradeNoError,
                 Spree::OffsitePayments::PaymentNotFoundError do |error|
      Rails.logger.warn(error.message)
      redirect_to spree.root_path
    end

    def return
      result = catch(:done) { @processor.process }
      case result
      when :payment_processed_already, :order_completed
        flash[:notice] = Spree.t(result)
        session[:order_id] = nil
        Rails.logger.debug("to show order: #{@processor.order}")
        redirect_to spree.order_path(@processor.order)
      when :payment_success_but_order_incomplete
        flash[:warn] = Spree.t(result)
        session[:order_id] = nil
        redirect_to edit_order_checkout_url(@processor.order, state: "payment")
      when :payment_failure
        flash[:error] = Spree.t(result)
        redirect_to edit_order_checkout_url(@processor.order, state: "payment")
      else
        redirect_to spree.order_path(@processor.order)
      end
    end

    def notification
    #def notify
      catch (:done) { @processor.process }
      render text: 'success'
    end

    private

    def load_processor
      Rails.logger.debug("#{request.params[:payment_method]}")
      #Rails.logger.debug("#{request.params[:payment_method]}")
      Rails.logger.debug("controller is #{request.path_parameters[:controller]} #{request.params[:payment_method]}")
      @processor = Spree::OffsitePayments.load_for(request)
      @processor.log = Rails.logger
    end
  end
end

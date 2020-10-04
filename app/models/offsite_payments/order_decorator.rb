module OffsitePayments
  module OrderDecorator
    def next_step_complete?
      available_steps = checkout_steps
      !self.cart? && available_steps[ available_steps.index( self.state ).succ ] == 'complete'
    end
    Spree::Order.prepend self  
  end
end

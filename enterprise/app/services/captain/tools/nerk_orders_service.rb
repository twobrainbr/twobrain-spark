class Captain::Tools::NerkOrdersService < Captain::Tools::NerkBaseService
  description 'Find recent NERK orders, amounts, payments, refunds and returns for the verified customer in the current conversation.'

  def execute
    context = verified_customer_context
    return VERIFICATION_REQUIRED if context.blank?

    orders = context.dig('commerce', 'orders') || []
    return 'No NERK orders were found for this verified contact.' if orders.empty?

    JSON.pretty_generate(orders)
  rescue Integrations::Nerk::Client::ApiError => e
    "NERK order lookup failed: #{e.message}"
  end
end

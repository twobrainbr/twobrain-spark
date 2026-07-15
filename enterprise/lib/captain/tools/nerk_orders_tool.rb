class Captain::Tools::NerkOrdersTool < Captain::Tools::NerkBaseTool
  description 'Find recent NERK orders, amounts, payments, refunds and returns for the verified customer in the current conversation.'

  def perform(tool_context)
    context = verified_customer_context(tool_context)
    return VERIFICATION_REQUIRED if context.blank?

    orders = context.dig('commerce', 'orders') || []
    return 'No NERK orders were found for this verified contact.' if orders.empty?

    JSON.pretty_generate(orders)
  rescue Integrations::Nerk::Client::ApiError => e
    "NERK order lookup failed: #{e.message}"
  end
end

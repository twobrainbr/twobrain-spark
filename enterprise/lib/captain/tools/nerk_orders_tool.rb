class Captain::Tools::NerkOrdersTool < Captain::Tools::NerkBaseTool
  description 'Find recent NERK orders for the customer in the current conversation. Use this before answering order or payment status questions.'

  def perform(tool_context)
    orders = contact_orders(tool_context)
    return 'No NERK orders were found for this verified contact.' if orders.empty?

    JSON.pretty_generate(orders)
  rescue Integrations::Nerk::Client::ApiError => e
    "NERK order lookup failed: #{e.message}"
  end
end

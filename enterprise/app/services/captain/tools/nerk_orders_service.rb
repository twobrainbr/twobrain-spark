class Captain::Tools::NerkOrdersService < Captain::Tools::NerkBaseService
  description 'Find recent NERK orders for the customer in the current conversation.'

  def execute
    orders = contact_orders
    return 'No NERK orders were found for this verified contact.' if orders.empty?

    JSON.pretty_generate(orders)
  rescue Integrations::Nerk::Client::ApiError => e
    "NERK order lookup failed: #{e.message}"
  end
end

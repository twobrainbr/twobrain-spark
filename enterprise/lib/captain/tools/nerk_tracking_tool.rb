class Captain::Tools::NerkTrackingTool < Captain::Tools::NerkBaseTool
  description 'Get live shipment tracking for a NERK order that belongs to the customer in the current conversation.'
  param :order_number, type: 'string', desc: 'The NERK order number supplied by the customer'

  def perform(tool_context, order_number:)
    order = contact_orders(tool_context).find do |candidate|
      candidate['orderNumber'].to_s.casecmp?(order_number.to_s) || candidate['id'].to_s == order_number.to_s
    end
    return 'The order was not found for this verified contact.' if order.blank?

    JSON.pretty_generate(nerk_client.tracking(order_id: order['orderNumber']))
  rescue Integrations::Nerk::Client::ApiError => e
    "NERK tracking lookup failed: #{e.message}"
  end
end

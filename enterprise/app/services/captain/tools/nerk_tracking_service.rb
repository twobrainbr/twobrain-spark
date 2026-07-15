class Captain::Tools::NerkTrackingService < Captain::Tools::NerkBaseService
  description 'Get live delivery tracking for a NERK order owned by the current customer.'
  param :order_number, desc: 'NERK order number supplied by the customer', required: true

  def execute(order_number:)
    order = contact_orders.find do |candidate|
      candidate['orderNumber'].to_s.casecmp?(order_number.to_s) || candidate['id'].to_s == order_number.to_s
    end
    return 'The order was not found for this verified contact.' if order.blank?

    JSON.pretty_generate(nerk_client.tracking(order_id: order['orderNumber']))
  rescue Integrations::Nerk::Client::ApiError => e
    "NERK tracking lookup failed: #{e.message}"
  end
end

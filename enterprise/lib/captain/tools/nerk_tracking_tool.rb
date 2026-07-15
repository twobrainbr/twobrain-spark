class Captain::Tools::NerkTrackingTool < Captain::Tools::NerkBaseTool
  description 'Get live shipment tracking for a NERK order that belongs to the customer in the current conversation.'
  param :order_number, type: 'string', desc: 'The NERK order number supplied by the customer'

  def perform(tool_context, order_number:)
    contact = verified_contact(tool_context)
    return VERIFICATION_REQUIRED if contact.blank?

    tracking = nerk_client.tracking(email: contact.email, phone: contact.phone_number, order_number: order_number)
    return 'The order was not found for this verified contact.' if tracking.blank?

    JSON.pretty_generate(tracking)
  rescue Integrations::Nerk::Client::ApiError => e
    "NERK tracking lookup failed: #{e.message}"
  end
end

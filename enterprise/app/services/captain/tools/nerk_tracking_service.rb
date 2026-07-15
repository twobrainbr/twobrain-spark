class Captain::Tools::NerkTrackingService < Captain::Tools::NerkBaseService
  description 'Get live delivery tracking for a NERK order owned by the current customer.'
  param :order_number, desc: 'NERK order number supplied by the customer', required: true

  def execute(order_number:)
    contact = verified_contact
    return VERIFICATION_REQUIRED if contact.blank?

    tracking = nerk_client.tracking(email: contact.email, phone: contact.phone_number, order_number: order_number)
    return 'The order was not found for this verified contact.' if tracking.blank?

    JSON.pretty_generate(tracking)
  rescue Integrations::Nerk::Client::ApiError => e
    "NERK tracking lookup failed: #{e.message}"
  end
end

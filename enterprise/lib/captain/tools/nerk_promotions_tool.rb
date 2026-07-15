class Captain::Tools::NerkPromotionsTool < Captain::Tools::NerkBaseTool
  description 'List active public NERK coupon codes that may be offered to customers.'

  def perform(_tool_context)
    coupons = nerk_client.promotions
    return 'No public NERK coupons are currently available.' if coupons.empty?

    JSON.pretty_generate(coupons)
  rescue Integrations::Nerk::Client::ApiError => e
    "NERK coupon lookup failed: #{e.message}"
  end
end

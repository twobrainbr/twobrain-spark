class Captain::Tools::NerkClubTool < Captain::Tools::NerkBaseTool
  description 'Get NERK Club membership, points and wallet balance for the verified customer in the current conversation.'

  def perform(tool_context)
    context = verified_customer_context(tool_context)
    return VERIFICATION_REQUIRED if context.blank?

    JSON.pretty_generate(context.dig('commerce').slice('loyalty', 'wallet'))
  rescue Integrations::Nerk::Client::ApiError => e
    "NERK Club lookup failed: #{e.message}"
  end
end

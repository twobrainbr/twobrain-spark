class Captain::Tools::NerkBaseTool < Captain::Tools::BasePublicTool
  VERIFICATION_REQUIRED = 'Identity verification required. Ask the customer to sign in to NERK and reopen the chat before sharing personal commerce data.'.freeze

  def active?
    @assistant.account.feature_enabled?('nerk_integration') && Integrations::Nerk::Client.configured?
  end

  private

  def nerk_client
    @nerk_client ||= Integrations::Nerk::Client.from_installation_config
  end

  def verified_contact(tool_context)
    state = tool_context&.state
    return unless state&.dig(:contact_inbox, :hmac_verified)

    find_contact(state)
  end

  def verified_customer_context(tool_context)
    contact = verified_contact(tool_context)
    return unless contact

    nerk_client.customer_context(email: contact.email, phone: contact.phone_number)
  end
end

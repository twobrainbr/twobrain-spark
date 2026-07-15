class Captain::Tools::NerkBaseTool < Captain::Tools::BasePublicTool
  def active?
    nerk_hook.present?
  end

  private

  def nerk_hook
    @nerk_hook ||= @assistant.account.hooks.enabled.find_by(app_id: 'nerk')
  end

  def nerk_client
    @nerk_client ||= Integrations::Nerk::Client.new(
      base_url: nerk_hook.reference_id,
      access_token: nerk_hook.access_token
    )
  end

  def contact_orders(tool_context)
    contact = find_contact(tool_context&.state)
    return [] if contact.blank?

    nerk_client.orders(email: contact.email, phone: contact.phone_number)
  end
end

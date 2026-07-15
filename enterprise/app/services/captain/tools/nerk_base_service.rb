class Captain::Tools::NerkBaseService < Captain::Tools::BaseTool
  def initialize(assistant, conversation: nil)
    @conversation = conversation
    super(assistant)
  end

  private

  def nerk_client
    hook = assistant.account.hooks.enabled.find_by!(app_id: 'nerk')
    Integrations::Nerk::Client.new(base_url: hook.reference_id, access_token: hook.access_token)
  end

  def contact_orders
    contact = @conversation&.contact
    return [] if contact.blank?

    nerk_client.orders(email: contact.email, phone: contact.phone_number)
  end
end

class Captain::Tools::NerkBaseService < Captain::Tools::BaseTool
  VERIFICATION_REQUIRED = 'Identity verification required. Ask the customer to sign in to NERK and reopen the chat before sharing personal commerce data.'.freeze

  def initialize(assistant, conversation: nil)
    @conversation = conversation
    super(assistant)
  end

  private

  def nerk_client
    @nerk_client ||= Integrations::Nerk::Client.from_installation_config
  end

  def verified_contact
    return unless @conversation&.contact_inbox&.hmac_verified?

    @conversation.contact
  end

  def verified_customer_context
    contact = verified_contact
    return unless contact

    nerk_client.customer_context(email: contact.email, phone: contact.phone_number)
  end
end

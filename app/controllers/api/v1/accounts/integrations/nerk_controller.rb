class Api::V1::Accounts::Integrations::NerkController < Api::V1::Accounts::BaseController
  before_action :ensure_nerk_enabled
  before_action :validate_contact, only: [:context, :orders, :tracking]

  def context
    render json: { context: customer_context }
  rescue Integrations::Nerk::Client::IdentityVerificationRequired => e
    render json: { error: e.message }, status: :conflict
  rescue Integrations::Nerk::Client::ApiError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def orders
    render json: { orders: customer_context.dig('commerce', 'orders') || [] }
  rescue Integrations::Nerk::Client::IdentityVerificationRequired => e
    render json: { error: e.message }, status: :conflict
  rescue Integrations::Nerk::Client::ApiError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def products
    render json: { products: client.products(query: params.require(:query)) }
  rescue ActionController::ParameterMissing, Integrations::Nerk::Client::ApiError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def tracking
    tracking = client.tracking(
      email: contact.email,
      phone: contact.phone_number,
      order_number: params.require(:order_number),
      source_account_id: Current.account.id,
      **channel_identity
    )
    return render json: { error: 'Order not found for this contact' }, status: :not_found if tracking.blank?

    render json: { tracking: tracking }
  rescue Integrations::Nerk::Client::IdentityVerificationRequired => e
    render json: { error: e.message }, status: :conflict
  rescue ActionController::ParameterMissing, Integrations::Nerk::Client::ApiError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  private

  def ensure_nerk_enabled
    return if Current.account.feature_enabled?('nerk_integration') && Integrations::Nerk::Client.configured?

    render json: { error: 'NERK integration is not enabled' }, status: :forbidden
  end

  def client
    @client ||= Integrations::Nerk::Client.from_installation_config
  end

  def customer_context
    @customer_context ||= client.customer_context(
      email: contact.email,
      phone: contact.phone_number,
      source_account_id: Current.account.id,
      **channel_identity
    )
  end

  def channel_identity
    contact_inbox = contact.contact_inboxes.includes(:inbox).order(updated_at: :desc).first
    return {} if contact_inbox.blank? || contact_inbox.source_id.blank?

    {
      channel: contact_inbox.inbox.channel_type.delete_prefix('Channel::').delete_suffix('Profile').underscore,
      external_id: contact_inbox.source_id
    }
  end

  def contact
    @contact ||= Current.account.contacts.find_by(id: params[:contact_id])
  end

  def validate_contact
    return if contact.present? && (contact.email.present? || contact.phone_number.present? || channel_identity.present?)

    render json: { error: 'Contact information missing' }, status: :unprocessable_entity
  end
end

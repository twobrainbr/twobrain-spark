class Api::V1::Accounts::Integrations::NerkController < Api::V1::Accounts::BaseController
  before_action :fetch_hook, except: [:create]
  before_action :validate_contact, only: [:orders]

  def create
    base_url = normalized_base_url
    access_token = params.require(:api_token)
    client = Integrations::Nerk::Client.new(base_url: base_url, access_token: access_token)
    client.validate!

    hook = Current.account.hooks.create!(
      app_id: 'nerk',
      reference_id: base_url,
      access_token: access_token,
      status: 'enabled',
      settings: { connected_at: Time.current.iso8601 }
    )
    render json: { id: hook.id, app_id: hook.app_id, status: hook.status }, status: :created
  rescue ActionController::ParameterMissing, URI::InvalidURIError => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue Integrations::Nerk::Client::ApiError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def orders
    render json: { orders: client.orders(email: contact.email, phone: contact.phone_number) }
  rescue Integrations::Nerk::Client::ApiError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def products
    query = params.require(:query)
    render json: { products: client.products(query: query) }
  rescue ActionController::ParameterMissing, Integrations::Nerk::Client::ApiError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def tracking
    order_id = params.require(:order_id)
    render json: { tracking: client.tracking(order_id: order_id) }
  rescue ActionController::ParameterMissing, Integrations::Nerk::Client::ApiError => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def destroy
    @hook.destroy!
    head :ok
  end

  private

  def fetch_hook
    @hook = Current.account.hooks.find_by!(app_id: 'nerk')
  end

  def client
    @client ||= Integrations::Nerk::Client.new(base_url: @hook.reference_id, access_token: @hook.access_token)
  end

  def contact
    @contact ||= Current.account.contacts.find_by(id: params[:contact_id])
  end

  def validate_contact
    return if contact.present? && (contact.email.present? || contact.phone_number.present?)

    render json: { error: 'Contact information missing' }, status: :unprocessable_entity
  end

  def normalized_base_url
    uri = URI.parse(params.require(:base_url))
    raise URI::InvalidURIError, 'NERK URL must use HTTPS' unless uri.is_a?(URI::HTTPS)
    raise URI::InvalidURIError, 'NERK URL host is required' if uri.host.blank?

    "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless uri.default_port == uri.port}"
  end
end

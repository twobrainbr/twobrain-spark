class Integrations::Nerk::Client
  class ApiError < StandardError; end
  class IdentityVerificationRequired < ApiError; end

  MAX_RESPONSE_SIZE = 1.megabyte

  class << self
    def configured?
      base_url.present? && access_token.present?
    end

    def from_installation_config
      raise ApiError, 'NERK integration is not configured' unless configured?

      new(base_url: base_url, access_token: access_token)
    end

    private

    def base_url
      GlobalConfigService.load('NERK_API_BASE_URL', nil)
    end

    def access_token
      GlobalConfigService.load('NERK_API_TOKEN', nil)
    end
  end

  def initialize(base_url:, access_token:)
    @base_url = normalized_base_url(base_url)
    @access_token = access_token
  end

  def customer_context(email:, phone:, source_account_id: nil, channel: nil, external_id: nil)
    response = get('/api/v1/context/customer', {
      email: email.presence,
      phone: phone.presence,
      source_account_id: source_account_id.presence,
      channel: channel.presence,
      external_id: external_id.presence
    }.compact)
    data = response['data']
    raise ApiError, 'NERK API returned an invalid customer context' unless data.is_a?(Hash)

    present_context(data)
  end

  def orders(email:, phone:, **identity)
    customer_context(email: email, phone: phone, **identity).dig('commerce', 'orders') || []
  end

  def tracking(email:, phone:, order_number:, **identity)
    order = orders(email: email, phone: phone, **identity).find do |candidate|
      candidate['order_number'].to_s.casecmp?(order_number.to_s) || candidate['id'].to_s == order_number.to_s
    end
    return nil if order.blank?

    {
      'order_number' => order['order_number'],
      'status' => order['status'],
      'promised_at' => order.dig('shipping', 'promised_at'),
      'shipments' => order.dig('shipping', 'shipments') || []
    }
  end

  def products(query: nil)
    response = get('/api/v1/products', query: query.presence, status: 'active', limit: 60)
    Array(response['data']).map { |product| present_product(product) }
  end

  def promotions
    data = get('/api/v1/promotions')['data']
    return { 'coupons' => [], 'combos' => [] } unless data.is_a?(Hash)

    {
      'coupons' => Array(data['coupons']).filter_map { |coupon| present_available_coupon(coupon) },
      'combos' => Array(data['combos']).filter_map { |combo| present_available_combo(combo) }
    }
  end

  def carts(customer_id:)
    Array(get('/api/v1/carts', customer_id: customer_id, include_history: true, limit: 20)['data'])
  end

  def sync_lead(name:, email:, phone:)
    data = request(:post, '/api/v1/customers', {
      name: name,
      email: email,
      phone: phone
    })['data']
    raise ApiError, 'A NERK não retornou o cliente sincronizado.' unless data.is_a?(Hash)

    data
  end

  def start_new_cart(customer_id:)
    request(:post, "/api/v1/customers/#{CGI.escape(customer_id)}/carts", {})['data']
  end

  def create_assisted_order(customer_id:, lines:, coupon_code: nil, cart_id: nil, shipping_address_id: nil, shipping_zip: nil,
                            shipping_service_id: nil, shipping_discount_cents: nil)
    request(
      :post,
      "/api/v1/customers/#{CGI.escape(customer_id)}/carts",
      {
        lines: lines,
        coupon_code: coupon_code.presence,
        cart_id: cart_id.presence,
        shipping_address_id: shipping_address_id.presence,
        shipping_zip: shipping_zip.presence,
        shipping_service_id: shipping_service_id.presence,
        shipping_discount_cents: shipping_discount_cents
      }.compact
    )['data']
  end

  def validate_customer_field(type:, value:, person_type: nil)
    request(
      :post,
      '/api/v1/validations',
      { type: type, value: value, person_type: person_type }.compact
    )['data']
  end

  def update_order(order_id:, notes:)
    request(:patch, "/api/v1/orders/#{CGI.escape(order_id)}", { notes: notes })['data']
  end

  def redeem_loyalty(customer_id:, points:)
    request(
      :post,
      "/api/v1/customers/#{CGI.escape(customer_id)}/loyalty/redemptions",
      { points: points.to_i }
    )['data']
  end

  private

  def request(method, path, payload)
    response_body = +''
    SafeFetch.fetch(
      "#{@base_url}#{path}",
      method: method,
      body: payload.to_json,
      headers: {
        'Accept' => 'application/json',
        'Content-Type' => 'application/json',
        'Authorization' => "Bearer #{@access_token}"
      },
      max_bytes: MAX_RESPONSE_SIZE,
      validate_content_type: false,
      capture_error_body: true
    ) { |result| response_body = result.tempfile.read }
    JSON.parse(response_body)
  rescue JSON::ParserError
    raise ApiError, 'A API da NERK retornou uma resposta inválida.'
  rescue SafeFetch::HttpError => e
    raise ApiError, api_error_message(e)
  rescue SafeFetch::Error => e
    raise ApiError, "Falha na comunicação com a NERK: #{e.message}"
  end

  def get(path, query = {})
    query_string = URI.encode_www_form(query)
    url = "#{@base_url}#{path}#{"?#{query_string}" if query_string.present?}"
    response_body = +''

    SafeFetch.fetch(
      url,
      headers: {
        'Accept' => 'application/json',
        'Authorization' => "Bearer #{@access_token}"
      },
      max_bytes: MAX_RESPONSE_SIZE,
      validate_content_type: false,
      capture_error_body: true
    ) { |result| response_body = result.tempfile.read }

    JSON.parse(response_body)
  rescue JSON::ParserError
    raise ApiError, 'NERK API returned invalid JSON'
  rescue SafeFetch::HttpError => e
    if e.message.start_with?('409 ')
      raise IdentityVerificationRequired,
            'Este contato ainda não está vinculado a um cliente NERK. ' \
            'Adicione ao contato o mesmo e-mail ou telefone usado na NERK e atualize este painel para consultar pedidos e benefícios.'
    end

    raise ApiError, api_error_message(e)
  rescue SafeFetch::Error => e
    raise ApiError, "NERK API request failed: #{e.message}"
  end

  def normalized_base_url(value)
    uri = URI.parse(value.to_s)
    raise ApiError, 'NERK API URL must use HTTPS' unless uri.is_a?(URI::HTTPS)
    raise ApiError, 'NERK API URL host is required' if uri.host.blank?

    "#{uri.scheme}://#{uri.host}#{":#{uri.port}" unless uri.default_port == uri.port}"
  rescue URI::InvalidURIError => e
    raise ApiError, e.message
  end

  def api_error_message(error)
    detail = JSON.parse(error.response_body.to_s)['detail'] if error.response_body.present?
    detail.presence || "Falha na API da NERK: #{error.message}"
  rescue JSON::ParserError
    "Falha na API da NERK: #{error.message}"
  end

  def present_context(data)
    commerce = data['commerce'].is_a?(Hash) ? data['commerce'] : {}
    customer = data['customer'].is_a?(Hash) ? data['customer'] : nil
    {
      'identity_match' => data['identity_match'],
      'customer' => customer&.slice(
        'id', 'name', 'email', 'phone', 'person_type', 'document', 'company_name', 'trade_name', 'city', 'bio',
        'country_code', 'social_profiles', 'lead_score', 'lifetime_value_cents', 'addresses', 'email_verified'
      ),
      'commerce' => {
        'orders' => Array(commerce['orders']).map { |order| present_order(order) },
        'loyalty' => present_loyalty(commerce['loyalty']),
        'wallet' => commerce['wallet']&.slice('balance_cents', 'recent_activity')
      },
      'summary' => data['summary'],
      'links' => customer && {
        'customer' => "#{@base_url}/usuarios/#{customer['id']}",
        'new_order' => "#{@base_url}/usuarios/#{customer['id']}/pdv"
      }
    }
  end

  def present_order(order)
    amounts = order['amounts'].is_a?(Hash) ? order['amounts'] : {}
    shipping = order['shipping'].is_a?(Hash) ? order['shipping'] : {}
    {
      'id' => order['id'],
      'order_number' => order['order_number'] || order['orderNumber'],
      'status' => order['status'],
      'payment_status' => order['payment_status'] || order['paymentStatus'],
      'amounts' => {
        'subtotal_cents' => amounts['subtotal_cents'] || order['subtotalCents'],
        'discount_cents' => amounts['discount_cents'] || order['discountCents'],
        'shipping_cents' => amounts['shipping_cents'] || order['shippingCents'],
        'total_cents' => amounts['total_cents'] || order['totalCents'],
        'currency' => amounts['currency'] || order['currency'] || 'BRL'
      },
      'items' => Array(order['items']).map do |item|
        {
          'name' => item['name'],
          'sku' => item['sku'],
          'quantity' => item['quantity'],
          'unit_price_cents' => item['unit_price_cents'] || item['unitPriceCents'],
          'total_cents' => item['total_cents'] || item['totalCents']
        }
      end,
      'payments' => Array(order['payments']).map { |payment| present_payment(payment) },
      'returns' => Array(order['returns']).map { |order_return| present_return(order_return) },
      'shipping' => {
        'promised_at' => shipping['promised_at'] || order['shippingPromisedAt'],
        'destination' => shipping['destination'],
        'shipments' => Array(shipping['shipments'] || order['shipments']).map { |shipment| present_shipment(shipment) }
      },
      'created_at' => order['created_at'] || order['createdAt'],
      'updated_at' => order['updated_at'] || order['updatedAt'],
      'notes' => order['notes'],
      'backoffice_url' => "#{@base_url}/fluxos/#{order['id']}"
    }
  end

  def present_payment(payment)
    {
      'status' => payment['status'],
      'amount_cents' => payment['amount_cents'] || payment['amountCents'],
      'method' => payment['method'],
      'installments' => payment['installments'],
      'refunds' => Array(payment['refunds']).map do |refund|
        refund.slice('status', 'amount_cents', 'reason', 'created_at')
      end
    }
  end

  def present_return(order_return)
    order_return.slice('status', 'reason', 'requested_at', 'resolved_at')
  end

  def present_shipment(shipment)
    {
      'provider' => shipment['provider'],
      'service' => shipment['service'],
      'tracking_code' => shipment['tracking_code'] || shipment['trackingCode'],
      'status' => shipment['status'],
      'estimated_delivery_days' => shipment['estimated_delivery_days'] || shipment['estimatedDeliveryDays'],
      'updated_at' => shipment['updated_at'] || shipment['updatedAt']
    }
  end

  def present_loyalty(loyalty)
    return nil unless loyalty.is_a?(Hash)

    loyalty.slice('points_balance', 'member', 'membership_status', 'joined_at', 'recent_activity', 'redemption')
  end

  def present_product(product)
    product.slice('id', 'name', 'slug', 'description', 'status', 'currency', 'sku', 'url').merge(
      'base_price_cents' => product['base_price_cents'] || product['basePriceCents'],
      'club_price_cents' => product['base_club_price_cents'] || product['baseClubPriceCents'],
      'brand' => product['brand']&.slice('name', 'slug'),
      'category' => product['category']&.slice('name', 'slug'),
      'images' => Array(product['images']).map { |image| image.slice('url', 'alt', 'isPrimary', 'is_primary') },
      'variants' => Array(product['variants']).map do |variant|
        variant.slice('id', 'name', 'sku', 'stock', 'active').merge(
          'price_cents' => variant['price_cents'] || variant['priceCents'],
          'offer_price_cents' => variant['offer_price_cents'] || variant['offerPriceCents'] || variant['price_cents'] || variant['priceCents'],
          'club_price_cents' => variant['club_price_cents'] || variant['clubPriceCents'],
          'promotion' => variant['promotion'],
          'attributes' => Array(variant['attributes']).map do |attribute|
            {
              'name' => attribute['name'],
              'value' => attribute['value'],
              'color_hex' => attribute['color_hex'] || attribute['colorHex']
            }
          end,
          'images' => Array(variant['images']).map { |image| image.slice('url', 'alt', 'position') }
        )
      end
    )
  end

  def present_available_coupon(coupon)
    return unless coupon['active']
    return if coupon['usageLimit'] && coupon['usedCount'].to_i >= coupon['usageLimit'].to_i
    return if coupon['startsAt'].present? && Time.iso8601(coupon['startsAt']) > Time.current
    return if coupon['expiresAt'].present? && Time.iso8601(coupon['expiresAt']) <= Time.current

    {
      'code' => coupon['code'],
      'discount_type' => coupon['discountType'] || coupon['discount_type'],
      'value' => coupon['value'],
      'minimum_order_cents' => coupon['minOrderCents'] || coupon['min_order_cents'],
      'maximum_discount_cents' => coupon['maxDiscountCents'] || coupon['max_discount_cents'],
      'expires_at' => coupon['expiresAt'] || coupon['expires_at'],
      'staff_only' => coupon['staffOnly'] || coupon['staff_only'],
      'description' => coupon['description']
    }
  rescue ArgumentError
    nil
  end

  def present_available_combo(combo)
    return unless combo['active']
    return if combo['usageLimit'] && combo['usedCount'].to_i >= combo['usageLimit'].to_i
    return if combo['startsAt'].present? && Time.iso8601(combo['startsAt']) > Time.current
    return if combo['endsAt'].present? && Time.iso8601(combo['endsAt']) <= Time.current

    {
      'id' => combo['id'],
      'name' => combo['name'],
      'description' => combo['description'],
      'discount_type' => combo['discountType'],
      'discount_value' => combo['discountValue'],
      'items' => Array(combo['items']).filter_map do |item|
        product = item['product']
        next unless product.is_a?(Hash)

        {
          'required_quantity' => item['requiredQuantity'] || 1,
          'variant_id' => item['variantId'],
          'product' => present_product(product)
        }
      end
    }
  rescue ArgumentError
    nil
  end
end

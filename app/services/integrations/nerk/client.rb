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

  def products(query:)
    response = get('/api/v1/products', query: query, status: 'active', limit: 10)
    Array(response['data']).map { |product| present_product(product) }
  end

  def promotions
    data = get('/api/v1/promotions')['data']
    return [] unless data.is_a?(Hash)

    Array(data['coupons']).filter_map { |coupon| present_available_coupon(coupon) }
  end

  private

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
      validate_content_type: false
    ) { |result| response_body = result.tempfile.read }

    JSON.parse(response_body)
  rescue JSON::ParserError
    raise ApiError, 'NERK API returned invalid JSON'
  rescue SafeFetch::HttpError => e
    if e.message.start_with?('409 ')
      raise IdentityVerificationRequired,
            'This social contact is synchronized, but must be linked to a verified NERK customer before orders can be displayed.'
    end

    raise ApiError, "NERK API request failed: #{e.message}"
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

  def present_context(data)
    commerce = data['commerce'].is_a?(Hash) ? data['commerce'] : {}
    customer = data['customer'].is_a?(Hash) ? data['customer'] : nil
    {
      'identity_match' => data['identity_match'],
      'customer' => customer&.slice(
        'id', 'name', 'company_name', 'trade_name', 'city', 'bio',
        'country_code', 'social_profiles', 'lead_score', 'lifetime_value_cents'
      ),
      'commerce' => {
        'orders' => Array(commerce['orders']).map { |order| present_order(order) },
        'loyalty' => present_loyalty(commerce['loyalty']),
        'wallet' => commerce['wallet']&.slice('balance_cents')
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
      'updated_at' => order['updated_at'] || order['updatedAt']
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

    loyalty.slice('points_balance', 'member', 'membership_status', 'joined_at')
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
          'club_price_cents' => variant['club_price_cents'] || variant['clubPriceCents']
        )
      end
    )
  end

  def present_available_coupon(coupon)
    return unless coupon['active']
    return if coupon['staffOnly'] || coupon['staff_only']
    return if coupon['usageLimit'] && coupon['usedCount'].to_i >= coupon['usageLimit'].to_i
    return if coupon['startsAt'].present? && Time.iso8601(coupon['startsAt']) > Time.current
    return if coupon['expiresAt'].present? && Time.iso8601(coupon['expiresAt']) <= Time.current

    {
      'code' => coupon['code'],
      'discount_type' => coupon['discountType'] || coupon['discount_type'],
      'value' => coupon['value'],
      'minimum_order_cents' => coupon['minOrderCents'] || coupon['min_order_cents'],
      'maximum_discount_cents' => coupon['maxDiscountCents'] || coupon['max_discount_cents'],
      'expires_at' => coupon['expiresAt'] || coupon['expires_at']
    }
  rescue ArgumentError
    nil
  end
end

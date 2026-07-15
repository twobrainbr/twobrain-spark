class Integrations::Nerk::Client
  include HTTParty

  class ApiError < StandardError; end

  def initialize(base_url:, access_token:)
    @base_url = base_url.chomp('/')
    @access_token = access_token
  end

  def validate!
    get('/api/v1/products', limit: 1)
    true
  end

  def orders(email:, phone:)
    customer_id = customer_id_for_phone(phone) if email.blank? && phone.present?
    return [] if email.blank? && customer_id.blank?

    response = get('/api/v1/orders', {
                     customer_email: email.presence,
                     customer_id: customer_id,
                     limit: 10
                   }.compact)
    Array(response['data']).map { |order| present_order(order) }
  end

  def products(query:)
    response = get('/api/v1/products', query: query, status: 'active', limit: 10)
    Array(response['data']).map { |product| present_product(product) }
  end

  def tracking(order_id:)
    get("/api/v1/orders/#{ERB::Util.url_encode(order_id.to_s)}/tracking")['data']
  end

  private

  def customer_id_for_phone(phone)
    response = get('/api/v1/customers', phone: phone, limit: 1)
    Array(response['data']).first&.fetch('id', nil)
  end

  def get(path, query = {})
    response = self.class.get(
      "#{@base_url}#{path}",
      query: query,
      headers: {
        'Accept' => 'application/json',
        'Authorization' => "Bearer #{@access_token}"
      },
      timeout: 10
    )
    return response.parsed_response if response.success? && response.parsed_response.is_a?(Hash)

    message = response.parsed_response.dig('error', 'message') if response.parsed_response.is_a?(Hash)
    raise ApiError, message.presence || "NERK API returned HTTP #{response.code}"
  rescue Net::OpenTimeout, Net::ReadTimeout, SocketError => e
    raise ApiError, "NERK API connection failed: #{e.message}"
  end

  def present_order(order)
    order.slice(
      'id', 'orderNumber', 'status', 'paymentStatus', 'subtotalCents',
      'discountCents', 'shippingCents', 'totalCents', 'currency',
      'shippingPromisedAt', 'createdAt'
    ).merge(
      'items' => Array(order['items']).map do |item|
        item.slice('id', 'productId', 'variantId', 'name', 'sku', 'unitPriceCents', 'quantity', 'totalCents')
      end,
      'shipments' => Array(order['shipments']).map do |shipment|
        shipment.slice('id', 'provider', 'service', 'trackingCode', 'status', 'estimatedDeliveryDays', 'createdAt', 'updatedAt')
      end
    )
  end

  def present_product(product)
    product.slice(
      'id', 'shortId', 'name', 'slug', 'description', 'status', 'basePriceCents',
      'baseClubPriceCents', 'compareAtPriceCents', 'currency', 'sku', 'attributes', 'url'
    ).merge(
      'brand' => product['brand']&.slice('name', 'slug'),
      'category' => product['category']&.slice('name', 'slug'),
      'images' => Array(product['images']).map { |image| image.slice('url', 'alt', 'isPrimary') },
      'variants' => Array(product['variants']).map do |variant|
        variant.slice('id', 'name', 'sku', 'priceCents', 'clubPriceCents', 'compareAtPriceCents', 'stock', 'options', 'active')
      end
    )
  end
end

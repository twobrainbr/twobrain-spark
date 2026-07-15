class Captain::Tools::NerkProductSearchService < Captain::Tools::NerkBaseService
  description 'Search the live NERK catalog for products, prices, variants and availability.'
  param :query, desc: 'Product name, SKU, category or attribute', required: true

  def execute(query:)
    products = nerk_client.products(query: query)
    return 'No active NERK products matched the search.' if products.empty?

    JSON.pretty_generate(products)
  rescue Integrations::Nerk::Client::ApiError => e
    "NERK product lookup failed: #{e.message}"
  end
end

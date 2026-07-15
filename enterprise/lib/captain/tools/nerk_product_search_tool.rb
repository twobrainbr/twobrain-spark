class Captain::Tools::NerkProductSearchTool < Captain::Tools::NerkBaseTool
  description 'Search the live NERK catalog for products, prices, variants and availability.'
  param :query, type: 'string', desc: 'Product name, SKU, category or attribute to search for'

  def perform(_tool_context, query:)
    products = nerk_client.products(query: query)
    return 'No active NERK products matched the search.' if products.empty?

    JSON.pretty_generate(products)
  rescue Integrations::Nerk::Client::ApiError => e
    "NERK product lookup failed: #{e.message}"
  end
end

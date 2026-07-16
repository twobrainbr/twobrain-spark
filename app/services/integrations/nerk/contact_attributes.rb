class Integrations::Nerk::ContactAttributes
  DEFINITIONS = [
    { attribute_key: 'nerk_person_type', attribute_display_name: 'Tipo de pessoa', attribute_display_type: 'list',
      attribute_values: %w[pf pj] },
    { attribute_key: 'nerk_document', attribute_display_name: 'CPF/CNPJ', attribute_display_type: 'text' },
    { attribute_key: 'nerk_company_name', attribute_display_name: 'Razão social', attribute_display_type: 'text' },
    { attribute_key: 'nerk_trade_name', attribute_display_name: 'Nome fantasia', attribute_display_type: 'text' },
    { attribute_key: 'nerk_customer_id', attribute_display_name: 'ID do cliente NERK', attribute_display_type: 'text' }
  ].freeze

  def self.ensure_for(account)
    DEFINITIONS.each do |definition|
      attribute = account.custom_attribute_definitions.find_or_initialize_by(
        attribute_key: definition[:attribute_key],
        attribute_model: 'contact_attribute'
      )
      attribute.assign_attributes(definition)
      attribute.save! if attribute.changed?
    end
  end
end

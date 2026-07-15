module Llm::ApiKey
  def self.current
    InstallationConfig.find_by(name: 'CAPTAIN_OPEN_AI_API_KEY')&.value.presence || ENV.fetch('OPENAI_API_KEY', nil)
  end
end

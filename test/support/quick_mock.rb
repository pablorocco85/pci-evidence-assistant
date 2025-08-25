# Mock Quick module for testing
module Quick
  class Config
    attr_accessor :base_url, :fallback_url, :auth_token, :timeout, :open_timeout, :max_retries, :retry_interval
  end

  class << self
    attr_reader :config

    def ai
      @ai ||= AI.new
    end

    def configure
      @config ||= Config.new
      yield @config if block_given?
      true
    end
  end

  class AI
    def chat(messages, options = {})
      {
        'choices' => [
          {
            'message' => {
              'content' => messages.is_a?(String) ? messages : messages.to_json
            }
          }
        ]
      }
    end

    def ask(question, options = {})
      'Mocked response'
    end
  end
end

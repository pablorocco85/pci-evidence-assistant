require 'net/http'
require 'json'
require 'uri'
require 'yaml'

module PCIEvidence
  module AI
    class ShopifyAIClient
      class Error < StandardError; end

      def initialize(logger: nil)
        @logger = logger || Logger.new($stdout)
        load_config
      end

      def generate_response(prompt, context = nil)
        validate_configuration!
        
        uri = URI.parse("#{@base_url}/v1/chat/completions")
        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = uri.scheme == 'https'

        messages = build_messages(prompt, context)
        
        request = Net::HTTP::Post.new(uri.path)
        request['Content-Type'] = 'application/json'
        # The proxy will handle authentication
        request.body = {
          model: @model,
          messages: messages,
          temperature: @temperature,
          max_tokens: @max_tokens
        }.to_json

        @logger.info("Sending request to AI service")
        response = http.request(request)

        handle_response(response)
      rescue StandardError => e
        @logger.error("AI request failed: #{e.message}")
        raise Error, "AI request failed: #{e.message}"
      end

      private

      def load_config
        config_path = File.join('config', 'settings.yml')
        unless File.exist?(config_path)
          config_path = File.join('config', 'settings.yml.example')
        end
        
        config = YAML.load_file(config_path)
        @base_url = config.dig('ai', 'base_url')
        @model = config.dig('ai', 'model')
        @temperature = config.dig('ai', 'temperature')
        @max_tokens = config.dig('ai', 'max_tokens')
      end

      def validate_configuration!
        missing = []
        missing << 'base_url' unless @base_url
        missing << 'model' unless @model
        missing << 'temperature' unless @temperature
        missing << 'max_tokens' unless @max_tokens

        if missing.any?
          raise Error, "Missing configuration: #{missing.join(', ')}"
        end
      end

      def build_messages(prompt, context)
        messages = []
        
        if context
          messages << {
            role: "system",
            content: context
          }
        end

        messages << {
          role: "user",
          content: prompt
        }

        messages
      end

      def handle_response(response)
        unless response.is_a?(Net::HTTPSuccess)
          @logger.error("AI service error: #{response.code} - #{response.body}")
          raise Error, "AI service error: #{response.code}"
        end

        result = JSON.parse(response.body)
        result.dig('choices', 0, 'message', 'content')
      rescue JSON::ParserError => e
        @logger.error("Failed to parse AI response: #{e.message}")
        raise Error, "Failed to parse AI response"
      end
    end
  end
end

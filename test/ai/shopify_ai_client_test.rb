require_relative '../test_helper'
require 'ai/shopify_ai_client'

module PCIEvidence
  module AI
    class ShopifyAIClientTest < Minitest::Test
      def setup
        @client = ShopifyAIClient.new(logger: TestLogger.new)
      end

      def test_configuration_loading
        # This will use settings.yml.example
        assert @client
      end

      def test_message_building
        prompt = "What is PCI DSS?"
        context = "You are a PCI DSS expert."
        
        messages = @client.send(:build_messages, prompt, context)
        
        assert_equal 2, messages.size
        assert_equal "system", messages[0][:role]
        assert_equal context, messages[0][:content]
        assert_equal "user", messages[1][:role]
        assert_equal prompt, messages[1][:content]
      end

      def test_validation
        client = ShopifyAIClient.new(logger: TestLogger.new)
        client.instance_variable_set(:@base_url, nil)
        
        assert_raises(ShopifyAIClient::Error) do
          client.send(:validate_configuration!)
        end
      end
    end
  end
end

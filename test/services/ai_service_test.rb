require_relative '../test_helper'
require 'services/ai_service'

module PCIEvidence
  module Services
    class AIServiceTest < Minitest::Test
      def setup
        @service = AIService.new(logger: nil)  # Disable logging for tests
        @mock_requirement = {
          id: "1.2.3",
          title: "Configure firewall rules",
          defined_approach_text: "Configure firewall rules to protect cardholder data",
          testing_procedures: [
            { id: "1.2.3.a", text: "Examine firewall configurations" },
            { id: "1.2.3.b", text: "Interview responsible personnel" }
          ]
        }
        @mock_evidence = "Firewall rules are configured according to policy. All inbound traffic is blocked by default. Changes are documented and reviewed monthly."
      end

      def test_analyze_evidence
        # Mock Quick.ai response
        Quick.stubs(:ai).returns(mock_quick_ai)
        
        result = @service.analyze_evidence(@mock_evidence, @mock_requirement)
        
        assert_kind_of Hash, result
        assert_includes result.keys, :analysis
        assert_includes result.keys, :timestamp
        assert_includes result.keys, :model_used
        assert_equal AIService::DEFAULT_MODEL, result[:model_used]
      end

      def test_extract_requirements_from_evidence
        Quick.stubs(:ai).returns(mock_quick_ai)
        
        result = @service.extract_requirements_from_evidence(@mock_evidence)
        
        assert_kind_of Hash, result
        assert_includes result.keys, :extracted_requirements
        assert_includes result.keys, :timestamp
        assert_includes result.keys, :model_used
      end

      def test_suggest_evidence_improvements
        Quick.stubs(:ai).returns(mock_quick_ai)
        
        result = @service.suggest_evidence_improvements(@mock_evidence, @mock_requirement)
        
        assert_kind_of Hash, result
        assert_includes result.keys, :suggestions
        assert_includes result.keys, :timestamp
        assert_includes result.keys, :model_used
      end

      def test_model_switching
        alternative_service = AIService.new(model: AIService::ALTERNATIVE_MODEL)
        Quick.stubs(:ai).returns(mock_quick_ai)
        
        result = alternative_service.analyze_evidence(@mock_evidence, @mock_requirement)
        assert_equal AIService::ALTERNATIVE_MODEL, result[:model_used]
      end

      def test_error_handling
        Quick.stubs(:ai).raises(StandardError.new("API Error"))
        
        assert_raises(StandardError) do
          @service.analyze_evidence(@mock_evidence, @mock_requirement)
        end
      end

      private

      def mock_quick_ai
        mock = mock('quick_ai')
        mock.stubs(:chat).returns("Mocked AI response")
        mock
      end
    end
  end
end

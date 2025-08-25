require_relative '../test_helper'
require 'services/ai_service'

module PCIEvidence
  module Services
    class AIServiceValidationTest < Minitest::Test
      def setup
        # Mock Quick AI
        @mock_quick = mock('quick')
        @mock_quick.stubs(:configure).returns(true)
        @mock_quick.stubs(:chat).returns(mock_ai_response({}))
        @mock_quick.stubs(:ask).returns("Mocked response")
        
        Quick.stubs(:ai).returns(@mock_quick)
        
        @service = AIService.new(logger: nil)  # Disable logging for tests
      end

      # Evidence Analysis Tests
      def test_valid_evidence_analysis_response
        response = mock_ai_response({
          'completeness' => 85,
          'relevance' => 'high',
          'gaps' => ['Missing audit logs', 'No review dates'],
          'recommendations' => ['Add audit log evidence', 'Include review timeline'],
          'confidence_score' => 90,
          'references' => ['PCI DSS v4.0', 'Requirement 1.2.3'],
          'uncertainty_flags' => ['Unclear review frequency']
        })

        # Should not raise any validation errors
        assert @service.send(:validate_response, response, :evidence_analysis)
      end

      def test_invalid_evidence_analysis_response
        response = mock_ai_response({
          'completeness' => 'invalid',  # Should be number or high/medium/low
          'relevance' => 'unknown',     # Invalid value
          'gaps' => [],                 # Empty array
          'recommendations' => nil      # Missing required field
        })

        assert_raises(AIService::ValidationError) do
          @service.send(:validate_response, response, :evidence_analysis)
        end
      end

      # Uncertain Response Tests
      def test_valid_uncertain_response
        response = mock_ai_response({
          'confidence_level' => 45,
          'draft_response' => 'Potential match with requirement 1.2.3',
          'uncertainty_reasons' => ['Ambiguous evidence', 'Multiple interpretations possible'],
          'verification_needed' => ['Confirm audit frequency', 'Verify tool versions'],
          'alternative_approaches' => ['Check system logs', 'Review change management'],
          'expert_consultation' => true,
          'data_gaps' => ['Missing implementation dates']
        })

        assert @service.send(:validate_response, response, :uncertain_response)
      end

      def test_invalid_uncertain_response
        response = mock_ai_response({
          'confidence_level' => 'low',  # Should be number
          'draft_response' => '',       # Empty string
          'uncertainty_reasons' => [],   # Empty array
          'verification_needed' => nil   # Missing required field
        })

        assert_raises(AIService::ValidationError) do
          @service.send(:validate_response, response, :uncertain_response)
        end
      end

      # Guidance Response Tests
      def test_valid_guidance_response
        response = mock_ai_response({
          'recommendation_type' => 'technical',
          'primary_guidance' => 'Implement automated log review',
          'rationale' => 'Current manual process is error-prone',
          'next_steps' => ['Select log aggregation tool', 'Define review criteria'],
          'alternative_options' => ['Enhanced manual process', 'Outsourced review'],
          'prerequisites' => ['Tool budget', 'Staff training'],
          'risks' => ['Learning curve', 'Initial false positives'],
          'timeline_estimate' => '3 months'
        })

        assert @service.send(:validate_response, response, :guidance_response)
      end

      # Requirement Extraction Tests
      def test_valid_requirement_extraction
        response = mock_ai_response({
          'requirement_id' => '1.2.3',
          'requirement_text' => 'Configure firewall rules',
          'evidence_match' => 'high',
          'justification' => 'Evidence shows detailed firewall configuration',
          'related_requirements' => ['1.2.4', '1.2.5'],
          'testing_procedures' => ['1.2.3.a', '1.2.3.b']
        })

        assert @service.send(:validate_response, response, :requirement_extraction)
      end

      def test_invalid_requirement_extraction
        response = mock_ai_response({
          'requirement_id' => 'invalid-id',  # Should be in PCI format
          'requirement_text' => '',          # Empty text
          'evidence_match' => 'unknown',     # Invalid match level
          'justification' => nil            # Missing justification
        })

        assert_raises(AIService::ValidationError) do
          @service.send(:validate_response, response, :requirement_extraction)
        end
      end

      # Interview Evidence Tests
      def test_valid_interview_evidence
        response = mock_ai_response({
          'interview_focus' => 'Firewall change process',
          'key_points' => ['Approval workflow', 'Documentation requirements'],
          'expected_evidence' => 'Change management documentation',
          'suggested_questions' => ['Who approves changes?', 'How are changes logged?'],
          'documentation_needs' => ['Change request forms', 'Approval records']
        })

        assert @service.send(:validate_response, response, :interview_evidence)
      end

      def test_invalid_interview_evidence
        response = mock_ai_response({
          'interview_focus' => '',  # Empty focus
          'key_points' => [],      # Empty array
          'expected_evidence' => nil  # Missing evidence
        })

        assert_raises(AIService::ValidationError) do
          @service.send(:validate_response, response, :interview_evidence)
        end
      end

      # GCP Evidence Tests
      def test_valid_gcp_evidence
        response = mock_ai_response({
          'resource_type' => 'firewall-rules',
          'control_mapping' => 'Requirement 1.2.3',
          'configuration' => 'Default deny with explicit allows',
          'validation_steps' => ['Review rules list', 'Verify default deny'],
          'audit_logs' => ['Config changes', 'Rule updates'],
          'monitoring_needs' => ['Rule change alerts', 'Violation notifications']
        })

        assert @service.send(:validate_response, response, :gcp_evidence)
      end

      def test_invalid_gcp_evidence
        response = mock_ai_response({
          'resource_type' => '',  # Empty type
          'control_mapping' => nil,  # Missing mapping
          'configuration' => [],  # Wrong type (should be string)
          'validation_steps' => 'step'  # Wrong type (should be array)
        })

        assert_raises(AIService::ValidationError) do
          @service.send(:validate_response, response, :gcp_evidence)
        end
      end

      def test_invalid_guidance_response
        response = mock_ai_response({
          'recommendation_type' => 'invalid_type',  # Invalid type
          'primary_guidance' => '',                 # Empty string
          'rationale' => nil,                      # Missing required field
          'next_steps' => []                       # Empty array
        })

        assert_raises(AIService::ValidationError) do
          @service.send(:validate_response, response, :guidance_response)
        end
      end

      # Field Validation Tests
      def test_completeness_field_validation
        valid_values = [85, "75%", "high", "medium", "low"]
        invalid_values = ["invalid", 101, -1, "unknown"]

        valid_values.each do |value|
          assert valid_completeness?(value), "#{value} should be valid completeness"
        end

        invalid_values.each do |value|
          refute valid_completeness?(value), "#{value} should be invalid completeness"
        end
      end

      def test_array_field_validation
        response = mock_ai_response({
          'completeness' => 85,  # Required field
          'relevance' => 'high', # Required field
          'gaps' => ['', nil, '  ', 'Valid Gap'],  # Contains invalid elements
          'recommendations' => ['Valid recommendation']  # Required field
        })

        # Should raise validation error for invalid array elements
        error = assert_raises(AIService::ValidationError) do
          @service.send(:validate_response, response, :evidence_analysis)
        end
        assert_match(/Validation failed for field 'gaps'/, error.message)
      end

      def test_array_field_warnings
        response = mock_ai_response({
          'completeness' => 85,
          'relevance' => 'high',
          'gaps' => ['Valid Gap 1', 'Valid Gap 2'],
          'recommendations' => []  # Empty array should trigger warning
        })

        # Create a StringIO to capture logger output
        log_output = StringIO.new
        logger = Logger.new(log_output)
        service = AIService.new(logger: logger)

        # Should log warning but not raise error
        service.send(:validate_response, response, :evidence_analysis)
        assert_match(/Empty array found for field: recommendations/, log_output.string)
      end

      # Edge Cases
      def test_handles_nil_response
        assert_raises(AIService::ValidationError) do
          @service.send(:validate_response, nil, :evidence_analysis)
        end
      end

      def test_handles_empty_response
        assert_raises(AIService::ValidationError) do
          @service.send(:validate_response, {}, :evidence_analysis)
        end
      end

      def test_handles_invalid_json
        response = mock_ai_response("Not a JSON string")
        
        # Create a StringIO to capture logger output
        log_output = StringIO.new
        logger = Logger.new(log_output)
        service = AIService.new(logger: logger)

        # Should log warning and return response without validation
        result = service.send(:validate_response, response, :evidence_analysis)
        assert result, "Should return response even with invalid JSON"
        assert_match(/Response content is not JSON/, log_output.string)
      end

      private

      def mock_ai_response(content)
        {
          'choices' => [
            {
              'message' => {
                'content' => content.is_a?(String) ? content : content.to_json
              }
            }
          ]
        }
      end

      def valid_completeness?(value)
        validator = AIService::RESPONSE_SCHEMAS[:evidence_analysis][:field_validations]['completeness']
        validator.call(value)
      rescue
        false
      end
    end
  end
end

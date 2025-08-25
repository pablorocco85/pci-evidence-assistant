require 'test_helper'
require 'services/evidence_analysis_engine'

module PCIEvidence
  module Services
    class EvidenceAnalysisEngineTest < Minitest::Test
      def setup
        @ai_service = mock
        @logger = mock
        @engine = EvidenceAnalysisEngine.new(ai_service: @ai_service, logger: @logger)
        @requirement = mock_requirement
      end

      def test_analyze_roc_response
        response_text = "Sample ROC response text"
        mock_ai_response = mock_analysis_response('roc_response')

        @logger.expects(:info).with("Analyzing ROC response for requirement test_req_1")
        @ai_service.expects(:analyze_evidence).with(response_text, anything).returns(mock_ai_response)

        result = @engine.analyze_roc_response(response_text, @requirement)

        assert_equal 'test_req_1', result['requirement_id']
        assert_equal 'roc_response', result['evidence_type']
        assert_equal 85, result['completeness']
        assert_equal 'high', result['relevance']
        assert_includes result['gaps'], 'Missing implementation details'
        assert_includes result['recommendations'], 'Add technical specifications'
        assert_kind_of Time, Time.parse(result['analyzed_at'])
        assert_equal 'gpt-4.1', result['model_used']
      end

      def test_analyze_github_evidence
        evidence_data = [mock_github_evidence]
        mock_ai_response = mock_analysis_response('github')

        @logger.expects(:info).with("Analyzing GitHub evidence for requirement test_req_1")
        @ai_service.expects(:analyze_evidence).with(anything, anything).returns(mock_ai_response)

        result = @engine.analyze_github_evidence(evidence_data, @requirement)

        assert_equal 'test_req_1', result['requirement_id']
        assert_equal 'github', result['evidence_type']
        assert_equal ['https://github.com/test/1'], result['evidence_sources']
        assert_equal 85, result['completeness']
        assert_equal 'high', result['relevance']
        assert_kind_of Time, Time.parse(result['analyzed_at'])
      end

      def test_analyze_gcp_evidence
        config_data = [mock_gcp_config]
        mock_ai_response = mock_analysis_response('gcp_config')

        @logger.expects(:info).with("Analyzing GCP configuration for requirement test_req_1")
        @ai_service.expects(:analyze_evidence).with(anything, anything).returns(mock_ai_response)

        result = @engine.analyze_gcp_evidence(config_data, @requirement)

        assert_equal 'test_req_1', result['requirement_id']
        assert_equal 'gcp_config', result['evidence_type']
        assert_equal ['firewall'], result['resource_types']
        assert_equal 85, result['completeness']
        assert_equal 'high', result['relevance']
        assert_kind_of Time, Time.parse(result['analyzed_at'])
      end

      def test_combine_evidence_analysis
        analyses = [
          mock_analysis_result('roc_response'),
          mock_analysis_result('github'),
          mock_analysis_result('gcp_config')
        ]

        mock_synthesis = {
          'choices' => [{
            'message' => {
              'content' => JSON.generate({
                'overall_completeness' => 90,
                'overall_confidence' => 85,
                'evidence_quality' => {
                  'roc_response' => 'strong',
                  'github' => 'moderate',
                  'gcp_config' => 'strong'
                },
                'combined_gaps' => ['Missing audit logs', 'Incomplete documentation'],
                'combined_recommendations' => ['Enable comprehensive logging', 'Update documentation'],
                'evidence_conflicts' => ['Configuration mismatch between ROC and actual setup'],
                'additional_evidence_needed' => ['Recent compliance scan results'],
                'compliance_status' => 'partially_compliant',
                'next_steps' => ['Review audit log configuration', 'Update documentation']
              })
            }
          }],
          model_used: 'gpt-4.1'
        }

        @logger.expects(:info).with("Combining evidence analyses for requirement test_req_1")
        @ai_service.expects(:make_ai_request).with(:chat, anything).returns(mock_synthesis)

        result = @engine.combine_evidence_analysis(analyses, @requirement)

        assert_equal 'test_req_1', result['requirement_id']
        assert_equal 3, result['evidence_count']
        assert_equal ['roc_response', 'github', 'gcp_config'], result['evidence_types']
        assert_equal 90, result['overall_completeness']
        assert_equal 85, result['overall_confidence']
        assert_equal 'partially_compliant', result['compliance_status']
        assert Time.parse(result['synthesized_at'])
      end

      private

      def mock_requirement
        requirement = mock
        requirement.stubs(:id).returns('test_req_1')
        requirement.stubs(:title).returns('Test Requirement')
        requirement.stubs(:defined_approach_text).returns('Test approach text')
        requirement.stubs(:customized_approach_objective).returns('Test objective')
        requirement.stubs(:testing_procedures).returns([mock_testing_procedure])
        requirement.stubs(:guidance).returns(mock_guidance)
        requirement
      end

      def mock_testing_procedure
        proc = mock
        proc.stubs(:id).returns('test_proc_1')
        proc.stubs(:text).returns('Test procedure text')
        proc.stubs(:sub_procedures).returns(['Sub-procedure 1', 'Sub-procedure 2'])
        proc
      end

      def mock_guidance
        guidance = mock
        guidance.stubs(:purpose).returns('Test purpose')
        guidance.stubs(:good_practices).returns(['Practice 1', 'Practice 2'])
        guidance.stubs(:examples).returns(['Example 1', 'Example 2'])
        guidance.stubs(:definitions).returns(['Definition 1', 'Definition 2'])
        guidance.stubs(:further_information).returns('Further info')
        guidance
      end

      def mock_github_evidence
        {
          type: 'pull_request',
          url: 'https://github.com/test/1',
          title: 'Test PR',
          description: 'Test description',
          created_at: Time.now.utc,
          updated_at: Time.now.utc,
          labels: ['security', 'pci'],
          status: 'merged',
          content: 'Test content',
          comments: [{
            author: 'test_user',
            date: Time.now.utc,
            content: 'Test comment'
          }],
          changes: [{
            file: 'test.rb',
            type: 'modified',
            before: 'old code',
            after: 'new code'
          }]
        }
      end

      def mock_gcp_config
        {
          resource_type: 'firewall',
          name: 'test-firewall',
          project: 'test-project',
          location: 'us-central1',
          configuration: {
            allowed: ['tcp:80,443'],
            denied: ['tcp:22'],
            direction: 'INGRESS'
          },
          iam_policies: [{
            role: 'roles/compute.securityAdmin',
            members: ['user:test@example.com'],
            conditions: 'None'
          }],
          audit_logs: [{
            type: 'DATA_WRITE',
            enabled: true,
            retention: '30 days',
            filters: 'resource.type=firewall'
          }],
          monitoring: [{
            type: 'uptime',
            metric: 'compute.firewall.uptime',
            threshold: '99.9%',
            alert_config: 'email'
          }]
        }
      end

      def mock_analysis_response(evidence_type)
        {
          analysis: {
            'choices' => [{
              'message' => {
                'content' => JSON.generate({
                  'completeness' => 85,
                  'relevance' => 'high',
                  'gaps' => ['Missing implementation details'],
                  'recommendations' => ['Add technical specifications'],
                  'confidence_score' => 90,
                  'references' => ['PCI DSS v4.0'],
                  'uncertainty_flags' => []
                })
              }
            }]
          },
          model_used: 'gpt-4.1'
        }
      end

      def mock_analysis_result(evidence_type)
        {
          'requirement_id' => 'test_req_1',
          'evidence_type' => evidence_type,
          'completeness' => 85,
          'relevance' => 'high',
          'gaps' => ['Missing implementation details'],
          'recommendations' => ['Add technical specifications'],
          'confidence_score' => 90,
          'references' => ['PCI DSS v4.0'],
          'uncertainty_flags' => [],
          'analyzed_at' => Time.now.utc.iso8601,
          'model_used' => 'gpt-4.1'
        }
      end
    end
  end
end

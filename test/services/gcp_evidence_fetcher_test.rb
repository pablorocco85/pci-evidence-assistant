require 'test_helper'
require 'services/gcp_evidence_fetcher'

module PCIEvidence
  module Services
    class GCPEvidenceFetcherTest < Minitest::Test
      def setup
        @logger = mock
        @fetcher = GCPEvidenceFetcher.new(logger: @logger)
        @requirement_id = '1.2.3'
      end

      def test_fetch_gcp_evidence
        # Set up logger expectations in sequence
        logger_sequence = sequence('logger_sequence')
        @logger.expects(:info).with("Fetching GCP evidence for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:info).with("Fetching firewall rules for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:info).with("Fetching IAM policies for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:info).with("Fetching audit logs for requirement #{@requirement_id}").in_sequence(logger_sequence)

        # Mock firewall rules response
        firewall_rules_json = JSON.generate([{
          name: 'test-rule',
          network: 'test-network',
          direction: 'INGRESS',
          priority: 1000,
          sourceRanges: ['0.0.0.0/0'],
          targetTags: ['web'],
          allowed: [{ IPProtocol: 'tcp', ports: ['80', '443'] }],
          denied: [],
          description: 'Test rule',
          createdAt: '2024-01-01T00:00:00Z',
          updatedAt: '2024-01-02T00:00:00Z'
        }])

        # Mock IAM policies response
        iam_policies_json = JSON.generate([{
          role: 'roles/compute.admin',
          members: ['user:test@example.com'],
          condition: nil,
          etag: 'test-etag'
        }])

        # Mock audit logs response
        audit_logs_json = JSON.generate([{
          timestamp: '2024-01-01T00:00:00Z',
          resource: { type: 'gce_firewall_rule' },
          methodName: 'compute.firewalls.patch',
          callerIp: '1.2.3.4',
          principalEmail: 'test@example.com',
          request: { name: 'test-rule' },
          response: { status: 'SUCCESS' },
          status: { code: 0 }
        }])

        # Mock successful MCP server responses
        http = mock('http')
        Net::HTTP.expects(:new).with('localhost', 9292).returns(http).times(3)

        # Mock firewall rules response
        firewall_response = mock_http_response(200, { result: firewall_rules_json }.to_json)
        http.expects(:post).with('/mcp', regexp_matches(/tools\.firewall_rules/), has_entry('Content-Type', 'application/json'))
            .returns(firewall_response)

        # Mock IAM policies response
        iam_response = mock_http_response(200, { result: iam_policies_json }.to_json)
        http.expects(:post).with('/mcp', regexp_matches(/tools\.iam_policies/), has_entry('Content-Type', 'application/json'))
            .returns(iam_response)

        # Mock audit logs response
        audit_response = mock_http_response(200, { result: audit_logs_json }.to_json)
        http.expects(:post).with('/mcp', regexp_matches(/tools\.audit_logs/), has_entry('Content-Type', 'application/json'))
            .returns(audit_response)

        result = @fetcher.fetch_gcp_evidence(@requirement_id)

        assert_equal @requirement_id, result[:requirement_id]
        
        # Check CDE evidence
        assert_kind_of Array, result[:evidence][:cde][:firewall_rules]
        assert_kind_of Array, result[:evidence][:cde][:iam_policies]
        assert_kind_of Array, result[:evidence][:cde][:audit_logs]
        refute_empty result[:evidence][:cde][:firewall_rules]
        refute_empty result[:evidence][:cde][:iam_policies]
        refute_empty result[:evidence][:cde][:audit_logs]

        # Check PCI supporting evidence
        assert_kind_of Array, result[:evidence][:pci_supporting][:firewall_rules]
        assert_kind_of Array, result[:evidence][:pci_supporting][:iam_policies]
        assert_kind_of Array, result[:evidence][:pci_supporting][:audit_logs]
        assert_empty result[:evidence][:pci_supporting][:firewall_rules]  # Only CDE project used
        assert_empty result[:evidence][:pci_supporting][:iam_policies]    # Only CDE project used
        assert_empty result[:evidence][:pci_supporting][:audit_logs]      # Only CDE project used

        # Check metadata
        assert_kind_of String, result[:metadata][:fetched_at]
        assert Time.parse(result[:metadata][:fetched_at])
        assert_equal ['shopify-cardserver', 'shopify-vault', 'shopify-restricted'], result[:metadata][:source_projects]
        assert_equal :pci, result[:metadata][:scope][:type]
        assert_equal "PCI", result[:metadata][:scope][:name]
        assert_equal "Full PCI scope including CDE and supporting services", result[:metadata][:scope][:description]
      end

      def test_fetch_gcp_evidence_with_filters
        options = {
          projects: ['test-project'],
          filters: {
            resource_types: ['firewall-rules', 'iam-policies'],
            time_range: '24h',
            status: 'active'
          }
        }

        # Set up logger expectations in sequence
        logger_sequence = sequence('logger_sequence')
        @logger.expects(:info).with("Fetching GCP evidence for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:info).with("Fetching firewall rules for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:info).with("Fetching IAM policies for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:info).with("Fetching audit logs for requirement #{@requirement_id}").in_sequence(logger_sequence)

        # Mock successful MCP server responses
        http = mock('http')
        Net::HTTP.expects(:new).with('localhost', 9292).returns(http).times(3)

        # Mock firewall rules response
        firewall_response = mock_http_response(200, { result: '[]' }.to_json)
        http.expects(:post).with('/mcp', regexp_matches(/tools\.firewall_rules.*test-project/), has_entry('Content-Type', 'application/json'))
            .returns(firewall_response)

        # Mock IAM policies response
        iam_response = mock_http_response(200, { result: '[]' }.to_json)
        http.expects(:post).with('/mcp', regexp_matches(/tools\.iam_policies.*test-project/), has_entry('Content-Type', 'application/json'))
            .returns(iam_response)

        # Mock audit logs response
        audit_response = mock_http_response(200, { result: '[]' }.to_json)
        http.expects(:post).with('/mcp', regexp_matches(/tools\.audit_logs.*test-project/), has_entry('Content-Type', 'application/json'))
            .returns(audit_response)

        result = @fetcher.fetch_gcp_evidence(@requirement_id, options)

        assert_equal @requirement_id, result[:requirement_id]
        
        # Check CDE evidence (empty since test-project is not CDE)
        assert_empty result[:evidence][:cde][:firewall_rules]
        assert_empty result[:evidence][:cde][:iam_policies]
        assert_empty result[:evidence][:cde][:audit_logs]

        # Check PCI supporting evidence (empty since test-project is not PCI)
        assert_empty result[:evidence][:pci_supporting][:firewall_rules]
        assert_empty result[:evidence][:pci_supporting][:iam_policies]
        assert_empty result[:evidence][:pci_supporting][:audit_logs]

        # Check metadata
        assert_equal ['test-project'], result[:metadata][:source_projects]
        assert_equal options[:filters], result[:metadata][:filters_applied]
        assert_equal :pci, result[:metadata][:scope][:type]  # Default scope
      end

      def test_fetch_gcp_evidence_handles_mcp_errors
        # Set up logger expectations in sequence
        logger_sequence = sequence('logger_sequence')
        @logger.expects(:info).with("Fetching GCP evidence for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:info).with("Fetching firewall rules for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:warn).with("Failed to fetch firewall rules from MCP server: MCP server request failed: 500 - Internal Server Error").in_sequence(logger_sequence)
        @logger.expects(:info).with("Fetching IAM policies for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:warn).with("Failed to fetch IAM policies from MCP server: MCP server request failed: 500 - Internal Server Error").in_sequence(logger_sequence)
        @logger.expects(:info).with("Fetching audit logs for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:warn).with("Failed to fetch audit logs from MCP server: MCP server request failed: 500 - Internal Server Error").in_sequence(logger_sequence)

        # Mock failed MCP server responses
        http = mock('http')
        Net::HTTP.expects(:new).with('localhost', 9292).returns(http).times(3)

        # Mock firewall rules response
        firewall_response = mock_http_response(500, { error: { message: 'MCP server request failed: 500 - Internal Server Error' } }.to_json)
        http.expects(:post).with('/mcp', regexp_matches(/tools\.firewall_rules/), has_entry('Content-Type', 'application/json'))
            .returns(firewall_response)

        # Mock IAM policies response
        iam_response = mock_http_response(500, { error: { message: 'MCP server request failed: 500 - Internal Server Error' } }.to_json)
        http.expects(:post).with('/mcp', regexp_matches(/tools\.iam_policies/), has_entry('Content-Type', 'application/json'))
            .returns(iam_response)

        # Mock audit logs response
        audit_response = mock_http_response(500, { error: { message: 'MCP server request failed: 500 - Internal Server Error' } }.to_json)
        http.expects(:post).with('/mcp', regexp_matches(/tools\.audit_logs/), has_entry('Content-Type', 'application/json'))
            .returns(audit_response)

        # Mock successful gcloud fallback responses
        gcloud_sequence = sequence('gcloud_sequence')
        
        # Mock firewall rules
        firewall_stdout = JSON.generate([{
          name: 'test-rule',
          network: 'test-network',
          direction: 'INGRESS',
          priority: 1000,
          sourceRanges: ['0.0.0.0/0'],
          targetTags: ['web'],
          allowed: [{ IPProtocol: 'tcp', ports: ['80', '443'] }],
          denied: [],
          description: 'Test rule',
          creationTimestamp: '2024-01-01T00:00:00Z'
        }])
        Open3.expects(:capture3).with('gcloud', 'compute', 'firewall-rules', 'list', '--project', 'shopify-cardserver', '--format', 'json')
             .returns([firewall_stdout, '', mock('status', success?: true)]).in_sequence(gcloud_sequence)
        Open3.expects(:capture3).with('gcloud', 'compute', 'firewall-rules', 'list', '--project', 'shopify-vault', '--format', 'json')
             .returns([firewall_stdout, '', mock('status', success?: true)]).in_sequence(gcloud_sequence)
        Open3.expects(:capture3).with('gcloud', 'compute', 'firewall-rules', 'list', '--project', 'shopify-restricted', '--format', 'json')
             .returns([firewall_stdout, '', mock('status', success?: true)]).in_sequence(gcloud_sequence)

        # Mock IAM policies
        iam_stdout = JSON.generate({
          bindings: [{
            role: 'roles/compute.admin',
            members: ['user:test@example.com']
          }]
        })
        Open3.expects(:capture3).with('gcloud', 'projects', 'get-iam-policy', 'shopify-cardserver', '--format', 'json')
             .returns([iam_stdout, '', mock('status', success?: true)]).in_sequence(gcloud_sequence)
        Open3.expects(:capture3).with('gcloud', 'projects', 'get-iam-policy', 'shopify-vault', '--format', 'json')
             .returns([iam_stdout, '', mock('status', success?: true)]).in_sequence(gcloud_sequence)
        Open3.expects(:capture3).with('gcloud', 'projects', 'get-iam-policy', 'shopify-restricted', '--format', 'json')
             .returns([iam_stdout, '', mock('status', success?: true)]).in_sequence(gcloud_sequence)

        # Mock audit logs
        audit_stdout = JSON.generate([{
          timestamp: '2024-01-01T00:00:00Z',
          resource: { type: 'gce_firewall_rule' },
          protoPayload: {
            methodName: 'compute.firewalls.patch',
            requestMetadata: { callerIp: '1.2.3.4' },
            authenticationInfo: { principalEmail: 'test@example.com' },
            request: { name: 'test-rule' },
            response: { status: 'SUCCESS' },
            status: { code: 0 }
          }
        }])
        Open3.expects(:capture3).with('gcloud', 'logging', 'read', 'resource.type=gce_firewall_rule OR resource.type=project', '--project=shopify-cardserver', '--format=json', '--limit=1000', '--freshness=24h')
             .returns([audit_stdout, '', mock('status', success?: true)]).in_sequence(gcloud_sequence)
        Open3.expects(:capture3).with('gcloud', 'logging', 'read', 'resource.type=gce_firewall_rule OR resource.type=project', '--project=shopify-vault', '--format=json', '--limit=1000', '--freshness=24h')
             .returns([audit_stdout, '', mock('status', success?: true)]).in_sequence(gcloud_sequence)
        Open3.expects(:capture3).with('gcloud', 'logging', 'read', 'resource.type=gce_firewall_rule OR resource.type=project', '--project=shopify-restricted', '--format=json', '--limit=1000', '--freshness=24h')
             .returns([audit_stdout, '', mock('status', success?: true)]).in_sequence(gcloud_sequence)

        result = @fetcher.fetch_gcp_evidence(@requirement_id)

        assert_equal @requirement_id, result[:requirement_id]
        
        # Check CDE evidence
        assert_kind_of Array, result[:evidence][:cde][:firewall_rules]
        assert_kind_of Array, result[:evidence][:cde][:iam_policies]
        assert_kind_of Array, result[:evidence][:cde][:audit_logs]
        refute_empty result[:evidence][:cde][:firewall_rules]
        refute_empty result[:evidence][:cde][:iam_policies]
        refute_empty result[:evidence][:cde][:audit_logs]

        # Check PCI supporting evidence
        assert_kind_of Array, result[:evidence][:pci_supporting][:firewall_rules]
        assert_kind_of Array, result[:evidence][:pci_supporting][:iam_policies]
        assert_kind_of Array, result[:evidence][:pci_supporting][:audit_logs]
        refute_empty result[:evidence][:pci_supporting][:firewall_rules]
        refute_empty result[:evidence][:pci_supporting][:iam_policies]
        refute_empty result[:evidence][:pci_supporting][:audit_logs]
      end

      def test_fetch_gcp_evidence_handles_all_errors
        # Set up logger expectations in sequence
        logger_sequence = sequence('logger_sequence')
        @logger.expects(:info).with("Fetching GCP evidence for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:info).with("Fetching firewall rules for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:warn).with("Failed to fetch firewall rules from MCP server: MCP server request failed: 500 - Internal Server Error").in_sequence(logger_sequence)
        @logger.expects(:error).with("Failed to fetch firewall rules from gcloud: Command failed").in_sequence(logger_sequence)
        @logger.expects(:info).with("Fetching IAM policies for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:warn).with("Failed to fetch IAM policies from MCP server: MCP server request failed: 500 - Internal Server Error").in_sequence(logger_sequence)
        @logger.expects(:error).with("Failed to fetch IAM policies from gcloud: Command failed").in_sequence(logger_sequence)
        @logger.expects(:info).with("Fetching audit logs for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:warn).with("Failed to fetch audit logs from MCP server: MCP server request failed: 500 - Internal Server Error").in_sequence(logger_sequence)
        @logger.expects(:error).with("Failed to fetch audit logs from gcloud: Command failed").in_sequence(logger_sequence)

        # Mock failed MCP server responses
        http = mock('http')
        Net::HTTP.expects(:new).with('localhost', 9292).returns(http).times(3)

        # Mock firewall rules response
        firewall_response = mock_http_response(500, { error: { message: 'MCP server request failed: 500 - Internal Server Error' } }.to_json)
        http.expects(:post).with('/mcp', regexp_matches(/tools\.firewall_rules/), has_entry('Content-Type', 'application/json'))
            .returns(firewall_response)

        # Mock IAM policies response
        iam_response = mock_http_response(500, { error: { message: 'MCP server request failed: 500 - Internal Server Error' } }.to_json)
        http.expects(:post).with('/mcp', regexp_matches(/tools\.iam_policies/), has_entry('Content-Type', 'application/json'))
            .returns(iam_response)

        # Mock audit logs response
        audit_response = mock_http_response(500, { error: { message: 'MCP server request failed: 500 - Internal Server Error' } }.to_json)
        http.expects(:post).with('/mcp', regexp_matches(/tools\.audit_logs/), has_entry('Content-Type', 'application/json'))
            .returns(audit_response)

        # Mock failed gcloud responses
        gcloud_sequence = sequence('gcloud_sequence')
        
        # Mock firewall rules failures
        Open3.expects(:capture3).with('gcloud', 'compute', 'firewall-rules', 'list', '--project', 'shopify-cardserver', '--format', 'json')
             .returns(['', 'Command failed', mock('status', success?: false)]).in_sequence(gcloud_sequence)
        Open3.expects(:capture3).with('gcloud', 'compute', 'firewall-rules', 'list', '--project', 'shopify-vault', '--format', 'json')
             .returns(['', 'Command failed', mock('status', success?: false)]).in_sequence(gcloud_sequence)
        Open3.expects(:capture3).with('gcloud', 'compute', 'firewall-rules', 'list', '--project', 'shopify-restricted', '--format', 'json')
             .returns(['', 'Command failed', mock('status', success?: false)]).in_sequence(gcloud_sequence)

        # Mock IAM policies failures
        Open3.expects(:capture3).with('gcloud', 'projects', 'get-iam-policy', 'shopify-cardserver', '--format', 'json')
             .returns(['', 'Command failed', mock('status', success?: false)]).in_sequence(gcloud_sequence)
        Open3.expects(:capture3).with('gcloud', 'projects', 'get-iam-policy', 'shopify-vault', '--format', 'json')
             .returns(['', 'Command failed', mock('status', success?: false)]).in_sequence(gcloud_sequence)
        Open3.expects(:capture3).with('gcloud', 'projects', 'get-iam-policy', 'shopify-restricted', '--format', 'json')
             .returns(['', 'Command failed', mock('status', success?: false)]).in_sequence(gcloud_sequence)

        # Mock audit logs failures
        Open3.expects(:capture3).with('gcloud', 'logging', 'read', 'resource.type=gce_firewall_rule OR resource.type=project', '--project=shopify-cardserver', '--format=json', '--limit=1000', '--freshness=24h')
             .returns(['', 'Command failed', mock('status', success?: false)]).in_sequence(gcloud_sequence)
        Open3.expects(:capture3).with('gcloud', 'logging', 'read', 'resource.type=gce_firewall_rule OR resource.type=project', '--project=shopify-vault', '--format=json', '--limit=1000', '--freshness=24h')
             .returns(['', 'Command failed', mock('status', success?: false)]).in_sequence(gcloud_sequence)
        Open3.expects(:capture3).with('gcloud', 'logging', 'read', 'resource.type=gce_firewall_rule OR resource.type=project', '--project=shopify-restricted', '--format=json', '--limit=1000', '--freshness=24h')
             .returns(['', 'Command failed', mock('status', success?: false)]).in_sequence(gcloud_sequence)

        result = @fetcher.fetch_gcp_evidence(@requirement_id)

        assert_equal @requirement_id, result[:requirement_id]
        
        # Check CDE evidence (empty due to all failures)
        assert_empty result[:evidence][:cde][:firewall_rules]
        assert_empty result[:evidence][:cde][:iam_policies]
        assert_empty result[:evidence][:cde][:audit_logs]

        # Check PCI supporting evidence (empty due to all failures)
        assert_empty result[:evidence][:pci_supporting][:firewall_rules]
        assert_empty result[:evidence][:pci_supporting][:iam_policies]
        assert_empty result[:evidence][:pci_supporting][:audit_logs]
      end

      private

      def mock_http_response(code, body)
        response = mock
        response.stubs(:code).returns(code.to_s)
        response.stubs(:message).returns(code == 200 ? 'OK' : 'Internal Server Error')
        response.stubs(:body).returns(body)
        response.stubs(:is_a?).with(Net::HTTPSuccess).returns(code == 200)
        response
      end
    end
  end
end

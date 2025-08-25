require 'test_helper'
require 'formatters/gcp_evidence_formatter'

module PCIEvidence
  module Formatters
    class GCPEvidenceFormatterTest < Minitest::Test
      def setup
        @logger = mock
        @formatter = GCPEvidenceFormatter.new(logger: @logger)
        @requirement_id = '1.2.3'
        @timestamp = '2024-01-01T00:00:00Z'
      end

      def test_format_empty_evidence
        assert_equal "", @formatter.format(nil)
        assert_equal "", @formatter.format({})
      end

      def test_format_cde_only_evidence
        evidence = {
          requirement_id: @requirement_id,
          evidence: {
            cde: {
              firewall_rules: [mock_firewall_rule],
              iam_policies: [mock_iam_policy],
              audit_logs: [mock_audit_log]
            },
            pci_supporting: {
              firewall_rules: [],
              iam_policies: [],
              audit_logs: []
            }
          },
          metadata: mock_metadata
        }

        result = @formatter.format(evidence)

        # Check main sections
        assert_match /^# GCP Evidence/, result
        assert_match /^## Metadata/, result
        assert_match /^## CDE Evidence/, result
        refute_match /^## PCI Supporting Evidence/, result

        # Check CDE evidence sections
        assert_match /^### Firewall Rules/, result
        assert_match /^### IAM Policies/, result
        assert_match /^### Audit Logs/, result

        # Check specific evidence details
        assert_match /\*\*Name:\*\* test-rule/, result
        assert_match /\*\*Role:\*\* roles\/compute.admin/, result
        assert_match /\*\*Method:\*\* compute.firewalls.patch/, result
      end

      def test_format_full_pci_evidence
        evidence = {
          requirement_id: @requirement_id,
          evidence: {
            cde: {
              firewall_rules: [mock_firewall_rule],
              iam_policies: [mock_iam_policy],
              audit_logs: [mock_audit_log]
            },
            pci_supporting: {
              firewall_rules: [mock_firewall_rule(name: 'vault-rule')],
              iam_policies: [mock_iam_policy(role: 'roles/vault.admin')],
              audit_logs: [mock_audit_log(method: 'vault.secrets.access')]
            }
          },
          metadata: mock_metadata
        }

        result = @formatter.format(evidence)

        # Check all sections present
        assert_match /^# GCP Evidence/, result
        assert_match /^## Metadata/, result
        assert_match /^## CDE Evidence/, result
        assert_match /^## PCI Supporting Evidence/, result

        # Check CDE evidence
        assert_match /\*\*Name:\*\* test-rule/, result
        assert_match /\*\*Role:\*\* roles\/compute.admin/, result
        assert_match /\*\*Method:\*\* compute.firewalls.patch/, result

        # Check PCI supporting evidence
        assert_match /\*\*Name:\*\* vault-rule/, result
        assert_match /\*\*Role:\*\* roles\/vault.admin/, result
        assert_match /\*\*Method:\*\* vault.secrets.access/, result
      end

      def test_format_with_filters
        evidence = {
          requirement_id: @requirement_id,
          evidence: {
            cde: {
              firewall_rules: [mock_firewall_rule],
              iam_policies: [],
              audit_logs: []
            },
            pci_supporting: {
              firewall_rules: [],
              iam_policies: [],
              audit_logs: []
            }
          },
          metadata: mock_metadata(filters: {
            resource_types: ['firewall-rules'],
            time_range: '24h',
            status: 'active'
          })
        }

        result = @formatter.format(evidence)

        # Check filters in metadata
        assert_match /\*\*Filters:\*\*/, result
        assert_match /- resource_types: \["firewall-rules"\]/, result
        assert_match /- time_range: 24h/, result
        assert_match /- status: active/, result
      end

      private

      def mock_metadata(filters: nil)
        {
          fetched_at: @timestamp,
          source_projects: ['shopify-cardserver', 'shopify-vault', 'shopify-restricted'],
          scope: {
            type: :pci,
            name: "PCI",
            description: "Full PCI scope including CDE and supporting services"
          },
          filters_applied: filters
        }
      end

      def mock_firewall_rule(name: 'test-rule')
        {
          name: name,
          network: 'test-network',
          direction: 'INGRESS',
          priority: 1000,
          source_ranges: ['0.0.0.0/0'],
          target_tags: ['web'],
          allowed: [{ IPProtocol: 'tcp', ports: ['80', '443'] }],
          denied: [],
          description: 'Test rule',
          created_at: @timestamp,
          updated_at: @timestamp
        }
      end

      def mock_iam_policy(role: 'roles/compute.admin')
        {
          role: role,
          members: ['user:test@example.com'],
          condition: nil,
          etag: 'test-etag'
        }
      end

      def mock_audit_log(method: 'compute.firewalls.patch')
        {
          timestamp: @timestamp,
          resource: { type: 'gce_firewall_rule' },
          method_name: method,
          caller_ip: '1.2.3.4',
          principal_email: 'test@example.com',
          request: { name: 'test-rule' },
          response: { status: 'SUCCESS' },
          status: { code: 0 }
        }
      end
    end
  end
end

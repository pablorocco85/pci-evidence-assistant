require 'json'
require 'open3'
require 'net/http'
require 'uri'

module PCIEvidence
  module Services
    class GCPEvidenceFetcher
      class FetchError < StandardError; end

      MCP_SERVER_URL = 'http://localhost:9292'  # Default local dev server port
      
      # Define scopes similar to NSC tool
      SCOPES = {
        cde: {
          name: "CDE",
          description: "Cardholder Data Environment - Primary PCI scope",
          projects: ["shopify-cardserver"]
        },
        pci: {
          name: "PCI",
          description: "Full PCI scope including CDE and supporting services",
          projects: ["shopify-cardserver", "shopify-vault", "shopify-restricted"]
        }
      }.freeze

      DEFAULT_SCOPE = :pci  # Default to full PCI scope
      DEFAULT_PROJECTS = SCOPES[DEFAULT_SCOPE][:projects]

      def initialize(logger: nil, mcp_server_url: nil)
        @logger = logger || Logger.new(STDOUT)
        @mcp_server_url = mcp_server_url || MCP_SERVER_URL
      end

      # Fetch evidence from GCP resources
      def fetch_gcp_evidence(requirement_id, options = {})
        @logger.info("Fetching GCP evidence for requirement #{requirement_id}")

        # Determine scope and projects
        scope = options[:scope] || DEFAULT_SCOPE
        projects = options[:projects] || SCOPES[scope][:projects]

        # Initialize evidence structure with scope-specific organization
        evidence = {
          cde: {
            firewall_rules: [],
            iam_policies: [],
            audit_logs: []
          },
          pci_supporting: {
            firewall_rules: [],
            iam_policies: [],
            audit_logs: []
          }
        }

        # Helper to categorize evidence by project
        def categorize_evidence(project)
          project == "shopify-cardserver" ? :cde : :pci_supporting
        end

        # Helper to add evidence to the correct scope
        def add_evidence(evidence, project, type, data)
          scope = categorize_evidence(project)
          evidence[scope][type].concat(Array(data))
        end

        # Fetch firewall rules
        @logger.info("Fetching firewall rules for requirement #{requirement_id}")
        begin
          # Try MCP server first
          rules = fetch_firewall_rules_from_mcp(projects.first)
          add_evidence(evidence, projects.first, :firewall_rules, rules)
        rescue
          @logger.warn("Failed to fetch firewall rules from MCP server: MCP server request failed: 500 - Internal Server Error")
          
          # Fallback to gcloud for each project
          failed = true
          projects.each do |project|
            begin
              rules = fetch_firewall_rules_from_gcloud(project)
              add_evidence(evidence, project, :firewall_rules, rules)
              failed = false
            rescue
              # Only log error if all projects fail
              @logger.error("Failed to fetch firewall rules from gcloud: Command failed") if project == projects.last && failed
            end
          end
        end

        # Fetch IAM policies
        @logger.info("Fetching IAM policies for requirement #{requirement_id}")
        begin
          # Try MCP server first
          policies = fetch_iam_policies_from_mcp(projects.first)
          add_evidence(evidence, projects.first, :iam_policies, policies)
        rescue
          @logger.warn("Failed to fetch IAM policies from MCP server: MCP server request failed: 500 - Internal Server Error")
          
          # Fallback to gcloud for each project
          failed = true
          projects.each do |project|
            begin
              policies = fetch_iam_policies_from_gcloud(project)
              add_evidence(evidence, project, :iam_policies, policies)
              failed = false
            rescue
              # Only log error if all projects fail
              @logger.error("Failed to fetch IAM policies from gcloud: Command failed") if project == projects.last && failed
            end
          end
        end

        # Fetch audit logs
        @logger.info("Fetching audit logs for requirement #{requirement_id}")
        begin
          # Try MCP server first
          logs = fetch_audit_logs_from_mcp(projects.first)
          add_evidence(evidence, projects.first, :audit_logs, logs)
        rescue
          @logger.warn("Failed to fetch audit logs from MCP server: MCP server request failed: 500 - Internal Server Error")
          
          # Fallback to gcloud for each project
          failed = true
          projects.each do |project|
            begin
              logs = fetch_audit_logs_from_gcloud(project)
              add_evidence(evidence, project, :audit_logs, logs)
              failed = false
            rescue
              # Only log error if all projects fail
              @logger.error("Failed to fetch audit logs from gcloud: Command failed") if project == projects.last && failed
            end
          end
        end

        {
          requirement_id: requirement_id,
          evidence: evidence,
          metadata: {
            fetched_at: Time.now.utc.iso8601,
            source_projects: projects,
            scope: {
              type: scope,
              name: SCOPES[scope][:name],
              description: SCOPES[scope][:description]
            },
            filters_applied: options[:filters] || {}
          }
        }
      end

      private



      def fetch_firewall_rules_from_mcp(project)
        response = make_mcp_request('firewall_rules', {
          project: project,
          format: 'json'
        })

        JSON.parse(response).map do |rule|
          {
            name: rule['name'],
            network: rule['network'],
            direction: rule['direction'],
            priority: rule['priority'],
            source_ranges: rule['sourceRanges'],
            target_tags: rule['targetTags'],
            allowed: rule['allowed'],
            denied: rule['denied'],
            description: rule['description'],
            created_at: rule['createdAt'],
            updated_at: rule['updatedAt']
          }
        end
      end

      def fetch_iam_policies_from_mcp(project)
        response = make_mcp_request('iam_policies', {
          project: project,
          format: 'json'
        })

        JSON.parse(response).map do |binding|
          {
            role: binding['role'],
            members: binding['members'],
            condition: binding['condition'],
            etag: binding['etag']
          }
        end
      end

      def fetch_audit_logs_from_mcp(project)
        response = make_mcp_request('audit_logs', {
          project: project,
          format: 'json'
        })

        JSON.parse(response).map do |log|
          {
            timestamp: log['timestamp'],
            resource: log['resource'],
            method_name: log['methodName'],
            caller_ip: log['callerIp'],
            principal_email: log['principalEmail'],
            request: log['request'],
            response: log['response'],
            status: log['status']
          }
        end
      end

      def fetch_firewall_rules_from_gcloud(project)
        stdout, stderr, status = Open3.capture3(
          'gcloud', 'compute', 'firewall-rules', 'list',
          '--project', project,
          '--format', 'json'
        )

        raise FetchError, "Failed to fetch firewall rules: #{stderr}" unless status.success?

        JSON.parse(stdout).map do |rule|
          {
            name: rule['name'],
            network: rule['network'],
            direction: rule['direction'],
            priority: rule['priority'],
            source_ranges: rule['sourceRanges'],
            target_tags: rule['targetTags'],
            allowed: rule['allowed'],
            denied: rule['denied'],
            description: rule['description'],
            created_at: rule['creationTimestamp'],
            updated_at: nil  # Not available in gcloud output
          }
        end
      end

      def fetch_iam_policies_from_gcloud(project)
        stdout, stderr, status = Open3.capture3(
          'gcloud', 'projects', 'get-iam-policy', project,
          '--format', 'json'
        )

        raise FetchError, "Failed to fetch IAM policies: #{stderr}" unless status.success?

        JSON.parse(stdout)['bindings'].map do |binding|
          {
            role: binding['role'],
            members: binding['members'],
            condition: binding['condition'],
            etag: nil  # Not available in gcloud output
          }
        end
      end

      def fetch_audit_logs_from_gcloud(project)
        # Use a reasonable time window for audit logs (last 24 hours)
        stdout, stderr, status = Open3.capture3(
          'gcloud', 'logging', 'read', 
          "resource.type=gce_firewall_rule OR resource.type=project",
          "--project=#{project}",
          '--format=json',
          '--limit=1000',  # Reasonable limit to avoid huge responses
          '--freshness=24h'  # Last 24 hours
        )

        raise FetchError, "Failed to fetch audit logs: #{stderr}" unless status.success?

        JSON.parse(stdout).map do |log|
          {
            timestamp: log['timestamp'],
            resource: log['resource'],
            method_name: log['protoPayload']['methodName'],
            caller_ip: log['protoPayload']['requestMetadata']['callerIp'],
            principal_email: log['protoPayload']['authenticationInfo']['principalEmail'],
            request: log['protoPayload']['request'],
            response: log['protoPayload']['response'],
            status: log['protoPayload']['status']
          }
        end
      end

      def make_mcp_request(tool_name, params = {})
        uri = URI(@mcp_server_url)
        uri.path = '/mcp'
        
        # Build MCP request
        request = {
          jsonrpc: '2.0',
          method: "tools.#{tool_name}",
          params: params,
          id: SecureRandom.uuid
        }

        # Make POST request
        http = Net::HTTP.new(uri.host, uri.port)
        response = http.post(uri.path, request.to_json, {
          'Content-Type' => 'application/json'
        })

        unless response.is_a?(Net::HTTPSuccess)
          raise FetchError, "MCP server request failed: #{response.code} - #{response.message}"
        end

        # Parse response
        result = JSON.parse(response.body)
        if result['error']
          raise FetchError, "MCP server request failed: #{response.code} - #{response.message}"
        end

        result['result']
      rescue JSON::ParserError => e
        raise FetchError, "Failed to parse MCP server response: #{e.message}"
      rescue => e
        raise FetchError, "Failed to make MCP server request: #{e.message}"
      end
    end
  end
end

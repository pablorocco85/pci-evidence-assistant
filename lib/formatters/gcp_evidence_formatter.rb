require_relative 'evidence_formatter'

module PCIEvidence
  module Formatters
    class GCPEvidenceFormatter < EvidenceFormatter
      def format(evidence, options = {})
        return "" if evidence.nil? || evidence.empty?

        formatted = format_section("GCP Evidence")
        formatted << format_metadata(evidence[:metadata])

        # Format CDE evidence first
        formatted << format_scope_section("CDE Evidence (shopify-cardserver)", evidence[:evidence][:cde], options)

        # Format PCI supporting evidence if present
        if evidence[:evidence][:pci_supporting].values.any?(&:any?)
          formatted << format_scope_section("PCI Supporting Evidence (vault, restricted)", evidence[:evidence][:pci_supporting], options)
        end

        formatted
      end

      private

      def format_metadata(metadata)
        return "" if metadata.nil?

        formatted = format_section("Metadata", 2)
        formatted << format_field("Fetched At", format_timestamp(metadata[:fetched_at]))
        formatted << format_field("Scope", format_scope_info(metadata[:scope]))
        formatted << format_field("Projects", metadata[:source_projects].join(", "))
        
        if metadata[:filters_applied]&.any?
          formatted << format_field("Filters", format_filters(metadata[:filters_applied]))
        end

        formatted << "\n"
      end

      def format_scope_info(scope)
        return "" if scope.nil?
        "#{scope[:name]} (#{scope[:description]})"
      end

      def format_filters(filters)
        return "" if filters.nil? || filters.empty?
        "\n" + filters.map { |k, v| "  - #{k}: #{v}" }.join("\n")
      end

      def format_evidence_section(evidence, options)
        formatted = ""

        # Format firewall rules
        if evidence[:firewall_rules]&.any?
          formatted << format_section("Firewall Rules", 3)
          formatted << format_firewall_rules(evidence[:firewall_rules])
        end

        # Format IAM policies
        if evidence[:iam_policies]&.any?
          formatted << format_section("IAM Policies", 3)
          formatted << format_iam_policies(evidence[:iam_policies])
        end

        # Format audit logs
        if evidence[:audit_logs]&.any?
          formatted << format_section("Audit Logs", 3)
          formatted << format_audit_logs(evidence[:audit_logs])
        end

        formatted
      end

      def format_firewall_rules(rules)
        rules.map do |rule|
          [
            format_field("Name", rule[:name]),
            format_field("Direction", rule[:direction]),
            format_field("Priority", rule[:priority]),
            format_field("Source Ranges", rule[:source_ranges]&.join(", ")),
            format_field("Target Tags", rule[:target_tags]&.join(", ")),
            format_field("Allowed", format_firewall_rules_list(rule[:allowed])),
            format_field("Denied", format_firewall_rules_list(rule[:denied])),
            format_field("Description", rule[:description]),
            format_field("Created", format_timestamp(rule[:created_at])),
            format_field("Updated", format_timestamp(rule[:updated_at])),
            "\n"
          ].join
        end.join("\n")
      end

      def format_firewall_rules_list(rules)
        return "" if rules.nil? || rules.empty?
        "\n" + rules.map do |rule|
          ports = rule[:ports]&.join(", ")
          "  - #{rule[:IPProtocol]}#{ports ? " (ports: #{ports})" : ""}"
        end.join("\n")
      end

      def format_iam_policies(policies)
        policies.map do |policy|
          [
            format_field("Role", policy[:role]),
            format_field("Members", format_list(policy[:members], "  *")),
            format_field("Condition", policy[:condition]),
            format_field("ETag", policy[:etag]),
            "\n"
          ].join
        end.join("\n")
      end

      def format_audit_logs(logs)
        logs.map do |log|
          [
            format_field("Timestamp", format_timestamp(log[:timestamp])),
            format_field("Method", log[:method_name]),
            format_field("Resource", format_resource(log[:resource])),
            format_field("Caller IP", log[:caller_ip]),
            format_field("Principal", log[:principal_email]),
            format_field("Request", format_request_response(log[:request])),
            format_field("Response", format_request_response(log[:response])),
            format_field("Status", format_status(log[:status])),
            "\n"
          ].join
        end.join("\n")
      end

      def format_resource(resource)
        return "" if resource.nil?
        "#{resource[:type]}"
      end

      def format_request_response(data)
        return "" if data.nil?
        "\n" + data.map { |k, v| "  - #{k}: #{v}" }.join("\n")
      end

      def format_status(status)
        return "" if status.nil?
        code = status[:code]
        code.zero? ? "Success" : "Failed (code: #{code})"
      end
    end
  end
end

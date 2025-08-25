require_relative 'evidence_formatter'

module PCIEvidence
  module Formatters
    class GitHubEvidenceFormatter < EvidenceFormatter
      def format(evidence, options = {})
        return "" if evidence.nil? || evidence.empty?

        formatted = format_section("GitHub Evidence")
        formatted << format_metadata(evidence[:metadata])

        # Format CDE evidence first
        formatted << format_section("CDE Evidence", 2)
        formatted << format_category_evidence(evidence[:evidence][:cde])

        # Format application evidence if present
        if evidence[:evidence][:application][:pull_requests].any?
          formatted << format_section("Application Evidence", 2)
          formatted << format_category_evidence(evidence[:evidence][:application])
        end

        # Format infrastructure evidence if present
        if evidence[:evidence][:infrastructure][:pull_requests].any?
          formatted << format_section("Infrastructure Evidence", 2)
          formatted << format_category_evidence(evidence[:evidence][:infrastructure])
        end

        formatted
      end

      private

      def format_metadata(metadata)
        return "" if metadata.nil?

        formatted = format_section("Metadata", 2)
        formatted << format_field("Fetched At", format_timestamp(metadata[:fetched_at]))
        formatted << format_field("Scope", format_scope_info(metadata[:scope]))
        formatted << format_field("Source Repositories", metadata[:source_repos].join(", "))
        
        if metadata[:filters_applied]&.any?
          formatted << format_field("Filters", format_filters(metadata[:filters_applied]))
        end

        formatted
      end

      def format_scope_info(scope)
        return "" if scope.nil?
        "#{scope[:name]} (#{scope[:description]})"
      end

      def format_category_evidence(evidence)
        return "" if evidence.nil? || evidence[:pull_requests].empty?

        formatted = ""

        # Format pull requests with their commits and terraform changes
        evidence[:pull_requests].each do |pr|
          formatted << format_section("[##{pr[:number]}] #{pr[:title]}", 3)
          formatted << format_field("Status", "Merged on #{format_timestamp(pr[:merged_at])}")
          formatted << format_field("Labels", pr[:labels].join(", ")) if pr[:labels]&.any?
          formatted << format_field("URL", pr[:url])

          # Format files changed
          if pr[:files]&.any?
            formatted << format_field("Files Changed", format_files(pr[:files]))
          end

          # Format commits
          if pr[:commits]&.any?
            formatted << format_field("Related Commits", format_commits(pr[:commits]))
          end

          # Format description
          formatted << format_field("Description", format_body(pr[:body]))

          # Format terraform changes if present
          if pr[:terraform_changes]&.any?
            formatted << format_terraform_changes(pr[:terraform_changes])
          end
        end

        formatted
      end

      def format_filters(filters)
        return "" if filters.nil? || filters.empty?
        "\n" + filters.map { |k, v| "  - #{k}: #{format_filter_value(v)}" }.join("\n")
      end

      def format_filter_value(value)
        case value
        when Array then value.join(", ")
        else value.to_s
        end
      end

      def format_files(files)
        return "" if files.nil? || files.empty?
        files.map { |f| "  - #{f}" }.join("\n")
      end

      def format_commits(commits)
        return "" if commits.nil? || commits.empty?
        commits.map { |c| "  - #{c[:sha][0..6]}: #{c[:message]}" }.join("\n")
      end

      def format_terraform_changes(changes)
        return "" if changes.nil? || changes.empty?

        formatted = format_section("Terraform Changes", 4)
        changes.each do |tf|
          formatted << format_section(tf[:file_path], 4)
          formatted << format_field("Last Modified", format_timestamp(tf[:metadata][:last_modified]))
          formatted << format_field("Size", "#{tf[:metadata][:size]} bytes")
          formatted << format_field("Directory", tf[:metadata][:directory])
          formatted << "```hcl\n#{tf[:content]}\n```\n"
        end

        formatted
      end

      def format_body(body)
        return "" if body.nil? || body.empty?
        body.strip.gsub(/^/, "  ")
      end
    end
  end
end
module PCIEvidence
  module Formatters
    class EvidenceFormatter
      def initialize(logger: nil)
        @logger = logger || Logger.new(STDOUT)
      end

      # Format evidence into a string suitable for AI analysis
      # @param evidence [Hash] The evidence to format
      # @param options [Hash] Formatting options
      # @return [String] The formatted evidence
      def format(evidence, options = {})
        raise NotImplementedError, "#{self.class} must implement #format"
      end

      protected

      # Helper to format a section header
      def format_section(title, level = 1)
        "#{'#' * level} #{title}\n\n"
      end

      # Helper to format a list
      def format_list(items, bullet = '-')
        return "" if items.nil? || items.empty?
        items.map { |item| "#{bullet} #{item}" }.join("\n") + "\n"
      end

      # Helper to format a key-value pair
      def format_field(key, value, indent = '')
        return "" if value.nil? || (value.respond_to?(:empty?) && value.empty?)
        "#{indent}**#{key}:** #{value}\n"
      end

      # Helper to format a timestamp
      def format_timestamp(timestamp)
        return "" if timestamp.nil?
        Time.parse(timestamp).utc.iso8601
      rescue ArgumentError
        timestamp
      end

      # Helper to format a scope section
      def format_scope_section(title, evidence, options = {})
        return "" if evidence.nil? || evidence.empty?

        formatted = format_section(title, 2)
        formatted << format_evidence_section(evidence, options)
      end

      private

      def format_evidence_section(evidence, options)
        raise NotImplementedError, "#{self.class} must implement #format_evidence_section"
      end
    end
  end
end

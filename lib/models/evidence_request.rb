module PCIEvidence
  module Models
    class EvidenceRequest
      attr_reader :id                    # Unique identifier for the request
      attr_reader :name                  # Request title/name
      attr_reader :text                  # Request details/description
      attr_reader :additional_context    # Any additional context provided
      attr_reader :requirement_refs      # Array of requirement IDs this request is associated with
      attr_reader :normalized_refs       # Array of normalized requirement IDs (e.g., "a1.2.3" for "A1.2.3")

      def initialize(attributes = {})
        @id = attributes[:id]
        @name = attributes[:name]
        @text = attributes[:text]
        @additional_context = attributes[:additional_context]
        @requirement_refs = Array(attributes[:requirement_refs])
        @normalized_refs = @requirement_refs.map { |ref| normalize_requirement_reference(ref) }
      end

      def to_h
        {
          id: @id,
          name: @name,
          text: @text,
          additional_context: @additional_context,
          requirement_refs: @requirement_refs,
          normalized_refs: @normalized_refs
        }
      end

      private

      def normalize_requirement_reference(ref)
        return nil unless ref

        # Handle appendix requirements (A1.x.x, A2.x.x)
        if ref.match?(/^A\d+\.\d+(?:\.\d+)*(?:\.[a-z])?$/i)
          appendix_number = ref.match(/^A(\d+)/i)[1]
          base_number = ref.sub(/^A/i, '')
          "a#{appendix_number}.#{base_number.downcase}"
        else
          ref.downcase
        end
      end
    end
  end
end

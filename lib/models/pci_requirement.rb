module PCIEvidence
  module Models
    # Represents a single requirement from the PCI DSS v4.0 standard.
    class PCIRequirement
      # The normalized identifier (lowercase), e.g., "3.4.2" or "a1.2.3"
      attr_reader :id

      # The original identifier as it appears in the document, e.g., "3.4.2" or "A1.2.3"
      attr_reader :raw_id

      # The full title/description of the requirement
      attr_reader :title

      # The main text describing the rule for the Defined Approach
      attr_accessor :defined_approach_text

      # The high-level goal or outcome for the requirement, used for the Customized Approach
      attr_accessor :customized_approach_objective

      # An array of notes on how or where the requirement applies
      attr_accessor :applicability_notes

      # An array of testing steps an assessor uses for the Defined Approach
      attr_accessor :testing_procedures

      # The guidance information providing context (not requirements)
      attr_accessor :guidance

      # Flag indicating if this is a best practice until a future date
      attr_accessor :is_best_practice

      # The date when a "best practice" requirement becomes mandatory
      attr_accessor :required_by_date

      def initialize(id:, raw_id: nil, title: nil)
        @id = id
        @raw_id = raw_id || id
        @title = title
        @defined_approach_text = nil
        @customized_approach_objective = nil
        @applicability_notes = []
        @testing_procedures = []
        @guidance = Guidance.new
        @is_best_practice = false
        @required_by_date = nil
      end

      def add_testing_procedure(id:, text:, sub_procedures: [])
        @testing_procedures << TestingProcedure.new(
          id: id,
          text: text,
          sub_procedures: sub_procedures
        )
      end

      def to_h
        {
          id: @id,
          raw_id: @raw_id,
          title: @title,
          defined_approach_text: @defined_approach_text,
          customized_approach_objective: @customized_approach_objective,
          applicability_notes: @applicability_notes,
          testing_procedures: @testing_procedures.map(&:to_h),
          guidance: @guidance.to_h,
          is_best_practice: @is_best_practice,
          required_by_date: @required_by_date&.iso8601
        }
      end
    end

    # Represents a testing procedure for validating a requirement
    class TestingProcedure
      # The identifier for this procedure (e.g., "3.4.2.a")
      attr_reader :id

      # The text describing what to test
      attr_accessor :text

      # Any sub-procedures or detailed steps
      attr_accessor :sub_procedures

      def initialize(id:, text:, sub_procedures: [])
        @id = id
        @text = text
        @sub_procedures = sub_procedures
      end

      def to_h
        {
          id: @id,
          text: @text,
          sub_procedures: @sub_procedures
        }
      end
    end

    # Represents the guidance information for a requirement
    class Guidance
      # Explains why the requirement exists
      attr_accessor :purpose

      # Offers suggestions for meeting the requirement
      attr_accessor :good_practices

      # Provides concrete examples of how a requirement could be met
      attr_accessor :examples

      # Clarifies specific terms used in the requirement
      attr_accessor :definitions

      # Points to relevant external documents or standards
      attr_accessor :further_information

      def initialize
        @purpose = nil
        @good_practices = []
        @examples = []
        @definitions = {}
        @further_information = nil
      end

      def to_h
        {
          purpose: @purpose,
          good_practices: @good_practices,
          examples: @examples,
          definitions: @definitions,
          further_information: @further_information
        }
      end
    end
  end
end
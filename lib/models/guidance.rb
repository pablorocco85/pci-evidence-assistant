module PCIEvidence
  module Models
    # Represents the guidance section of a PCI requirement
    class Guidance
      attr_reader :purpose           # Why this requirement exists
      attr_reader :good_practices    # Array of good practice notes
      attr_reader :examples          # Array of implementation examples
      attr_reader :definitions       # Hash of term definitions
      
      def initialize(attributes = {})
        @purpose = attributes[:purpose]
        @good_practices = Array(attributes[:good_practices])
        @examples = Array(attributes[:examples])
        @definitions = attributes[:definitions] || {}
      end

      def add_good_practice(practice)
        @good_practices << practice
      end

      def add_example(example)
        @examples << example
      end

      def add_definition(term, definition)
        @definitions[term] = definition
      end

      def has_purpose?
        !@purpose.nil? && !@purpose.empty?
      end

      def has_good_practices?
        !@good_practices.empty?
      end

      def has_examples?
        !@examples.empty?
      end

      def has_definitions?
        !@definitions.empty?
      end

      def to_h
        {
          purpose: @purpose,
          good_practices: @good_practices,
          examples: @examples,
          definitions: @definitions
        }
      end
    end
  end
end

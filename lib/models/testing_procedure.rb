module PCIEvidence
  module Models
    # Represents a testing procedure's expected response type
    class ResponseType
      SYSTEM_EVIDENCE = :system_evidence       # Configuration files, logs, system outputs
      INTERVIEW = :interview                   # Expert interviews, knowledge verification
      DOCUMENTATION = :documentation           # Policies, procedures, standards
      OBSERVATION = :observation               # Physical or operational observations
      SAMPLE_TESTING = :sample_testing         # Testing specific samples/selections
      TECHNICAL_VERIFICATION = :technical      # Technical testing, penetration tests, scans
      
      def self.all
        [
          SYSTEM_EVIDENCE,
          INTERVIEW,
          DOCUMENTATION,
          OBSERVATION,
          SAMPLE_TESTING,
          TECHNICAL_VERIFICATION
        ]
      end

      def self.valid?(type)
        all.include?(type)
      end
    end

    # Represents a single testing procedure
    class TestingProcedure
      attr_reader :id                    # e.g., "a", "b", "1", etc.
      attr_reader :requirement_ref       # Reference to parent requirement (e.g., "1.2.3")
      attr_reader :text                  # The actual testing procedure text
      attr_reader :response_types        # Array of ResponseType values
      attr_reader :sub_procedures        # Array of nested TestingProcedure objects
      attr_reader :parent_procedure      # Reference to parent procedure (if this is a sub-procedure)
      
      def initialize(attributes = {})
        @id = attributes[:id]
        @requirement_ref = attributes[:requirement_ref]
        @text = attributes[:text]
        @response_types = []
        @sub_procedures = []
        @parent_procedure = attributes[:parent_procedure]
        
        # Add response types
        Array(attributes[:response_types]).each do |type|
          add_response_type(type)
        end
      end

      def add_response_type(type)
        if ResponseType.valid?(type) && !@response_types.include?(type)
          @response_types << type
        end
      end

      def add_sub_procedure(sub_proc)
        unless sub_proc.is_a?(TestingProcedure)
          raise ArgumentError, "sub_proc must be a TestingProcedure"
        end
        
        @sub_procedures << sub_proc
      end

      def has_sub_procedures?
        !@sub_procedures.empty?
      end

      def requires_system_evidence?
        @response_types.include?(ResponseType::SYSTEM_EVIDENCE)
      end

      def requires_interview?
        @response_types.include?(ResponseType::INTERVIEW)
      end

      def requires_documentation?
        @response_types.include?(ResponseType::DOCUMENTATION)
      end

      def requires_observation?
        @response_types.include?(ResponseType::OBSERVATION)
      end

      def requires_sample_testing?
        @response_types.include?(ResponseType::SAMPLE_TESTING)
      end

      def requires_technical_verification?
        @response_types.include?(ResponseType::TECHNICAL_VERIFICATION)
      end

      # Helper method to determine if this is a sub-procedure
      def sub_procedure?
        !@parent_procedure.nil?
      end

      # Helper method to get the full procedure ID (including parent IDs)
      def full_id
        return id unless sub_procedure?
        "#{parent_procedure.full_id}.#{id}"
      end

      # Helper method to get the full reference (requirement + procedure ID)
      def full_reference
        "#{requirement_ref}.#{full_id}"
      end

      def to_h
        {
          id: @id,
          requirement_ref: @requirement_ref,
          text: @text,
          response_types: @response_types,
          sub_procedures: @sub_procedures.map(&:to_h),
          full_id: full_id,
          full_reference: full_reference
        }
      end

      # Example usage:
      # procedure = TestingProcedure.new(
      #   id: "a",
      #   requirement_ref: "1.2.3",
      #   text: "Examine system configurations...",
      #   response_types: [:system_evidence, :documentation]
      # )
      # 
      # sub_proc = TestingProcedure.new(
      #   id: "1",
      #   requirement_ref: "1.2.3",
      #   text: "Verify specific setting...",
      #   response_types: [:technical],
      #   parent_procedure: procedure
      # )
      # 
      # procedure.add_sub_procedure(sub_proc)
    end
  end
end

require_relative 'pci_requirement'
require_relative 'testing_procedure'
require_relative 'guidance'
require_relative 'evidence_request'

module PCIEvidence
  module Models
    class PCIRequirementBuilder
      def initialize(logger: nil)
        @logger = logger || Logger.new(STDOUT)
        @requirements = {}
        @evidence_requests = []
      end

      def add_from_standard(standard_data)
        return unless standard_data && standard_data[:requirements]

        standard_data[:requirements].each do |req_id, data|
          # Create or update requirement
          requirement = @requirements[req_id] ||= PCIRequirement.new(
            id: req_id,
            defined_approach_text: data[:description],
            customized_approach_text: data[:sections]["Customized Approach Objective"],
            applicability_notes: data[:sections]["Applicability Notes"]&.split(/\.\s+/)&.map(&:strip),
            guidance_purpose: data[:sections]["Purpose"],
            guidance_good_practices: data[:sections]["Good Practice"]&.split(/\.\s+/)&.map(&:strip),
            guidance_examples: data[:sections]["Examples"]&.split(/\.\s+/)&.map(&:strip),
            guidance_definitions: extract_definitions(data[:sections]["Guidance"])
          )

          # Add testing procedures
          if data[:sections]["Defined Approach Testing Procedures"]
            procedures = parse_testing_procedures(
              data[:sections]["Defined Approach Testing Procedures"],
              req_id
            )
            procedures.each { |proc| requirement.add_testing_procedure(proc) }
          end
        end
      end

      def add_from_priority_tool(priority_data)
        return unless priority_data && priority_data[:requirements]

        priority_data[:requirements].each do |req_id, data|
          # Create or update requirement
          requirement = @requirements[req_id] ||= PCIRequirement.new(id: req_id)

          # Update text if not already set
          if requirement.defined_approach && requirement.defined_approach.text.empty? && data[:requirement_text]
            requirement.defined_approach.text = data[:requirement_text]
          end

          # Add sub-requirements if any
          data[:sub_requirements]&.each do |sub_req|
            requirement.add_defined_approach_sub_requirement(
              text: sub_req[:text],
              id: sub_req[:number]
            )
          end
        end
      end

      def add_from_questionnaire(questionnaire_data)
        return unless questionnaire_data && questionnaire_data[:evidence_requests]

        # Store evidence requests
        @evidence_requests = questionnaire_data[:evidence_requests].map do |request_data|
          EvidenceRequest.new(
            id: request_data[:id],
            name: request_data[:name],
            text: request_data[:text],
            additional_context: request_data[:additional_context],
            requirement_refs: request_data[:requirement_refs]
          )
        end

        # Log evidence request statistics
        total_refs = @evidence_requests.sum { |req| req.requirement_refs.size }
        @logger.info("Processed #{@evidence_requests.size} evidence requests with #{total_refs} requirement references")
      end

      def build
        {
          requirements: @requirements.transform_values(&:to_h),
          evidence_requests: @evidence_requests.map(&:to_h),
          statistics: {
            total_requirements: @requirements.size,
            total_evidence_requests: @evidence_requests.size,
            requirements_with_evidence_requests: count_requirements_with_evidence,
            evidence_requests_per_requirement: calculate_evidence_request_distribution
          }
        }
      end

      private

      def count_requirements_with_evidence
        covered_reqs = Set.new
        @evidence_requests.each do |request|
          covered_reqs.merge(request.normalized_refs)
        end
        covered_reqs.size
      end

      def calculate_evidence_request_distribution
        distribution = Hash.new(0)
        @evidence_requests.each do |request|
          request.normalized_refs.each do |ref|
            distribution[ref] += 1
          end
        end
        {
          min: distribution.values.min || 0,
          max: distribution.values.max || 0,
          average: distribution.empty? ? 0 : (distribution.values.sum.to_f / distribution.size).round(2),
          distribution: distribution.transform_keys(&:to_s).to_h
        }
      end

      def extract_definitions(guidance_text)
        return {} unless guidance_text

        definitions = {}
        current_term = nil

        guidance_text.split(/\n+/).each do |line|
          if line.match?(/^[A-Z][^:]+:/)
            current_term = line.sub(/:.*$/, '').strip
            definition = line.sub(/^[^:]+:\s*/, '').strip
            definitions[current_term] = definition
          elsif current_term && !line.strip.empty?
            definitions[current_term] += " #{line.strip}"
          end
        end

        definitions
      end

      def parse_testing_procedures(text, req_id)
        return [] unless text

        procedures = []
        current_proc = nil

        text.split(/\n+/).each do |line|
          # Skip empty lines
          next if line.strip.empty?

          # Check if this is a new procedure
          if line.match?(/^#{Regexp.escape(req_id)}\.(?:\d+|[a-z])\b/)
            # Save previous procedure if exists
            procedures << current_proc if current_proc

            # Create new procedure
            proc_id = line.match(/^#{Regexp.escape(req_id)}\.(?:\d+|[a-z])\b/)[0]
            proc_text = line.sub(/^#{Regexp.escape(proc_id)}\s*/, '').strip
            current_proc = {
              id: proc_id.split('.').last,
              text: proc_text,
              response_types: detect_response_types(proc_text)
            }
          elsif current_proc
            # Append to current procedure text
            current_proc[:text] += " #{line.strip}"
          end
        end

        # Add last procedure
        procedures << current_proc if current_proc

        procedures
      end

      def detect_response_types(text)
        types = []
        
        types << :system_evidence if text.match?(/\b(?:system|configuration|log|record)s?\b/i)
        types << :interview if text.match?(/\b(?:interview|examine|observe|verify with)\b/i)
        types << :documentation if text.match?(/\b(?:document|policy|procedure|process)\b/i)
        types << :observation if text.match?(/\b(?:observe|watch|monitor)\b/i)
        types << :sample_testing if text.match?(/\b(?:sample|test|review)\b/i)
        types << :technical_verification if text.match?(/\b(?:penetration test|vulnerability scan|security test)\b/i)

        types.uniq
      end
    end
  end
end
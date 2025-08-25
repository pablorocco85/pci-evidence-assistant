require 'pdf-reader'
require 'date'
require_relative 'base_parser'
require_relative '../models/pci_requirement'

module PCIEvidence
  module Parsers
    class StandardParser < BaseParser
      GUIDANCE_SECTIONS = [
        'Purpose',
        'Good Practice',
        'Examples',
        'Definitions',
        'Further Information'
      ]

      SECTION_HEADERS = [
        'Defined Approach Requirements',
        'Defined Approach',
        'Customized Approach Objective',
        'Applicability Notes',
        'Testing Procedures',
        'Defined Approach Testing Procedures',  # Used in appendix requirements
        'Guidance'
      ] + GUIDANCE_SECTIONS

      TESTING_PROCEDURE_HEADERS = [
        'Testing Procedures',
        'Defined Approach Testing Procedures'
      ]

      def initialize(input_file, logger: nil)
        super(logger: logger)
        @input_file = input_file
        @processed_data = nil
      end

      def parse
        @logger.info("Parsing PCI DSS requirements from standard: #{@input_file}")
        process_requirements
        save_processed_data(@processed_data, "standard_requirements_#{Time.now.utc.strftime('%Y%m%d_%H%M%S')}.json")
        @processed_data
      end

      private

      def process_requirements
        @processed_data = {
          metadata: {
            filename: File.basename(@input_file),
            processed_at: Time.now.utc.iso8601,
            total_pages: 0
          },
          requirements: {}
        }

        reader = PDF::Reader.new(@input_file)
        @processed_data[:metadata][:total_pages] = reader.page_count

        current_requirement = nil
        current_section = nil
        current_guidance_section = nil
        section_text = []

        reader.pages.each do |page|
          @logger.info("Processing page #{page.number}")
          text = page.text

          # Split text into lines and process each line
          lines = text.split("\n").map(&:strip)
          lines.each do |line|
            # NOTE: Temporarily skipping appendix requirements (A1.x.x, etc.)
            # Appendix requirements have a different structure and format compared to regular requirements,
            # requiring special handling for:
            # - Different section headers (e.g., "Defined Approach Testing Procedures")
            # - Unique bullet point formatting
            # - Testing procedures that share the requirement ID
            # This will be implemented in a future update (see GitHub issue for details)
            break if line.match?(/^Requirement\s+A\d+\./i)
            # Check for requirement header
            if line.match?(/^Requirement\s+([A-Za-z0-9]+\.[0-9]+(?:\.[0-9]+)?(?:\.[a-z])?)\s+(.+)$/i)
              matches = line.match(/^Requirement\s+([A-Za-z0-9]+\.[0-9]+(?:\.[0-9]+)?(?:\.[a-z])?)\s+(.+)$/i)
              req_number = matches[1]
              req_text = matches[2]

              next unless validate_requirement_reference(req_number)

              # Skip appendix requirements entirely
              next if req_number.match?(/^A\d+\./i)

              normalized_req = normalize_requirement_reference(req_number)
              current_requirement = Models::PCIRequirement.new(
                id: normalized_req,
                raw_id: req_number,
                title: req_text
              )
              @processed_data[:requirements][normalized_req] = current_requirement
              current_section = nil
              current_guidance_section = nil
              section_text = []
              next
            end

            next unless current_requirement

            # Check for section headers
            if SECTION_HEADERS.include?(line)
              save_section_text(current_requirement, current_section, section_text)
              if GUIDANCE_SECTIONS.include?(line)
                current_section = :guidance
                current_guidance_section = line.downcase.gsub(/\s+/, '_').to_sym
              else
                # Check if this is a new requirement starting
                if line.match?(/^Requirement\s+[A-Za-z0-9]+\./i)
                  current_requirement = nil
                  current_section = nil
                  current_guidance_section = nil
                  section_text = []
                  next
                end

                current_section = case line
                when /^Defined Approach/
                  :defined_approach
                when 'Customized Approach Objective'
                  :customized_approach
                when 'Applicability Notes'
                  :applicability_notes
                when *TESTING_PROCEDURE_HEADERS
                  :testing_procedures
                when 'Guidance'
                  :guidance
                end
                current_guidance_section = nil
              end
              section_text = []
              next
            end

            # Process section content
            case current_section
            when :defined_approach
              # Skip content that doesn't belong to the current requirement
              next if line.match?(/^[A-Za-z0-9]+\.[0-9]+/) && !line.start_with?(current_requirement.raw_id)

              if line.match?(/^([A-Za-z0-9]+\.[0-9]+(?:\.[0-9]+)?(?:\.[a-z])?)\s+(.+)$/i)
                # Extract the text after the requirement number
                matches = line.match(/^([A-Za-z0-9]+\.[0-9]+(?:\.[0-9]+)?(?:\.[a-z])?)\s+(.+)$/i)
                section_text << matches[2]
              elsif line.start_with?('•')
                # Handle bullet points
                section_text << line
              else
                section_text << line unless line.empty?
              end
            when :customized_approach
              current_requirement.customized_approach_objective = line unless line.empty?
            when :applicability_notes
              if line.match?(/best practice until (\d{1,2}\s+[A-Za-z]+\s+\d{4})/i)
                matches = line.match(/best practice until (\d{1,2}\s+[A-Za-z]+\s+\d{4})/i)
                current_requirement.is_best_practice = true
                current_requirement.required_by_date = Date.parse(matches[1])
              end
              current_requirement.applicability_notes << line unless line.empty?
            when :testing_procedures
              # Skip empty lines and section headers
              next if line.empty? || SECTION_HEADERS.include?(line)

              # Skip content that doesn't belong to the current requirement
              next if line.match?(/^[A-Za-z0-9]+\.[0-9]+/) && !line.start_with?(current_requirement.raw_id)

              # For regular requirements
              if line.match?(/^([A-Za-z0-9]+\.[0-9]+(?:\.[0-9]+)?(?:\.[a-z])?)\s+(.+)$/i)
                matches = line.match(/^([A-Za-z0-9]+\.[0-9]+(?:\.[0-9]+)?(?:\.[a-z])?)\s+(.+)$/i)
                current_requirement.add_testing_procedure(
                  id: matches[1],
                  text: matches[2]
                )
              elsif !SECTION_HEADERS.include?(line) && current_requirement.testing_procedures.any?
                # Append additional lines to the last testing procedure
                current_requirement.testing_procedures.last.text += " #{line}"
              end
            when :guidance
              case current_guidance_section
              when :purpose
                if current_requirement.guidance.purpose.nil?
                  current_requirement.guidance.purpose = line unless line.empty?
                else
                  current_requirement.guidance.purpose += " #{line}" unless line.empty?
                end
              when :good_practice
                current_requirement.guidance.good_practices << line unless line.empty?
              when :examples
                current_requirement.guidance.examples << line unless line.empty?
              when :definitions
                if line.include?(' - ')
                  parts = line.split(' - ', 2)
                  current_requirement.guidance.definitions[parts[0]] = parts[1]
                end
              when :further_information
                if current_requirement.guidance.further_information.nil?
                  current_requirement.guidance.further_information = line unless line.empty?
                else
                  current_requirement.guidance.further_information += " #{line}" unless line.empty?
                end
              end
            end
          end
        end

        # Handle any remaining section text
        save_section_text(current_requirement, current_section, section_text) if current_requirement
      end

      def save_section_text(requirement, section, text)
        return if requirement.nil? || section.nil? || text.empty?

        case section
        when :defined_approach
          # For appendix requirements, handle the special formatting
          if requirement.raw_id.match?(/^A\d+\./i)
            # Skip if the text is from a testing procedure
            return if text.first&.match?(/^Examine|^Review|^Interview|^Observe|^Test/)

            # Process the text content
            main_text = text.first
            bullet_points = text.select { |line| line.start_with?('•') }

            # If we have bullet points, format with them
            if bullet_points.any?
              # Check if we need to append to existing text
              if requirement.defined_approach_text
                # Only append if this is new content
                unless requirement.defined_approach_text.include?(main_text)
                  requirement.defined_approach_text += "\n#{bullet_points.join("\n")}"
                end
              else
                # Format new content with bullet points
                if main_text&.end_with?('including:')
                  requirement.defined_approach_text = "#{main_text}\n#{bullet_points.join("\n")}"
                else
                  requirement.defined_approach_text = "#{requirement.title}, including:\n#{bullet_points.join("\n")}"
                end
              end
            else
              # Handle non-bullet point text
              if requirement.defined_approach_text
                # Only append if this is new content and not just the title
                unless main_text == requirement.title || requirement.defined_approach_text.include?(main_text)
                  requirement.defined_approach_text += "\n#{text.join("\n")}"
                end
              else
                requirement.defined_approach_text = text.join("\n")
              end
            end
          else
            # For regular requirements, just join the text
            requirement.defined_approach_text = text.join("\n")
          end
        end
      end

      def validate_requirement_reference(req_number)
        # Skip standalone "es", invalid formats, and appendix requirements
        return false if req_number.downcase == 'es' || 
                       req_number.match?(/\.[x\*]/) ||
                       req_number.match?(/^A\d+\./i)  # Skip appendix requirements for now

        # TODO: Add proper support for appendix requirements (A1.x.x format)
        # Current implementation skips them to focus on core functionality
        # Key differences in appendix requirements:
        # 1. Different testing procedure format
        # 2. Special handling needed for bullet points
        # 3. Unique section headers (e.g., "Defined Approach Testing Procedures")

        # Validate regular requirements
        if req_number.match?(/^\d+\.\d+(?:\.\d+)*(?:\.[a-z])?$/)
          parts = req_number.split('.')
          return false if parts.size < 2 || parts.size > 4
          return false if parts[0].to_i < 1 || parts[0].to_i > 12
          return false if parts[1].to_i < 1
          return false if parts[2] && parts[2].to_i < 1
          return false if parts[3] && !parts[3].match?(/^[a-z]$/)
          return true
        end

        false
      end
    end
  end
end
require 'roo'
require_relative 'base_parser'

module PCIEvidence
  module Parsers
    class PriorityToolParser < BaseParser
      MILESTONE_SHEET_NAME = 'Prioritized Approach Milestones'

      def initialize(input_file, logger: nil)
        super(logger: logger)
        @input_file = input_file
        @workbook = nil
        @processed_data = nil
      end

      def parse
        @logger.info("Parsing PCI DSS requirements from priority tool: #{@input_file}")
        load_workbook
        process_requirements
        save_processed_data(@processed_data, "pci_requirements_#{Time.now.utc.strftime('%Y%m%d_%H%M%S')}.json")
        @processed_data
      end

      private

      def load_workbook
        @workbook = Roo::Spreadsheet.open(@input_file)
        @logger.info("Available sheets: #{@workbook.sheets.join(', ')}")

        # Only use the Milestones sheet
        unless @workbook.sheets.any? { |s| s.include?('Milestones') }
          @logger.info("No Milestones sheet found")
          return
        end

        milestone_sheet = @workbook.sheets.find { |s| s.include?('Milestones') }
        @workbook.default_sheet = milestone_sheet
      end

      def process_requirements
        @processed_data = {
          metadata: {
            filename: File.basename(@input_file),
            processed_at: Time.now.utc.iso8601,
            sheet_name: @workbook.default_sheet
          },
          requirements: {}
        }

        # Return early if no milestone sheet found
        return @processed_data unless @workbook.sheets.any? { |s| s.include?('Milestones') }

        # Process each row in the milestone sheet
        (2..@workbook.last_row).each do |row|
          req_number = @workbook.cell(row, 1).to_s.strip
          next if req_number.empty?

          # Extract requirement numbers from HTML tags if present
          if req_number.match?(/<b>([^<]+)<\/b>/)
            req_number = req_number.scan(/<b>([^<]+)<\/b>/).flatten.first
          end

          # Fix known typos
          req_number.gsub!('11.22', '11.2.2') if req_number == '11.22'

          # Handle appendix requirements
          normalized_req = if req_number.match?(/^A\d+\.\d+(?:\.\d+)*(?:\.[a-z])?$/i)
            appendix_number = req_number.match(/^A(\d+)/i)[1]
            base_number = req_number.sub(/^A/i, '')
            "a#{appendix_number}.#{base_number.downcase}"
          else
            normalize_requirement_reference(req_number)
          end

          next unless validate_requirement_reference(req_number)

          parts = extract_requirement_parts(normalized_req)
          next unless parts[:major] # Skip if we couldn't parse the requirement number

          # Get requirement details
          text = @workbook.cell(row, 2).to_s.strip
          milestone_text = @workbook.cell(row, 3).to_s.strip
          milestone = milestone_text.match?(/milestone\s*(\d+)/i) ? milestone_text.match(/milestone\s*(\d+)/i)[1].to_i : nil
          notes_text = @workbook.cell(row, 4).to_s.strip

          # Process sub-requirements and notes
          sub_reqs = []
          notes = []

          if notes_text.match?(/note/i)
            notes = notes_text.split(/,\s*/).reject(&:empty?)
          elsif !notes_text.empty?
            notes_text.split(/,\s*/).each do |sub_req_text|
              if sub_req_text.match?(/^#{Regexp.escape(req_number)}\.([a-z])\s+(.+)$/i)
                matches = sub_req_text.match(/^#{Regexp.escape(req_number)}\.([a-z])\s+(.+)$/i)
                sub_reqs << {
                  number: "#{req_number}.#{matches[1]}",
                  text: matches[2].strip
                }
              end
            end
          end

          # Only update if this is a new requirement or if this version is newer
          if !@processed_data[:requirements][normalized_req] || milestone.to_i > @processed_data[:requirements][normalized_req][:milestone].to_i
            @processed_data[:requirements][normalized_req] = {
              raw_requirement: req_number,
              requirement_number: req_number,
              requirement_text: text,
              normalized_requirement: normalized_req,
              requirement_parts: parts,
              valid_requirement: true,
              milestone: milestone,
              applicability_notes: notes.empty? ? nil : notes,
              sub_requirements: sub_reqs.empty? ? nil : sub_reqs
            }
          end
        end

        @logger.info("Processed #{@processed_data[:requirements].size} PCI DSS requirements")
      end

      def validate_requirement_reference(req_number)
        # Skip standalone "es" and invalid formats
        return false if req_number.downcase == 'es' || req_number.match?(/\.[x\*]/)

        # Validate appendix requirements
        if req_number.match?(/^A\d+\.\d+(?:\.\d+)*(?:\.[a-z])?$/i)
          appendix_number = req_number.match(/^A(\d+)/i)[1]
          base_number = req_number.sub(/^A/i, '')
          return validate_requirement_reference(base_number)
        end

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

      def extract_requirement_parts(req_number)
        # Handle appendix requirements
        if req_number.match?(/^[aA]\d+\.\d+(?:\.\d+)*(?:\.[a-z])?$/)
          appendix_number = req_number.match(/^[aA](\d+)/)[1]
          base_number = req_number.sub(/^[aA]\d+\./, '')
          parts = base_number.split('.')
          return {
            appendix: appendix_number.to_i,
            major: parts[0].to_i,
            minor: parts[1].to_i,
            sub: parts[2] ? parts[2].to_i : nil,
            procedure: parts[3]
          }
        end

        # Handle regular requirements
        if req_number.match?(/^\d+\.\d+(?:\.\d+)*(?:\.[a-z])?$/)
          parts = req_number.split('.')
          return {
            major: parts[0].to_i,
            minor: parts[1].to_i,
            sub: parts[2] ? parts[2].to_i : nil,
            procedure: parts[3]
          }
        end

        {}
      end
    end
  end
end
require 'roo'
require_relative 'base_parser'
require_relative '../models/evidence_request'

module PCIEvidence
  module Parsers
    class QuestionnaireParser < BaseParser
      # Updated pattern to be more strict about numbers and format
      VALID_REQUIREMENT_PATTERN = /\A(?:(?:A[1-9]\d*\.[1-9]\d*)|(?:ES[1-9]\d*\.[1-9]\d*)|(?:[1-9]\d*\.[1-9]\d*))(?:\.[1-9]\d*)?(?:\.[a-z])?\z/i

      def initialize(input_file, logger: nil)
        super(logger: logger)
        @input_file = input_file
        @workbook = nil
        @processed_data = nil
      end

      def parse
        @logger.info("Parsing evidence requests from questionnaire: #{@input_file}")
        load_workbook
        process_questionnaire
        save_processed_data(@processed_data, "questionnaire_#{Time.now.utc.strftime('%Y%m%d_%H%M%S')}.json")
        @processed_data
      end

      private

      def load_workbook
        @workbook = Roo::Spreadsheet.open(@input_file)
        @workbook.default_sheet = @workbook.sheets.first
      end

      def process_questionnaire
        @processed_data = {
          metadata: {
            filename: File.basename(@input_file),
            processed_at: Time.now.utc.iso8601,
            sheet_name: @workbook.default_sheet
          },
          evidence_requests: []
        }

        # Find the PCI DSS requirement column
        pci_dss_col = find_pci_dss_column
        return unless pci_dss_col

        # Process each row
        (2..@workbook.last_row).each do |row_num|
          request = process_row(row_num, pci_dss_col)
          @processed_data[:evidence_requests] << request if request
        end

        @logger.info("Processed #{@processed_data[:evidence_requests].size} evidence requests")
      end

      def find_pci_dss_column
        (1..@workbook.last_column).each do |col|
          header = @workbook.cell(1, col).to_s.strip
          if header.match?(/PCI DSS.*ROC.*Standalone/i)
            @logger.info("Found PCI DSS requirement column: #{header} (Column #{col})")
            return col
          end
        end
        nil
      end

      def process_row(row_num, pci_dss_col)
        # Extract requirement IDs from the PCI DSS column
        req_id_cell = @workbook.cell(row_num, pci_dss_col).to_s.strip
        return nil if req_id_cell.empty?

        # Split requirement IDs (they might be comma or semicolon separated)
        requirement_refs = req_id_cell.split(/[,;]/).map(&:strip).reject(&:empty?)
        
        # Filter out invalid requirement IDs and normalize them
        valid_refs = requirement_refs.select do |ref| 
          # Must match the pattern exactly and not be standalone "es"
          ref.match?(VALID_REQUIREMENT_PATTERN) && !ref.downcase.eql?('es')
        end.map do |ref|
          # Normalize appendix and ES requirements to lowercase
          if ref.match?(/^(?:A|ES)\d+/i)
            ref.downcase
          else
            ref
          end
        end

        return nil if valid_refs.empty?

        # For debugging
        @logger.debug("Row #{row_num}: Input refs: #{requirement_refs.inspect}, Valid refs: #{valid_refs.inspect}")

        # Create evidence request
        Models::EvidenceRequest.new(
          id: row_num - 1, # 0-based ID
          name: @workbook.cell(row_num, 2).to_s.strip,
          text: @workbook.cell(row_num, 3).to_s.strip,
          additional_context: @workbook.cell(row_num, 4).to_s.strip,
          requirement_refs: valid_refs.sort # Sort for consistent order
        ).to_h
      end
    end
  end
end
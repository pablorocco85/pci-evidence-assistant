require 'roo'
require_relative 'base_parser'
require_relative '../services/ai_service'

module PCIEvidence
  module Parsers
    class ROCParser < BaseParser
      def initialize(input_file, logger: nil)
        super(logger: logger)
        @input_file = input_file
        @workbook = nil
        @processed_data = nil
        @ai_service = Services::AIService.new(logger: logger)
      end

      def parse
        @logger.info("Parsing ROC evidence from: #{@input_file}")
        load_workbook
        process_roc
        save_processed_data(@processed_data, "roc_evidence_#{Time.now.utc.strftime('%Y%m%d_%H%M%S')}.json")
        @processed_data
      end

      private

      def load_workbook
        @workbook = Roo::Spreadsheet.open(@input_file)
        @workbook.default_sheet = @workbook.sheets.first
      end

      def process_roc
        @processed_data = {
          metadata: {
            filename: File.basename(@input_file),
            processed_at: Time.now.utc.iso8601,
            sheet_name: @workbook.default_sheet
          },
          evidence_items: []
        }

        # Find the columns we need
        columns = find_columns
        return unless columns[:requirement] && columns[:evidence]

        # Process each row
        (2..@workbook.last_row).each do |row_num|
          evidence = process_row(row_num, columns)
          @processed_data[:evidence_items] << evidence if evidence
        end

        # Add statistics
        @processed_data[:statistics] = calculate_statistics
        
        @logger.info("Processed #{@processed_data[:evidence_items].size} evidence items")
      end

      def find_columns
        columns = {}
        (1..@workbook.last_column).each do |col|
          header = @workbook.cell(1, col).to_s.strip.downcase
          columns[:requirement] = col if header.include?('requirement')
          columns[:evidence] = col if header.include?('evidence') || header.include?('response')
          columns[:status] = col if header.include?('status') || header.include?('result')
          columns[:date] = col if header.include?('date')
        end
        columns
      end

      def process_row(row_num, columns)
        requirement_text = @workbook.cell(row_num, columns[:requirement]).to_s.strip
        evidence_text = @workbook.cell(row_num, columns[:evidence]).to_s.strip
        status = columns[:status] ? @workbook.cell(row_num, columns[:status]).to_s.strip : nil
        date = columns[:date] ? @workbook.cell(row_num, columns[:date]).to_s.strip : nil

        return nil if evidence_text.empty?

        # Extract requirement IDs from the requirement text
        requirement_ids = extract_requirement_ids(requirement_text)
        return nil if requirement_ids.empty?

        # Use AI to analyze the evidence
        ai_analysis = analyze_evidence(evidence_text, requirement_text)

        {
          id: row_num - 1,
          requirement_ids: requirement_ids,
          evidence_text: evidence_text,
          status: status,
          date: date,
          ai_analysis: ai_analysis,
          extracted_requirements: extract_additional_requirements(evidence_text)
        }
      end

      def extract_requirement_ids(text)
        # Match both standard (1.2.3) and appendix (A1.2.3) requirements
        text.scan(/(?:^|\s)(?:A?\d+\.\d+(?:\.\d+)?(?:\.[a-z])?)/i).map(&:strip)
      end

      def analyze_evidence(evidence_text, requirement_text)
        @ai_service.analyze_evidence(evidence_text, requirement_text)
      end

      def extract_additional_requirements(evidence_text)
        @ai_service.extract_requirements_from_evidence(evidence_text)
      end

      def calculate_statistics
        total_items = @processed_data[:evidence_items].size
        total_requirements = @processed_data[:evidence_items].sum { |item| item[:requirement_ids].size }
        requirement_coverage = Hash.new(0)
        
        @processed_data[:evidence_items].each do |item|
          item[:requirement_ids].each do |req_id|
            requirement_coverage[req_id] += 1
          end
        end

        {
          total_evidence_items: total_items,
          total_requirements_referenced: total_requirements,
          unique_requirements: requirement_coverage.keys.size,
          requirements_by_frequency: requirement_coverage.transform_values(&:to_i),
          average_requirements_per_item: total_items.zero? ? 0 : (total_requirements.to_f / total_items).round(2)
        }
      end
    end
  end
end
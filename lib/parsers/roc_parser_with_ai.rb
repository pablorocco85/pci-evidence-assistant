require 'pdf-reader'
require_relative 'base_parser'
require_relative '../ai/shopify_ai_client'

module PCIEvidence
  module Parsers
    class ROCParserWithAI < BaseParser
      def initialize(roc_file, requirements_data, logger: nil)
        super(logger: logger)
        @roc_file = roc_file
        @requirements_data = requirements_data # From PriorityToolParser
        @ai_client = AI::ShopifyAIClient.new(logger: logger)
        @processed_data = nil
      end

      def parse
        @logger.info("Parsing ROC with AI assistance: #{@roc_file}")
        extract_roc_content
        process_requirements
        save_results
      end

      private

      def extract_roc_content
        @processed_data = {
          metadata: {
            roc_file: File.basename(@roc_file),
            processed_at: Time.now.utc.iso8601
          },
          requirements: {}
        }

        reader = PDF::Reader.new(@roc_file)
        current_requirement = nil
        current_text = []

        reader.pages.each do |page|
          text = page.text
          
          # Look for requirement headers
          if text =~ /Requirement (\d+\.\d+(\.\d+)?([a-z])?)/i
            # Process previous requirement if exists
            process_requirement_content(current_requirement, current_text.join("\n")) if current_requirement
            
            # Start new requirement
            current_requirement = normalize_requirement_reference($1)
            current_text = []
          end

          current_text << text if current_requirement
        end

        # Process last requirement
        process_requirement_content(current_requirement, current_text.join("\n")) if current_requirement
      end

      def process_requirement_content(requirement, content)
        return unless requirement && @requirements_data[:requirements][requirement]

        # Use AI to extract relevant parts
        prompt = generate_extraction_prompt(requirement, content)
        result = @ai_client.generate_response(prompt)
        
        parsed_result = parse_ai_response(result)
        
        @processed_data[:requirements][requirement] = {
          requirement_text: @requirements_data[:requirements][requirement][:requirement_text],
          evidence_observed: parsed_result[:evidence],
          testing_procedures: parsed_result[:procedures],
          assessor_notes: parsed_result[:notes],
          compliance_status: parsed_result[:status],
          evidence_patterns: identify_patterns(parsed_result[:evidence])
        }
      end

      def generate_extraction_prompt(requirement, content)
        <<~PROMPT
        Extract key information from this ROC section for PCI DSS requirement #{requirement}.
        Focus on these specific parts:
        1. Evidence Observed (specific evidence provided)
        2. Testing Procedures (how the evidence was validated)
        3. Assessor Notes (any additional context)
        4. Compliance Status (In Place, Not in Place, etc.)

        Format the response as JSON with these keys:
        {
          "evidence": ["item1", "item2", ...],
          "procedures": ["step1", "step2", ...],
          "notes": ["note1", "note2", ...],
          "status": "status"
        }

        ROC Content:
        #{content}
        PROMPT
      end

      def parse_ai_response(response)
        begin
          JSON.parse(response, symbolize_names: true)
        rescue JSON::ParserError
          @logger.error("Failed to parse AI response as JSON")
          {
            evidence: [],
            procedures: [],
            notes: [],
            status: "Unknown"
          }
        end
      end

      def identify_patterns(evidence_items)
        patterns = []
        evidence_items.each do |item|
          patterns.concat(identify_evidence_patterns(item))
        end
        patterns.uniq
      end

      def save_results
        return unless @processed_data

        filename = "roc_analysis_with_ai_#{Time.now.strftime('%Y%m%d_%H%M%S')}.json"
        save_processed_data(@processed_data, filename)
        @processed_data
      end
    end
  end
end

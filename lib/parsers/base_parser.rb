require 'logger'
require 'json'

module PCIEvidence
  module Parsers
    class BaseParser
      attr_reader :logger

      def initialize(logger: nil)
        @logger = logger || Logger.new($stdout)
        @logger.level = Logger::INFO
      end

      protected

      def normalize_requirement_reference(ref)
        # Clean and standardize requirement references
        # e.g., "1.2.3" or "1.2.3.a" or "Req. 1.2.3"
        ref = ref.to_s.strip
        ref = ref.gsub(/^Req\.\s*/, '')
        ref = ref.gsub(/\s+/, '')
        ref.downcase
      end

      def extract_requirement_parts(ref)
        # Split requirement into parts
        # e.g., "1.2.3.a" -> { major: 1, minor: 2, sub: 3, part: 'a' }
        parts = ref.split('.')
        {
          major: parts[0].to_i,
          minor: parts[1]&.to_i,
          sub: parts[2]&.to_i,
          part: parts[3]
        }
      end

      def validate_requirement_reference(ref)
        # Basic validation of requirement format
        normalized = normalize_requirement_reference(ref)
        parts = extract_requirement_parts(normalized)
        
        valid = parts[:major].positive? &&
                (parts[:minor].nil? || parts[:minor].positive?) &&
                (parts[:sub].nil? || parts[:sub].positive?)
        
        unless valid
          @logger.warn("Invalid requirement reference: #{ref}")
          return false
        end
        
        true
      end

      def save_processed_data(data, filename)
        # Save processed data to JSON
        output_path = File.join('data', 'processed', filename)
        File.write(output_path, JSON.pretty_generate(data))
        @logger.info("Saved processed data to #{output_path}")
      end

      def load_processed_data(filename)
        # Load previously processed data
        input_path = File.join('data', 'processed', filename)
        return nil unless File.exist?(input_path)
        
        JSON.parse(File.read(input_path))
      end
    end
  end
end

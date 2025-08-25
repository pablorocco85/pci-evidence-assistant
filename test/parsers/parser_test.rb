require_relative '../test_helper'

module PCIEvidence
  class ParserTest < Minitest::Test
    def setup
      @logger = TestLogger.new
      
      # Input files
      @questionnaire_file = Dir.glob(File.join('data', 'input', 'questionnaires', '*.xlsx')).first
      @roc_file = Dir.glob(File.join('data', 'input', 'historical_rocs', '*.pdf')).first
      @standard_file = Dir.glob(File.join('data', 'input', 'standards', '*prioritized*.xlsx')).first
      
      assert @questionnaire_file, "No questionnaire file found"
      assert @roc_file, "No ROC file found"
      assert @standard_file, "No prioritized approach file found"
    end

    def test_questionnaire_parsing
      parser = Parsers::QuestionnaireParser.new(@questionnaire_file, logger: @logger)
      result = parser.parse
      
      # Basic structure tests
      assert result[:metadata], "No metadata in result"
      assert result[:requests], "No requests in result"
      assert result[:requests].is_a?(Array), "Requests is not an array"
      
      # Content tests
      unless result[:requests].empty?
        first_request = result[:requests].first
        assert first_request[:id], "Request has no ID"
        assert first_request[:raw_requirement], "Request has no requirement reference"
        assert first_request[:normalized_requirement], "Request has no normalized requirement"
        assert first_request[:request_text], "Request has no text"
        
        puts "\nSample Questionnaire Request:"
        puts JSON.pretty_generate(first_request)
      end
    end

    def test_roc_parsing
      parser = Parsers::ROCParser.new(@roc_file, logger: @logger)
      result = parser.parse
      
      # Basic structure tests
      assert result[:metadata], "No metadata in result"
      assert result[:requirements], "No requirements in result"
      
      # Content tests
      unless result[:requirements].empty?
        req_key = result[:requirements].keys.first
        req_data = result[:requirements][req_key]
        
        assert req_data[:testing_procedures], "No testing procedures"
        assert req_data[:evidence_observed], "No evidence observed"
        assert req_data[:evidence_patterns], "No evidence patterns"
        assert req_data[:compliance_status], "No compliance status"
        
        puts "\nSample ROC Requirement:"
        puts JSON.pretty_generate({
          requirement: req_key,
          data: req_data
        })
      end
    end

    def test_requirement_matching
      # Parse both files
      q_parser = Parsers::QuestionnaireParser.new(@questionnaire_file, logger: @logger)
      q_result = q_parser.parse
      
      r_parser = Parsers::ROCParser.new(@roc_file, logger: @logger)
      r_result = r_parser.parse
      
      matches = 0
      patterns = 0
      
      # Test requirement matching
      q_result[:requests].each do |request|
        req = request[:normalized_requirement]
        if r_result[:requirements][req]
          matches += 1
          req_patterns = r_result[:requirements][req][:evidence_patterns]
          patterns += 1 if req_patterns&.any?
        end
      end
      
      puts "\nMatching Statistics:"
      puts "Total requests: #{q_result[:requests].size}"
      puts "Matched with ROC: #{matches}"
      puts "With evidence patterns: #{patterns}"
      
      assert matches.positive?, "No matching requirements found"
    end
  end
end

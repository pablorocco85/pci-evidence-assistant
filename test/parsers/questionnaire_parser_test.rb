require_relative '../test_helper'
require 'parsers/questionnaire_parser'

module PCIEvidence
  module Parsers
    class QuestionnaireParserTest < Minitest::Test
      include TestHelpers

      def setup
        @mock_workbook = mock('workbook')
        Roo::Spreadsheet.stubs(:open).returns(@mock_workbook)

        # Mock basic workbook methods
        @mock_workbook.stubs(:sheets).returns(['Sheet1'])
        @mock_workbook.stubs(:default_sheet=)
        @mock_workbook.stubs(:default_sheet).returns('Sheet1')
        @mock_workbook.stubs(:last_row).returns(7)
        @mock_workbook.stubs(:last_column).returns(4)

        # Mock the header row
        @mock_workbook.stubs(:cell).with(1, 1).returns('PCI DSS 4.0.1 ROC (Standalone)')
        @mock_workbook.stubs(:cell).with(1, 2).returns('Request Name')
        @mock_workbook.stubs(:cell).with(1, 3).returns('Request Text')
        @mock_workbook.stubs(:cell).with(1, 4).returns('Additional Context')

        # Mock data rows
        mock_data_rows

        @parser = QuestionnaireParser.new('dummy.xlsx')
      end

      def test_parse_valid_questionnaire
        result = @parser.parse

        assert_processed_data_valid(result)
        assert_equal 5, result[:evidence_requests].size, "Should have 5 valid evidence requests"
        
        # Check first request
        first_request = result[:evidence_requests].first
        assert_equal "Firewall Rules", first_request[:name]
        assert_equal "Review firewall rules", first_request[:text]
        assert_equal ["1.2.3"], first_request[:requirement_refs]

        # Check request with multiple requirements
        multi_req = result[:evidence_requests].find { |r| r[:name] == "Security Policies" }
        assert_equal ["12.3.1", "12.5.1"], multi_req[:requirement_refs], "Requirements should be sorted"

        # Check appendix requirement
        appendix_req = result[:evidence_requests].find { |r| r[:name] == "Custom Controls" }
        assert_equal ["a1.2.3"], appendix_req[:requirement_refs]

        # Check ES requirement
        es_req = result[:evidence_requests].find { |r| r[:name] == "Valid Entry" }
        assert_equal ["es1.2"], es_req[:requirement_refs]

        # Check testing procedure
        test_req = result[:evidence_requests].find { |r| r[:name] == "Testing Procedure" }
        assert_equal ["1.2.3.a"], test_req[:requirement_refs]
      end

      def test_invalid_requirement_ids
        # Mock invalid data
        @mock_workbook.stubs(:last_row).returns(5)
        @mock_workbook.stubs(:cell).with(2, 1).returns('es')
        @mock_workbook.stubs(:cell).with(2, 2).returns('Invalid Entry')
        @mock_workbook.stubs(:cell).with(2, 3).returns('Should be ignored')
        @mock_workbook.stubs(:cell).with(2, 4).returns('Not a requirement')

        @mock_workbook.stubs(:cell).with(3, 1).returns('1.x.3')
        @mock_workbook.stubs(:cell).with(3, 2).returns('Invalid Format')
        @mock_workbook.stubs(:cell).with(3, 3).returns('Should be ignored')
        @mock_workbook.stubs(:cell).with(3, 4).returns('Bad format')

        @mock_workbook.stubs(:cell).with(4, 1).returns('A1')
        @mock_workbook.stubs(:cell).with(4, 2).returns('Incomplete Appendix')
        @mock_workbook.stubs(:cell).with(4, 3).returns('Should be ignored')
        @mock_workbook.stubs(:cell).with(4, 4).returns('Missing numbers')

        @mock_workbook.stubs(:cell).with(5, 1).returns('12')
        @mock_workbook.stubs(:cell).with(5, 2).returns('Incomplete Requirement')
        @mock_workbook.stubs(:cell).with(5, 3).returns('Should be ignored')
        @mock_workbook.stubs(:cell).with(5, 4).returns('Missing minor version')

        result = @parser.parse
        puts "Input requirements:"
        puts "- es"
        puts "- 1.x.3"
        puts "- A1"
        puts "- 12"
        puts "Pattern: #{QuestionnaireParser::VALID_REQUIREMENT_PATTERN.source}"
        puts "Evidence requests found: #{result[:evidence_requests].inspect}"
        assert_equal 0, result[:evidence_requests].size, "Should have no valid evidence requests"
      end

      def test_empty_questionnaire
        @mock_workbook.stubs(:last_row).returns(1)
        result = @parser.parse
        assert_equal 0, result[:evidence_requests].size, "Should have no evidence requests"
      end

      def test_missing_requirement_column
        @mock_workbook.stubs(:cell).with(1, 1).returns('Wrong Column Header')
        result = @parser.parse
        assert_equal 0, result[:evidence_requests].size, "Should have no evidence requests without requirement column"
      end

      def test_duplicate_requirements
        @mock_workbook.stubs(:last_row).returns(3)
        @mock_workbook.stubs(:cell).with(2, 1).returns('1.2.3')
        @mock_workbook.stubs(:cell).with(2, 2).returns('First Request')
        @mock_workbook.stubs(:cell).with(2, 3).returns('First description')
        @mock_workbook.stubs(:cell).with(2, 4).returns('Context 1')

        @mock_workbook.stubs(:cell).with(3, 1).returns('1.2.3')
        @mock_workbook.stubs(:cell).with(3, 2).returns('Second Request')
        @mock_workbook.stubs(:cell).with(3, 3).returns('Second description')
        @mock_workbook.stubs(:cell).with(3, 4).returns('Context 2')

        result = @parser.parse
        assert_equal 2, result[:evidence_requests].size, "Should allow duplicate requirements"
        assert_equal ["1.2.3"], result[:evidence_requests][0][:requirement_refs]
        assert_equal ["1.2.3"], result[:evidence_requests][1][:requirement_refs]
      end

      private

      def mock_data_rows
        # Row 2: Single requirement
        @mock_workbook.stubs(:cell).with(2, 1).returns('1.2.3')
        @mock_workbook.stubs(:cell).with(2, 2).returns('Firewall Rules')
        @mock_workbook.stubs(:cell).with(2, 3).returns('Review firewall rules')
        @mock_workbook.stubs(:cell).with(2, 4).returns('Check all rules')

        # Row 3: Multiple requirements
        @mock_workbook.stubs(:cell).with(3, 1).returns('12.5.1;12.3.1')
        @mock_workbook.stubs(:cell).with(3, 2).returns('Security Policies')
        @mock_workbook.stubs(:cell).with(3, 3).returns('Review security policies')
        @mock_workbook.stubs(:cell).with(3, 4).returns('Including all updates')

        # Row 4: Appendix requirement
        @mock_workbook.stubs(:cell).with(4, 1).returns('A1.2.3')
        @mock_workbook.stubs(:cell).with(4, 2).returns('Custom Controls')
        @mock_workbook.stubs(:cell).with(4, 3).returns('Review custom controls')
        @mock_workbook.stubs(:cell).with(4, 4).returns('For service providers')

        # Row 5: Invalid ES entry
        @mock_workbook.stubs(:cell).with(5, 1).returns('es')
        @mock_workbook.stubs(:cell).with(5, 2).returns('Invalid Entry')
        @mock_workbook.stubs(:cell).with(5, 3).returns('Should be ignored')
        @mock_workbook.stubs(:cell).with(5, 4).returns('Not a requirement')

        # Row 6: Valid ES entry
        @mock_workbook.stubs(:cell).with(6, 1).returns('ES1.2')
        @mock_workbook.stubs(:cell).with(6, 2).returns('Valid Entry')
        @mock_workbook.stubs(:cell).with(6, 3).returns('Should be processed')
        @mock_workbook.stubs(:cell).with(6, 4).returns('Enterprise security')

        # Row 7: Testing procedure
        @mock_workbook.stubs(:cell).with(7, 1).returns('1.2.3.a')
        @mock_workbook.stubs(:cell).with(7, 2).returns('Testing Procedure')
        @mock_workbook.stubs(:cell).with(7, 3).returns('Review testing procedures')
        @mock_workbook.stubs(:cell).with(7, 4).returns('Including evidence')
      end
    end
  end
end
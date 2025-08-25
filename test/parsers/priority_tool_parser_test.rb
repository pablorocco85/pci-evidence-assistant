require_relative '../test_helper'
require 'parsers/priority_tool_parser'

module PCIEvidence
  module Parsers
    class PriorityToolParserTest < Minitest::Test
      include TestHelpers

      def setup
        @mock_workbook = mock('workbook')
        Roo::Spreadsheet.stubs(:open).returns(@mock_workbook)

        # Mock basic workbook methods
        @mock_workbook.stubs(:sheets).returns([
          'Release Notes & Instructions',
          'Change Summary',
          'Prioritized Approach Summary',
          'Prioritized Approach Milestones',
          'Calcs',
          'Data Validation',
          'Sheet1',
          'Sheet2',
          'Sheet3'
        ])
        @mock_workbook.stubs(:default_sheet=)
        @mock_workbook.stubs(:default_sheet).returns('Prioritized Approach Milestones')
        @mock_workbook.stubs(:last_row).returns(7)
        @mock_workbook.stubs(:last_column).returns(4)

        # Mock milestone sheet header row
        @mock_workbook.stubs(:cell).with(1, 1).returns('PCI DSS Requirement')
        @mock_workbook.stubs(:cell).with(1, 2).returns('Description')
        @mock_workbook.stubs(:cell).with(1, 3).returns('Milestone')
        @mock_workbook.stubs(:cell).with(1, 4).returns('Notes')

        # Mock data rows
        mock_data_rows

        @parser = PriorityToolParser.new('dummy.xlsx')
      end

      def test_parse_valid_requirements
        result = @parser.parse
        puts "Result: #{result.inspect}"

        assert_processed_data_valid(result)
        assert_equal 5, result[:requirements].size, "Should have 5 valid requirements"
        
        # Check regular requirement
        req = result[:requirements]["1.2.3"]
        puts "Looking for 1.2.3: #{req.inspect}"
        assert_equal "1.2.3", req[:requirement_number]
        assert_equal "Configure firewall rules", req[:requirement_text]
        assert_equal true, req[:valid_requirement]

        # Check requirement with sub-requirements
        req = result[:requirements]["12.5.1"]
        puts "Looking for 12.5.1: #{req.inspect}"
        assert_equal "12.5.1", req[:requirement_number]
        assert_equal "Define security policies", req[:requirement_text]
        assert_equal 2, req[:sub_requirements].size
        assert_equal "12.5.1.a", req[:sub_requirements][0][:number]
        assert_equal "Document security policies", req[:sub_requirements][0][:text]
        assert_equal "12.5.1.b", req[:sub_requirements][1][:number]
        assert_equal "Review security policies", req[:sub_requirements][1][:text]

        # Check appendix requirement
        req = result[:requirements]["a1.1.2.3"]
        puts "Looking for a1.1.2.3: #{req.inspect}"
        assert_equal "A1.2.3", req[:requirement_number]
        assert_equal "Configure service provider controls", req[:requirement_text]
        assert_equal true, req[:valid_requirement]

        # Check requirement with milestone
        req = result[:requirements]["2.1.1"]
        puts "Looking for 2.1.1: #{req.inspect}"
        assert_equal "2.1.1", req[:requirement_number]
        assert_equal "Configure secure settings", req[:requirement_text]
        assert_equal 1, req[:milestone]
        assert_equal true, req[:valid_requirement]

        # Check requirement with applicability notes
        req = result[:requirements]["3.4.1"]
        puts "Looking for 3.4.1: #{req.inspect}"
        assert_equal "3.4.1", req[:requirement_number]
        assert_equal "Implement encryption", req[:requirement_text]
        assert_equal ["Note 1: Encryption required for sensitive data", "Note 2: Key management required"], req[:applicability_notes]
        assert_equal true, req[:valid_requirement]
      end

      def test_invalid_requirements
        # Mock invalid data
        @mock_workbook.stubs(:last_row).returns(5)

        # Mock all possible cell accesses
        (1..5).each do |row|
          (1..4).each do |col|
            @mock_workbook.stubs(:cell).with(row, col).returns('')
          end
        end

        # Mock milestone sheet header row
        @mock_workbook.stubs(:cell).with(1, 1).returns('PCI DSS Requirement')
        @mock_workbook.stubs(:cell).with(1, 2).returns('Description')
        @mock_workbook.stubs(:cell).with(1, 3).returns('Milestone')
        @mock_workbook.stubs(:cell).with(1, 4).returns('Notes')

        # Row 2: Invalid ES entry
        @mock_workbook.stubs(:cell).with(2, 1).returns('es')
        @mock_workbook.stubs(:cell).with(2, 2).returns('Invalid Entry')
        @mock_workbook.stubs(:cell).with(2, 3).returns('Should be ignored')

        # Row 3: Invalid format
        @mock_workbook.stubs(:cell).with(3, 1).returns('1.x.3')
        @mock_workbook.stubs(:cell).with(3, 2).returns('Invalid Format')
        @mock_workbook.stubs(:cell).with(3, 3).returns('Should be ignored')

        # Row 4: Incomplete appendix
        @mock_workbook.stubs(:cell).with(4, 1).returns('A1')
        @mock_workbook.stubs(:cell).with(4, 2).returns('Incomplete Appendix')
        @mock_workbook.stubs(:cell).with(4, 3).returns('Should be ignored')

        # Row 5: Incomplete requirement
        @mock_workbook.stubs(:cell).with(5, 1).returns('12')
        @mock_workbook.stubs(:cell).with(5, 2).returns('Incomplete Requirement')
        @mock_workbook.stubs(:cell).with(5, 3).returns('Should be ignored')

        result = @parser.parse
        assert_equal 0, result[:requirements].size, "Should have no valid requirements"
      end

      def test_empty_workbook
        @mock_workbook.stubs(:last_row).returns(1)

        # Mock all possible cell accesses
        (1..1).each do |row|
          (1..4).each do |col|
            @mock_workbook.stubs(:cell).with(row, col).returns('')
          end
        end

        result = @parser.parse
        assert_equal 0, result[:requirements].size, "Should have no requirements"
      end

      def test_missing_milestone_sheet
        @mock_workbook.stubs(:sheets).returns(['Sheet1'])
        result = @parser.parse
        assert_equal 0, result[:requirements].size, "Should have no requirements without milestone sheet"
      end

      def test_duplicate_requirements
        # Mock data with duplicate requirements
        @mock_workbook.stubs(:last_row).returns(3)

        # Mock all possible cell accesses
        (1..3).each do |row|
          (1..4).each do |col|
            @mock_workbook.stubs(:cell).with(row, col).returns('')
          end
        end

        # Mock milestone sheet header row
        @mock_workbook.stubs(:cell).with(1, 1).returns('PCI DSS Requirement')
        @mock_workbook.stubs(:cell).with(1, 2).returns('Description')
        @mock_workbook.stubs(:cell).with(1, 3).returns('Milestone')
        @mock_workbook.stubs(:cell).with(1, 4).returns('Notes')

        # Row 2: First version
        @mock_workbook.stubs(:cell).with(2, 1).returns('1.2.3')
        @mock_workbook.stubs(:cell).with(2, 2).returns('First version')
        @mock_workbook.stubs(:cell).with(2, 3).returns('Milestone 1')

        # Row 3: Second version
        @mock_workbook.stubs(:cell).with(3, 1).returns('1.2.3')
        @mock_workbook.stubs(:cell).with(3, 2).returns('Second version')
        @mock_workbook.stubs(:cell).with(3, 3).returns('Milestone 2')

        result = @parser.parse
        assert_equal 1, result[:requirements].size, "Should merge duplicate requirements"
        assert_equal "Second version", result[:requirements]["1.2.3"][:requirement_text], "Should use latest version"
      end

      private

      def mock_data_rows
        # Mock all possible cell accesses
        (1..7).each do |row|
          (1..4).each do |col|
            @mock_workbook.stubs(:cell).with(row, col).returns('')
          end
        end

        # Mock milestone sheet header row
        @mock_workbook.stubs(:cell).with(1, 1).returns('PCI DSS Requirement')
        @mock_workbook.stubs(:cell).with(1, 2).returns('Description')
        @mock_workbook.stubs(:cell).with(1, 3).returns('Milestone')
        @mock_workbook.stubs(:cell).with(1, 4).returns('Notes')

        # Row 2: Regular requirement
        @mock_workbook.stubs(:cell).with(2, 1).returns('1.2.3')
        @mock_workbook.stubs(:cell).with(2, 2).returns('Configure firewall rules')
        @mock_workbook.stubs(:cell).with(2, 3).returns('Milestone 2')

        # Row 3: Requirement with sub-requirements
        @mock_workbook.stubs(:cell).with(3, 1).returns('12.5.1')
        @mock_workbook.stubs(:cell).with(3, 2).returns('Define security policies')
        @mock_workbook.stubs(:cell).with(3, 3).returns('Milestone 3')
        @mock_workbook.stubs(:cell).with(3, 4).returns('12.5.1.a Document security policies, 12.5.1.b Review security policies')

        # Row 4: Appendix requirement
        @mock_workbook.stubs(:cell).with(4, 1).returns('A1.2.3')
        @mock_workbook.stubs(:cell).with(4, 2).returns('Configure service provider controls')
        @mock_workbook.stubs(:cell).with(4, 3).returns('Milestone 4')

        # Row 5: Requirement with milestone
        @mock_workbook.stubs(:cell).with(5, 1).returns('2.1.1')
        @mock_workbook.stubs(:cell).with(5, 2).returns('Configure secure settings')
        @mock_workbook.stubs(:cell).with(5, 3).returns('Milestone 1')

        # Row 6: Requirement with applicability notes
        @mock_workbook.stubs(:cell).with(6, 1).returns('3.4.1')
        @mock_workbook.stubs(:cell).with(6, 2).returns('Implement encryption')
        @mock_workbook.stubs(:cell).with(6, 3).returns('Milestone 2')
        @mock_workbook.stubs(:cell).with(6, 4).returns('Note 1: Encryption required for sensitive data, Note 2: Key management required')

        # Row 7: Empty row
        @mock_workbook.stubs(:cell).with(7, 1).returns('')
        @mock_workbook.stubs(:cell).with(7, 2).returns('')
        @mock_workbook.stubs(:cell).with(7, 3).returns('')
        @mock_workbook.stubs(:cell).with(7, 4).returns('')
      end
    end
  end
end
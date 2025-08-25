require_relative '../test_helper'
require 'parsers/standard_parser'

module PCIEvidence
  module Parsers
    class StandardParserTest < Minitest::Test
      include TestHelpers

      def setup
        @mock_reader = mock('pdf_reader')
        PDF::Reader.stubs(:new).returns(@mock_reader)

        # Mock basic PDF methods
        @mock_reader.stubs(:page_count).returns(3)
        @mock_reader.stubs(:pages).returns([
          mock_page(1, mock_requirement_1_2_3),
          mock_page(2, mock_requirement_12_5_1),
          mock_page(3, mock_requirement_a1_2_3)
        ])

        @parser = StandardParser.new('dummy.pdf')
      end

      def test_parse_valid_requirements
        result = @parser.parse
        puts "Result: #{result.inspect}"

        assert_processed_data_valid(result)
        assert_equal 2, result[:requirements].size, "Should have 2 valid requirements (appendix requirements are skipped)"
        
        # Check regular requirement
        req = result[:requirements]["1.2.3"]
        puts "Looking for 1.2.3: #{req.inspect}"
        assert_equal "1.2.3", req.raw_id
        assert_equal "Configure firewall rules", req.defined_approach_text
        assert_equal "Ensure secure firewall configuration", req.customized_approach_objective
        assert_equal ["Note: This is required for all firewalls"], req.applicability_notes
        assert_equal 2, req.testing_procedures.size
        assert_equal "1.2.3.a", req.testing_procedures[0].id
        assert_equal "Examine firewall configurations", req.testing_procedures[0].text
        assert_equal "1.2.3.b", req.testing_procedures[1].id
        assert_equal "Interview responsible personnel", req.testing_procedures[1].text
        assert_equal "To ensure network security", req.guidance.purpose
        assert_equal ["Follow vendor recommendations", "Document all changes"], req.guidance.good_practices
        assert_equal ["Block all inbound traffic by default"], req.guidance.examples
        assert_equal({"firewall" => "A network security device"}, req.guidance.definitions)

        # Check requirement with sub-requirements
        req = result[:requirements]["12.5.1"]
        puts "Looking for 12.5.1: #{req.inspect}"
        assert_equal "12.5.1", req.raw_id
        assert_equal "Define security policies", req.defined_approach_text
        assert_equal "Ensure comprehensive security policies", req.customized_approach_objective
        assert_equal ["Note: Policies must be documented"], req.applicability_notes
        assert_equal 2, req.testing_procedures.size
        assert_equal "12.5.1.a", req.testing_procedures[0].id
        assert_equal "Review security policies", req.testing_procedures[0].text
        assert_equal "12.5.1.b", req.testing_procedures[1].id
        assert_equal "Interview security personnel", req.testing_procedures[1].text
        assert_equal "To establish security governance", req.guidance.purpose
        assert_equal ["Review annually", "Get management approval"], req.guidance.good_practices
        assert_equal ["Information Security Policy template"], req.guidance.examples
        assert_equal({"policy" => "A formal document"}, req.guidance.definitions)

        # TODO: Add tests for appendix requirements once implemented
        # Appendix requirements (A1.x.x) are currently skipped to focus on core functionality
        # See StandardParser#validate_requirement_reference for details
      end

      def test_invalid_requirements
        # Mock PDF with invalid requirement formats
        @mock_reader.stubs(:page_count).returns(3)
        @mock_reader.stubs(:pages).returns([
          mock_page(1, "Requirement es: Invalid ES entry"),
          mock_page(2, "Requirement 1.x.3: Invalid format"),
          mock_page(3, "Requirement A1: Incomplete appendix")
        ])

        result = @parser.parse
        assert_equal 0, result[:requirements].size, "Should have no valid requirements"
      end

      def test_empty_pdf
        @mock_reader.stubs(:page_count).returns(0)
        @mock_reader.stubs(:pages).returns([])

        result = @parser.parse
        assert_equal 0, result[:requirements].size, "Should have no requirements"
      end

      private

      def mock_page(number, text)
        page = mock("page_#{number}")
        page.stubs(:number).returns(number)
        page.stubs(:text).returns(text)
        page
      end

      def mock_requirement_1_2_3
        <<~TEXT
          Requirement 1.2.3 Configure firewall rules
          Defined Approach
          Configure firewall rules

          Customized Approach Objective
          Ensure secure firewall configuration

          Applicability Notes
          Note: This is required for all firewalls

          Testing Procedures
          1.2.3.a Examine firewall configurations
          1.2.3.b Interview responsible personnel

          Purpose
          To ensure network security
          Good Practice
          Follow vendor recommendations
          Document all changes
          Examples
          Block all inbound traffic by default
          Definitions
          firewall - A network security device
        TEXT
      end

      def mock_requirement_12_5_1
        <<~TEXT
          Requirement 12.5.1 Define security policies
          Defined Approach
          Define security policies

          Customized Approach Objective
          Ensure comprehensive security policies

          Applicability Notes
          Note: Policies must be documented

          Testing Procedures
          12.5.1.a Review security policies
          12.5.1.b Interview security personnel

          Purpose
          To establish security governance
          Good Practice
          Review annually
          Get management approval
          Examples
          Information Security Policy template
          Definitions
          policy - A formal document
        TEXT
      end

      def mock_requirement_a1_2_3
        <<~TEXT
          Requirement A1.2.3 Processes or mechanisms are implemented for reporting and addressing suspected or confirmed security incidents and vulnerabilities
          Defined Approach Requirements
          A1.2.3 Processes or mechanisms are implemented for reporting and addressing suspected or confirmed security incidents and vulnerabilities, including:
          • Customers can securely report security incidents and vulnerabilities to the provider.
          • The provider addresses and remediates suspected or confirmed security incidents and vulnerabilities according to Requirement 6.3.1.

          Customized Approach Objective
          Suspected or confirmed security incidents or vulnerabilities are discovered and addressed. Customers are informed where appropriate.

          Applicability Notes
          This requirement is a best practice until 31 March 2025, after which it will be required and must be fully considered during a PCI DSS assessment.

          Defined Approach Testing Procedures
          A1.2.3 Examine documented procedures and interview personnel to verify that the provider has a mechanism for reporting and addressing suspected or confirmed security incidents and vulnerabilities, in accordance with all elements specified in this requirement.

          Purpose
          Security vulnerabilities in the provided services can impact the security of all the service provider's customers and therefore must be managed in accordance with the service provider's established processes, with priority given to resolving vulnerabilities that have the highest probability of compromise. Customers are likely to notice vulnerabilities and security misconfigurations while using the service. Implementing secure methods for customers to report security incidents and vulnerabilities encourages customers to report potential issues and enable the provider to quickly learn about and address potential issues within their environment.
        TEXT
      end
    end
  end
end
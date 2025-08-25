require 'minitest/autorun'
require 'minitest/mock'
require 'minitest/spec'
require 'mocha/minitest'
require 'logger'
require 'json'
require 'time'
require_relative 'support/quick_mock'

# Add lib to load path
$LOAD_PATH.unshift File.expand_path('../lib', __dir__)

# Configure logger for tests
module PCIEvidence
  class << self
    def logger
      @logger ||= Logger.new(nil)
    end
  end
end

# Helper methods for tests
module TestHelpers
  def fixture_path(filename)
    File.join(File.expand_path('../test/fixtures', __dir__), filename)
  end

  def read_fixture(filename)
    File.read(fixture_path(filename))
  end

  def create_temp_file(content, extension = '.txt')
    file = Tempfile.new(['test', extension])
    file.write(content)
    file.close
    file.path
  end

  def with_temp_file(content, extension = '.txt')
    file = create_temp_file(content, extension)
    yield file
  ensure
    File.unlink(file) if file && File.exist?(file)
  end

  def assert_requirement_valid(requirement)
    assert_kind_of PCIEvidence::Models::PCIRequirement, requirement
    assert requirement.id, "Requirement should have an ID"
    assert requirement.defined_approach, "Requirement should have a defined approach"
    assert_kind_of PCIEvidence::Models::RequirementApproach, requirement.defined_approach
  end

  def assert_evidence_request_valid(request)
    assert_kind_of PCIEvidence::Models::EvidenceRequest, request
    assert request.id, "Evidence request should have an ID"
    assert request.text, "Evidence request should have text"
    assert_kind_of Array, request.requirement_refs
  end

  def assert_testing_procedure_valid(procedure)
    assert_kind_of PCIEvidence::Models::TestingProcedure, procedure
    assert procedure.id, "Testing procedure should have an ID"
    assert procedure.text, "Testing procedure should have text"
    assert_kind_of Array, procedure.response_types
  end

  def assert_guidance_valid(guidance)
    assert_kind_of PCIEvidence::Models::Guidance, guidance
    assert guidance.purpose || guidance.good_practices || guidance.examples || guidance.definitions,
      "Guidance should have at least one component"
  end

  def assert_processed_data_valid(data)
    assert_kind_of Hash, data
    assert data[:metadata], "Processed data should have metadata"
    assert data[:metadata][:processed_at], "Metadata should have processed_at timestamp"
    assert data[:metadata][:filename], "Metadata should have filename"
  end

  def assert_requirement_id_valid(id)
    pattern = /^(?:a?\d+\.\d+(?:\.\d+)?(?:\.[a-z])?|ES\d+(?:\.\d+)?(?:\.[a-z])?)$/i
    assert_match pattern, id, "Requirement ID '#{id}' should match PCI DSS format"
  end

  def assert_no_duplicate_requirements(requirements)
    ids = requirements.map { |r| r.id.downcase }
    assert_equal ids.uniq.size, ids.size, "Found duplicate requirement IDs"
  end

  def assert_valid_json_output(file_path)
    assert File.exist?(file_path), "Output file should exist"
    json = JSON.parse(File.read(file_path))
    assert_kind_of Hash, json
    assert json["metadata"], "JSON should have metadata"
    assert json["metadata"]["processed_at"], "JSON should have processed_at timestamp"
  end
end
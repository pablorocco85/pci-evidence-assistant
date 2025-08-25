#!/usr/bin/env ruby

require_relative '../lib/parsers/questionnaire_parser'
require_relative '../lib/parsers/priority_tool_parser'
require_relative '../lib/parsers/standard_parser'
require_relative '../lib/models/pci_requirement_builder'

# Process evidence requests from questionnaire
puts "\n=== Processing Evidence Requests ==="
questionnaire_file = Dir.glob("data/input/questionnaires/*Evidence Request Listing.xlsx").first
if questionnaire_file
  puts "Found questionnaire: #{questionnaire_file}"
  parser = PCIEvidence::Parsers::QuestionnaireParser.new(questionnaire_file)
  requests = parser.parse
else
  puts "No questionnaire found in data/input/questionnaires/"
  exit 1
end

# Process PCI DSS requirements from priority tool
puts "\n=== Processing PCI DSS Requirements from Priority Tool ==="
priority_tool_file = Dir.glob("data/input/standards/Prioritized-Approach-Tool-For-PCI-DSS-v4_0_1.xlsx").first
if priority_tool_file
  puts "Found priority tool: #{priority_tool_file}"
  parser = PCIEvidence::Parsers::PriorityToolParser.new(priority_tool_file)
  requirements_data = parser.parse
else
  puts "No priority tool found in data/input/standards/"
  exit 1
end

# Process PCI DSS requirements from standard PDF
puts "\n=== Processing PCI DSS Requirements from Standard PDF ==="
standard_file = Dir.glob("data/input/standards/PCI-DSS-v4_0_1.pdf").first
if standard_file
  puts "Found standard: #{standard_file}"
  parser = PCIEvidence::Parsers::StandardParser.new(standard_file)
  standard_data = parser.parse
else
  puts "No standard found in data/input/standards/"
  exit 1
end

# Process ROC (currently disabled)
puts "\n=== ROC Processing (Currently Disabled) ==="
puts "ROC parsing will be enabled after AI integration is complete."

# Build complete requirement objects
puts "\n=== Building Complete Requirement Objects ==="
builder = PCIEvidence::Models::PCIRequirementBuilder.new
builder.add_from_standard(standard_data)
builder.add_from_priority_tool(requirements_data)
builder.add_from_questionnaire(requests)

complete_data = builder.build

# Save complete requirements
output_file = "data/processed/complete_requirements_#{Time.now.utc.strftime('%Y%m%d_%H%M%S')}.json"
File.open(output_file, 'w') do |f|
  f.write(JSON.pretty_generate(complete_data))
end

# Analyze requirement coverage
puts "\n=== Analyzing Requirement Coverage ==="
puts "Coverage Analysis:"
puts "- Total requirements: #{complete_data[:statistics][:total_requirements]}"
puts "- Total evidence requests: #{complete_data[:statistics][:total_evidence_requests]}"
puts "- Requirements with evidence requests: #{complete_data[:statistics][:requirements_with_evidence_requests]}"

distribution = complete_data[:statistics][:evidence_requests_per_requirement]
puts "\nEvidence Request Distribution:"
puts "- Minimum evidence requests per requirement: #{distribution[:min]}"
puts "- Maximum evidence requests per requirement: #{distribution[:max]}"
puts "- Average evidence requests per requirement: #{distribution[:average]}"

# Show requirements with most evidence requests
puts "\nTop 10 Requirements by Evidence Request Count:"
distribution[:distribution]
  .sort_by { |_, count| -count }
  .first(10)
  .each do |req_id, count|
    puts "  #{req_id}: #{count} evidence requests"
  end

# Show requirements with no evidence requests
puts "\nRequirements with No Evidence Requests:"
no_evidence = complete_data[:requirements].keys - distribution[:distribution].keys
no_evidence.sort.each_slice(5) do |group|
  puts "  #{group.join(', ')}"
end
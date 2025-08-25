# Only require Quick if it's not already defined (for testing)
require 'quick' unless defined?(Quick)

module PCIEvidence
  module Services
    class AIService
      DEFAULT_MODEL = 'gpt-4.1'
      ALTERNATIVE_MODEL = 'google:gemini-2.5-pro'

      PROXY_URL = 'https://proxy-shopify-ai.local.shop.dev'
      FALLBACK_PROXY_URL = 'http://proxy-shopify-ai.local.shop.dev'

      def initialize(model: DEFAULT_MODEL, logger: nil)
        @model = model
        @logger = logger || Logger.new(STDOUT)
        configure_quick_client
      end

      private

      def configure_quick_client
        Quick.configure do |config|
          # Use local proxy that handles token rotation
          config.base_url = PROXY_URL
          config.fallback_url = FALLBACK_PROXY_URL
          
          # No need to set auth token when using dev proxy
          config.auth_token = nil
          
          # Configure timeouts
          config.timeout = 30  # 30 seconds
          config.open_timeout = 5  # 5 seconds
          
          # Configure retries
          config.max_retries = 3
          config.retry_interval = 1  # 1 second
        end
      rescue => e
        @logger.error("Failed to configure Quick client: #{e.message}")
        raise "AI Service configuration failed: #{e.message}"
      end

      class AIError < StandardError; end
      class ModelError < AIError; end
      class ValidationError < AIError; end
      class RateLimitError < AIError; end
      class TimeoutError < AIError; end

      def analyze_evidence(evidence_text, requirement_context)
        @logger.info("Analyzing evidence for requirement context using #{@model}")
        
        messages = [
          {
            role: "system",
            content: "You are a PCI DSS compliance expert. Your task is to analyze evidence provided and determine if it satisfies the requirement context. Focus on completeness, accuracy, and relevance."
          },
          {
            role: "user",
            content: format_analysis_prompt(evidence_text, requirement_context)
          }
        ]

        with_error_handling do
          response = make_ai_request(:chat, messages)
          validate_response(response)
          parse_analysis_response(response)
        end
      end

      private

      def make_ai_request(method, content, retries: 2)
        attempt = 0
        begin
          attempt += 1
          case method
          when :chat
            Quick.ai.chat(content, default_chat_params)
          when :ask
            Quick.ai.ask(content, default_ask_params)
          else
            raise ArgumentError, "Unknown AI request method: #{method}"
          end
        rescue => e
          if should_retry?(e) && attempt <= retries
            @logger.warn("AI request failed (attempt #{attempt}/#{retries + 1}): #{e.message}")
            if e.is_a?(RateLimitError) || e.message.include?('rate limit')
              sleep(2 ** attempt) # Exponential backoff
            end
            retry
          elsif should_fallback?(e)
            @logger.warn("Falling back to alternative model due to error: #{e.message}")
            fallback_request(method, content)
          else
            raise map_error(e)
          end
        end
      end

      def default_chat_params
        {
          model: @model,
          temperature: 0.3,
          max_tokens: 1000,
          top_p: 0.9,
          frequency_penalty: 0.1,
          presence_penalty: 0.1
        }
      end

      def default_ask_params
        {
          model: @model,
          temperature: 0.3,
          max_tokens: 500
        }
      end

      def with_error_handling
        yield
      rescue AIError => e
        @logger.error("AI Service error: #{e.class} - #{e.message}")
        raise
      rescue StandardError => e
        @logger.error("Unexpected error in AI Service: #{e.class} - #{e.message}")
        raise AIError, "AI Service failed: #{e.message}"
      end

      def should_retry?(error)
        error.is_a?(TimeoutError) ||
          error.is_a?(RateLimitError) ||
          error.message.include?('timeout') ||
          error.message.include?('rate limit') ||
          error.message.include?('server error')
      end

      def should_fallback?(error)
        error.is_a?(ModelError) ||
          error.message.include?('model') ||
          error.message.include?('capacity')
      end

      def fallback_request(method, content)
        original_model = @model
        @model = ALTERNATIVE_MODEL
        @logger.info("Attempting fallback request with #{@model}")
        
        begin
          make_ai_request(method, content, retries: 1)
        ensure
          @model = original_model
        end
      end

      def map_error(error)
        case error.message
        when /timeout/i, /deadline/i
          TimeoutError.new("Request timed out: #{error.message}")
        when /rate limit/i, /too many requests/i
          RateLimitError.new("Rate limit exceeded: #{error.message}")
        when /model/i, /capacity/i
          ModelError.new("Model error: #{error.message}")
        else
          AIError.new("AI request failed: #{error.message}")
        end
      end

      # Response schemas for different types of analysis
      RESPONSE_SCHEMAS = {
        evidence_analysis: {
          required_fields: [
            'completeness',     # How complete is the evidence (percentage or score)
            'relevance',        # How relevant is the evidence to the requirement
            'gaps',            # Any identified gaps in the evidence
            'recommendations'   # Suggestions for improvement
          ],
          optional_fields: [
            'confidence_score', # AI's confidence in its analysis
            'references',       # Any referenced documents or standards
            'uncertainty_flags' # Specific areas where the analysis is uncertain
          ],
          field_validations: {
            'completeness' => ->(val) { val.is_a?(Numeric) && (0..100).include?(val) || 
                                      val.is_a?(String) && val.match?(/^\d{1,3}%$/) ||
                                      ['high', 'medium', 'low'].include?(val.to_s.downcase) },
            'relevance' => ->(val) { ['high', 'medium', 'low', 'uncertain'].include?(val.to_s.downcase) },
            'gaps' => ->(val) { val.is_a?(Array) && val.all? { |gap| gap.is_a?(String) && !gap.empty? } }
          }
        },

        uncertain_response: {
          required_fields: [
            'confidence_level',      # How confident is the AI in its draft response
            'draft_response',        # The potential response
            'uncertainty_reasons',   # Why the AI is uncertain
            'verification_needed'    # What needs to be verified
          ],
          optional_fields: [
            'alternative_approaches', # Other ways to handle this
            'expert_consultation',    # Whether human expert review is recommended
            'data_gaps'              # Missing information that would help
          ],
          field_validations: {
            'confidence_level' => ->(val) { (0..100).include?(val.to_i) },
            'uncertainty_reasons' => ->(val) { val.is_a?(Array) && val.length >= 1 },
            'verification_needed' => ->(val) { val.is_a?(Array) && val.all? { |v| v.is_a?(String) && !v.empty? } }
          }
        },

        guidance_response: {
          required_fields: [
            'recommendation_type',   # Type of guidance (process, technical, policy)
            'primary_guidance',      # Main recommendation
            'rationale',            # Why this is recommended
            'next_steps'            # Immediate actions to take
          ],
          optional_fields: [
            'alternative_options',   # Other approaches to consider
            'prerequisites',         # What needs to be in place first
            'risks',                # Potential risks to consider
            'timeline_estimate'      # Estimated time to implement
          ],
          field_validations: {
            'recommendation_type' => ->(val) { ['process', 'technical', 'policy', 'compliance'].include?(val.downcase) },
            'next_steps' => ->(val) { val.is_a?(Array) && val.all? { |step| step.is_a?(String) && !step.empty? } }
          }
        },
        requirement_extraction: {
          required_fields: [
            'requirement_id',   # The identified PCI requirement ID
            'requirement_text', # The actual requirement text
            'evidence_match',   # How well the evidence matches (high/medium/low)
            'justification'     # Why this requirement was identified
          ],
          optional_fields: [
            'related_requirements', # Other potentially relevant requirements
            'testing_procedures'    # Relevant testing procedures
          ],
          field_validations: {
            'requirement_id' => ->(val) { val.match?(/^(?:\d+\.\d+(?:\.\d+)?(?:\.[a-z])?|A\d+\.\d+(?:\.\d+)?(?:\.[a-z])?)$/i) },
            'requirement_text' => ->(val) { val.is_a?(String) && !val.strip.empty? },
            'evidence_match' => ->(val) { ['high', 'medium', 'low'].include?(val.to_s.downcase) },
            'justification' => ->(val) { val.is_a?(String) && !val.strip.empty? },
            'related_requirements' => ->(val) { val.is_a?(Array) && val.all? { |id| id.match?(/^(?:\d+\.\d+(?:\.\d+)?(?:\.[a-z])?|A\d+\.\d+(?:\.\d+)?(?:\.[a-z])?)$/i) } },
            'testing_procedures' => ->(val) { val.is_a?(Array) && val.all? { |id| id.match?(/^(?:\d+\.\d+(?:\.\d+)?(?:\.[a-z])?|A\d+\.\d+(?:\.\d+)?(?:\.[a-z])?)$/i) } }
          }
        },
        interview_evidence: {
          required_fields: [
            'interview_focus',  # What should be asked/verified
            'key_points',       # Critical points to cover
            'expected_evidence' # What evidence should result from interview
          ],
          optional_fields: [
            'suggested_questions', # Specific questions to ask
            'documentation_needs'  # Additional documentation needed
          ],
          field_validations: {
            'interview_focus' => ->(val) { val.is_a?(String) && !val.strip.empty? },
            'key_points' => ->(val) { val.is_a?(Array) && val.any? && val.all? { |point| point.is_a?(String) && !point.strip.empty? } },
            'expected_evidence' => ->(val) { val.is_a?(String) && !val.strip.empty? },
            'suggested_questions' => ->(val) { val.is_a?(Array) && val.all? { |q| q.is_a?(String) && !q.strip.empty? } },
            'documentation_needs' => ->(val) { val.is_a?(Array) && val.all? { |doc| doc.is_a?(String) && !doc.strip.empty? } }
          }
        },
        gcp_evidence: {
          required_fields: [
            'resource_type',    # Type of GCP resource
            'control_mapping',  # How it maps to PCI controls
            'configuration',    # Required configuration state
            'validation_steps'  # How to validate compliance
          ],
          optional_fields: [
            'audit_logs',       # Required audit logging
            'monitoring_needs'  # Additional monitoring requirements
          ],
          field_validations: {
            'resource_type' => ->(val) { val.is_a?(String) && !val.strip.empty? },
            'control_mapping' => ->(val) { val.is_a?(String) && !val.strip.empty? },
            'configuration' => ->(val) { val.is_a?(String) && !val.strip.empty? },
            'validation_steps' => ->(val) { val.is_a?(Array) && val.any? && val.all? { |step| step.is_a?(String) && !step.strip.empty? } },
            'audit_logs' => ->(val) { val.is_a?(Array) && val.all? { |log| log.is_a?(String) && !log.strip.empty? } },
            'monitoring_needs' => ->(val) { val.is_a?(Array) && val.all? { |need| need.is_a?(String) && !need.strip.empty? } }
          }
        }
      }.freeze

      def validate_response(response, type = :general)
        raise ValidationError, "Empty response received" if response.nil? || response.empty?
        
        # Basic format validation
        if response.is_a?(Hash)
          raise ValidationError, "Invalid response format" unless response['choices']&.any?
          
          # Extract the actual content from the response
          content = response['choices'].first['message']['content']
          
          # Parse JSON content if it's a string
          begin
            parsed_content = content.is_a?(String) ? JSON.parse(content) : content
          rescue JSON::ParserError
            @logger.warn("Response content is not JSON, skipping schema validation")
            return response
          end

          # Schema validation if we have a schema for this type
          if schema = RESPONSE_SCHEMAS[type]
            validate_against_schema(parsed_content, schema)
          end
        end
        
        response
      end

      private

      def validate_against_schema(content, schema)
        # Check required fields
        schema[:required_fields].each do |field|
          unless content.key?(field)
            raise ValidationError, "Missing required field: #{field}"
          end
        end

        # Log warning for missing optional fields
        schema[:optional_fields].each do |field|
          unless content.key?(field)
            @logger.warn("Missing optional field in response: #{field}")
          end
        end

        # Run field-specific validations
        if schema[:field_validations]
          schema[:field_validations].each do |field, validator|
            if content.key?(field)
              begin
                unless validator.call(content[field])
                  raise ValidationError, "Invalid value for field '#{field}': #{content[field]}"
                end
              rescue StandardError => e
                @logger.error("Validation error for field '#{field}': #{e.message}")
                raise ValidationError, "Validation failed for field '#{field}': #{content[field]}"
              end
            end
          end
        end

        # General validation for array fields
        content.each do |key, value|
          if value.is_a?(Array)
            if value.empty?
              @logger.warn("Empty array found for field: #{key}")
            else
              # Validate array elements are not empty strings or nil
              value.each_with_index do |element, index|
                if element.nil? || (element.is_a?(String) && element.strip.empty?)
                  @logger.warn("Empty element found in array '#{key}' at index #{index}")
                end
              end
            end
          end
        end

        # Additional type checking for common fields
        if content.key?('confidence_score') && !content['confidence_score'].is_a?(Numeric)
          raise ValidationError, "confidence_score must be numeric"
        end

        if content.key?('timestamp')
          begin
            Time.parse(content['timestamp'])
          rescue ArgumentError
            raise ValidationError, "Invalid timestamp format"
          end
        end
      end

      def extract_requirements_from_evidence(evidence_text)
        @logger.info("Extracting requirements from evidence using #{@model}")
        
        messages = [
          {
            role: "system",
            content: "You are a PCI DSS compliance expert. Your task is to identify all PCI DSS requirements that this evidence might satisfy. Look for technical details, processes, and controls that align with specific requirements."
          },
          {
            role: "user",
            content: format_extraction_prompt(evidence_text)
          }
        ]

        response = Quick.ai.chat(messages, {
          model: @model,
          temperature: 0.2, # Even lower temperature for precise requirement matching
          max_tokens: 1000,
          top_p: 0.9,
          frequency_penalty: 0.1,
          presence_penalty: 0.1
        })

        parse_extraction_response(response)
      end

      def suggest_evidence_improvements(evidence_text, requirement_context)
        @logger.info("Suggesting evidence improvements using #{@model}")
        
        messages = [
          {
            role: "system",
            content: "You are a PCI DSS compliance expert. Your task is to suggest improvements to the provided evidence to better satisfy the requirement context. Focus on gaps, clarity, and completeness."
          },
          {
            role: "user",
            content: format_improvement_prompt(evidence_text, requirement_context)
          }
        ]

        response = Quick.ai.chat(messages, {
          model: @model,
          temperature: 0.5, # Higher temperature for creative improvement suggestions
          max_tokens: 1500,
          top_p: 0.9,
          frequency_penalty: 0.2,
          presence_penalty: 0.2
        })

        parse_improvement_response(response)
      end

      private

      def format_analysis_prompt(evidence_text, requirement_context)
        <<~PROMPT
          You are a PCI DSS compliance expert. Analyze the following evidence and provide a structured response in JSON format.

          Requirement Context:
          #{requirement_context}

          Evidence Provided:
          #{evidence_text}

          Required Response Format:
          {
            "completeness": <number 0-100 or "high"/"medium"/"low">,
            "relevance": <"high"/"medium"/"low"/"uncertain">,
            "gaps": [
              <array of specific gaps identified>
            ],
            "recommendations": [
              <array of specific recommendations>
            ],
            "confidence_score": <number 0-100>,
            "references": [
              <array of relevant documentation or standards>
            ],
            "uncertainty_flags": [
              <array of specific areas where analysis is uncertain>
            ]
          }

          If you are uncertain about your analysis, use this format instead:
          {
            "confidence_level": <number 0-100>,
            "draft_response": <your potential analysis>,
            "uncertainty_reasons": [
              <array of reasons for uncertainty>
            ],
            "verification_needed": [
              <array of items that need verification>
            ],
            "alternative_approaches": [
              <array of other ways to analyze this>
            ],
            "expert_consultation": <boolean>,
            "data_gaps": [
              <array of missing information>
            ]
          }

          If you can't analyze but can provide guidance, use this format:
          {
            "recommendation_type": <"process"/"technical"/"policy"/"compliance">,
            "primary_guidance": <main recommendation>,
            "rationale": <explanation>,
            "next_steps": [
              <array of immediate actions>
            ],
            "alternative_options": [
              <array of alternative approaches>
            ],
            "prerequisites": [
              <array of requirements>
            ],
            "risks": [
              <array of potential risks>
            ],
            "timeline_estimate": <estimated implementation time>
          }

          Important:
          - Always provide numeric scores where applicable
          - Include specific, actionable recommendations
          - Flag any uncertainties explicitly
          - Reference specific parts of the evidence in your analysis
          - If uncertain, use the appropriate alternative format
        PROMPT
      end

      def format_extraction_prompt(evidence_text)
        <<~PROMPT
          You are a PCI DSS compliance expert. Analyze the evidence and provide a structured response in JSON format.

          Evidence Text:
          #{evidence_text}

          Required Response Format:
          {
            "requirement_id": <PCI requirement number>,
            "requirement_text": <actual requirement text>,
            "evidence_match": <"high"/"medium"/"low">,
            "justification": <detailed explanation>,
            "related_requirements": [
              <array of related requirement IDs>
            ],
            "testing_procedures": [
              <array of relevant testing procedures>
            ]
          }

          If you are uncertain about the match, use this format:
          {
            "confidence_level": <number 0-100>,
            "draft_response": <your potential requirement match>,
            "uncertainty_reasons": [
              <array of reasons for uncertainty>
            ],
            "verification_needed": [
              <array of items that need verification>
            ],
            "alternative_approaches": [
              <array of other possible requirement matches>
            ],
            "expert_consultation": <boolean>,
            "data_gaps": [
              <array of missing information>
            ]
          }

          Important:
          - Be specific about requirement numbers (e.g., "1.2.3" not "Requirement 1")
          - Include exact requirement text from the standard
          - Provide clear justification for the match
          - List any related requirements that might also apply
          - If uncertain, use the uncertainty format
          - Reference specific parts of the evidence in your analysis
        PROMPT
      end

      def format_improvement_prompt(evidence_text, requirement_context)
        <<~PROMPT
          You are a PCI DSS compliance expert. Analyze the evidence and provide improvement suggestions in JSON format.

          Requirement Context:
          #{requirement_context}

          Current Evidence:
          #{evidence_text}

          Required Response Format:
          {
            "recommendation_type": <"process"/"technical"/"policy"/"compliance">,
            "primary_guidance": <main recommendation>,
            "rationale": <explanation>,
            "next_steps": [
              <array of immediate actions>
            ],
            "alternative_options": [
              <array of alternative approaches>
            ],
            "prerequisites": [
              <array of requirements>
            ],
            "risks": [
              <array of potential risks>
            ],
            "timeline_estimate": <estimated implementation time>
          }

          If you are uncertain about improvements, use this format:
          {
            "confidence_level": <number 0-100>,
            "draft_response": <your potential improvements>,
            "uncertainty_reasons": [
              <array of reasons for uncertainty>
            ],
            "verification_needed": [
              <array of items that need verification>
            ],
            "expert_consultation": <boolean>,
            "data_gaps": [
              <array of missing information>
            ]
          }

          Important:
          - Be specific and actionable in your recommendations
          - Include clear rationale for each suggestion
          - Provide realistic timeline estimates
          - Consider implementation prerequisites
          - Flag any uncertainties explicitly
          - If uncertain, use the uncertainty format
        PROMPT
      end

      def parse_analysis_response(response)
        {
          analysis: response,
          timestamp: Time.now.utc,
          model_used: @model
        }
      end

      def parse_extraction_response(response)
        {
          extracted_requirements: response,
          timestamp: Time.now.utc,
          model_used: @model
        }
      end

      def parse_improvement_response(response)
        {
          suggestions: response,
          timestamp: Time.now.utc,
          model_used: @model
        }
      end
    end
  end
end

require_relative 'ai_service'

module PCIEvidence
  module Services
    class EvidenceAnalysisEngine
      def initialize(ai_service: nil, logger: nil)
        @ai_service = ai_service || AIService.new
        @logger = logger || Logger.new(STDOUT)
      end

      # Analyze ROC response evidence
      def analyze_roc_response(response_text, requirement)
        @logger.info("Analyzing ROC response for requirement #{requirement.id}")

        context = format_requirement_context(requirement)
        analysis = @ai_service.analyze_evidence(response_text, context)

        if analysis[:analysis]['choices']&.first&.dig('message', 'content')
          result = JSON.parse(analysis[:analysis]['choices'].first['message']['content'])
          
          # Add metadata
          result.merge!(
            'requirement_id' => requirement.id,
            'evidence_type' => 'roc_response',
            'analyzed_at' => Time.now.utc,
            'model_used' => analysis[:model_used]
          )

          result
        else
          raise "Invalid AI response format"
        end
      end

      # Analyze GitHub evidence (issues, PRs, commits)
      def analyze_github_evidence(evidence_data, requirement)
        @logger.info("Analyzing GitHub evidence for requirement #{requirement.id}")

        # Format evidence data into analyzable text
        evidence_text = format_github_evidence(evidence_data)
        context = format_requirement_context(requirement)
        
        analysis = @ai_service.analyze_evidence(evidence_text, context)

        if analysis[:analysis]['choices']&.first&.dig('message', 'content')
          result = JSON.parse(analysis[:analysis]['choices'].first['message']['content'])
          
          # Add metadata
          result.merge!(
            'requirement_id' => requirement.id,
            'evidence_type' => 'github',
            'evidence_sources' => evidence_data.map { |e| e[:url] },
            'analyzed_at' => Time.now.utc,
            'model_used' => analysis[:model_used]
          )

          result
        else
          raise "Invalid AI response format"
        end
      end

      # Analyze GCP configuration evidence
      def analyze_gcp_evidence(config_data, requirement)
        @logger.info("Analyzing GCP configuration for requirement #{requirement.id}")

        # Format config data into analyzable text
        evidence_text = format_gcp_evidence(config_data)
        context = format_requirement_context(requirement)
        
        analysis = @ai_service.analyze_evidence(evidence_text, context)

        if analysis[:analysis]['choices']&.first&.dig('message', 'content')
          result = JSON.parse(analysis[:analysis]['choices'].first['message']['content'])
          
          # Add metadata
          result.merge!(
            'requirement_id' => requirement.id,
            'evidence_type' => 'gcp_config',
            'resource_types' => config_data.map { |c| c[:resource_type] }.uniq,
            'analyzed_at' => Time.now.utc,
            'model_used' => analysis[:model_used]
          )

          result
        else
          raise "Invalid AI response format"
        end
      end

      # Combine multiple pieces of evidence
      def combine_evidence_analysis(analyses, requirement)
        @logger.info("Combining evidence analyses for requirement #{requirement.id}")

        # Format the analyses into a summary for the AI
        summary_text = format_evidence_summary(analyses)
        context = format_requirement_context(requirement)

        # Ask AI to synthesize the evidence
        messages = [
          {
            role: "system",
            content: "You are a PCI DSS compliance expert. Your task is to synthesize multiple pieces of evidence analysis into a comprehensive assessment."
          },
          {
            role: "user",
            content: format_synthesis_prompt(summary_text, context)
          }
        ]

        synthesis = @ai_service.make_ai_request(:chat, messages)

        if synthesis['choices']&.first&.dig('message', 'content')
          result = JSON.parse(synthesis['choices'].first['message']['content'])
          
          # Add metadata
          result.merge!(
            'requirement_id' => requirement.id,
            'evidence_count' => analyses.length,
            'evidence_types' => analyses.map { |a| a['evidence_type'] }.uniq,
            'synthesized_at' => Time.now.utc,
            'model_used' => synthesis[:model_used]
          )

          result
        else
          raise "Invalid AI response format"
        end
      end

      private

      def format_requirement_context(requirement)
        <<~CONTEXT
          Requirement ID: #{requirement.id}
          Title: #{requirement.title}
          
          Defined Approach Text:
          #{requirement.defined_approach_text}
          
          Customized Approach Objective:
          #{requirement.customized_approach_objective}
          
          Testing Procedures:
          #{format_testing_procedures(requirement.testing_procedures)}
          
          Guidance:
          #{format_guidance(requirement.guidance)}
        CONTEXT
      end

      def format_testing_procedures(procedures)
        procedures.map do |proc|
          <<~PROC
            #{proc.id}:
            #{proc.text}
            #{format_sub_procedures(proc.sub_procedures)}
          PROC
        end.join("\n")
      end

      def format_sub_procedures(sub_procedures)
        return "" if sub_procedures.nil? || sub_procedures.empty?
        
        sub_procedures.map do |sub|
          "  - #{sub}"
        end.join("\n")
      end

      def format_guidance(guidance)
        return "" if guidance.nil?

        <<~GUIDANCE
          Purpose:
          #{guidance.purpose}

          Good Practices:
          #{format_bullet_points(guidance.good_practices)}

          Examples:
          #{format_bullet_points(guidance.examples)}

          Definitions:
          #{format_bullet_points(guidance.definitions)}

          Further Information:
          #{guidance.further_information}
        GUIDANCE
      end

      def format_bullet_points(items)
        return "" if items.nil? || items.empty?
        
        items.map { |item| "  - #{item}" }.join("\n")
      end

      def format_github_evidence(evidence_data)
        evidence_data.map do |evidence|
          <<~EVIDENCE
            Type: #{evidence[:type]}
            URL: #{evidence[:url]}
            Title: #{evidence[:title]}
            Description: #{evidence[:description]}
            Created At: #{evidence[:created_at]}
            Updated At: #{evidence[:updated_at]}
            Labels: #{evidence[:labels]&.join(', ')}
            Status: #{evidence[:status]}
            
            Content:
            #{evidence[:content]}
            
            Comments:
            #{format_comments(evidence[:comments])}
            
            Changes:
            #{format_changes(evidence[:changes])}
          EVIDENCE
        end.join("\n\n---\n\n")
      end

      def format_comments(comments)
        return "" if comments.nil? || comments.empty?
        
        comments.map do |comment|
          <<~COMMENT
            Author: #{comment[:author]}
            Date: #{comment[:date]}
            #{comment[:content]}
          COMMENT
        end.join("\n\n")
      end

      def format_changes(changes)
        return "" if changes.nil? || changes.empty?
        
        changes.map do |change|
          <<~CHANGE
            File: #{change[:file]}
            Type: #{change[:type]}
            Before:
            #{change[:before]}
            
            After:
            #{change[:after]}
          CHANGE
        end.join("\n\n")
      end

      def format_gcp_evidence(config_data)
        config_data.map do |config|
          <<~CONFIG
            Resource Type: #{config[:resource_type]}
            Resource Name: #{config[:name]}
            Project: #{config[:project]}
            Location: #{config[:location]}
            
            Configuration:
            #{format_config_details(config[:configuration])}
            
            IAM Policies:
            #{format_iam_policies(config[:iam_policies])}
            
            Audit Logs:
            #{format_audit_logs(config[:audit_logs])}
            
            Monitoring:
            #{format_monitoring(config[:monitoring])}
          CONFIG
        end.join("\n\n---\n\n")
      end

      def format_config_details(config)
        return "" if config.nil?
        
        case config
        when Hash
          config.map { |k, v| "#{k}: #{v}" }.join("\n")
        when String
          config
        else
          config.to_s
        end
      end

      def format_iam_policies(policies)
        return "" if policies.nil? || policies.empty?
        
        policies.map do |policy|
          <<~POLICY
            Role: #{policy[:role]}
            Members: #{policy[:members].join(', ')}
            Conditions: #{policy[:conditions]}
          POLICY
        end.join("\n")
      end

      def format_audit_logs(logs)
        return "" if logs.nil? || logs.empty?
        
        logs.map do |log|
          <<~LOG
            Type: #{log[:type]}
            Enabled: #{log[:enabled]}
            Retention: #{log[:retention]}
            Filters: #{log[:filters]}
          LOG
        end.join("\n")
      end

      def format_monitoring(monitoring)
        return "" if monitoring.nil? || monitoring.empty?
        
        monitoring.map do |monitor|
          <<~MONITOR
            Type: #{monitor[:type]}
            Metric: #{monitor[:metric]}
            Threshold: #{monitor[:threshold]}
            Alert Configuration: #{monitor[:alert_config]}
          MONITOR
        end.join("\n")
      end

      def format_evidence_summary(analyses)
        analyses.map do |analysis|
          <<~SUMMARY
            Evidence Type: #{analysis['evidence_type']}
            Completeness: #{analysis['completeness']}
            Relevance: #{analysis['relevance']}
            
            Gaps:
            #{format_bullet_points(analysis['gaps'])}
            
            Recommendations:
            #{format_bullet_points(analysis['recommendations'])}
            
            Confidence Score: #{analysis['confidence_score']}
            
            References:
            #{format_bullet_points(analysis['references'])}
            
            Uncertainty Flags:
            #{format_bullet_points(analysis['uncertainty_flags'])}
          SUMMARY
        end.join("\n\n---\n\n")
      end

      def format_synthesis_prompt(summary_text, requirement_context)
        <<~PROMPT
          Analyze and synthesize the following evidence analyses for a PCI DSS requirement.

          Requirement Context:
          #{requirement_context}

          Evidence Analyses:
          #{summary_text}

          Provide a comprehensive synthesis in this JSON format:
          {
            "overall_completeness": <number 0-100>,
            "overall_confidence": <number 0-100>,
            "evidence_quality": {
              "roc_response": <"strong"/"moderate"/"weak"/"missing">,
              "github": <"strong"/"moderate"/"weak"/"missing">,
              "gcp_config": <"strong"/"moderate"/"weak"/"missing">
            },
            "combined_gaps": [
              <array of unique gaps across all evidence>
            ],
            "combined_recommendations": [
              <array of unique, prioritized recommendations>
            ],
            "evidence_conflicts": [
              <array of any conflicts between evidence sources>
            ],
            "additional_evidence_needed": [
              <array of missing evidence types or details>
            ],
            "compliance_status": <"compliant"/"partially_compliant"/"non_compliant"/"insufficient_evidence">,
            "next_steps": [
              <array of prioritized actions>
            ]
          }

          Important:
          - Identify any conflicts between evidence sources
          - Highlight gaps that appear across multiple sources
          - Prioritize recommendations based on impact
          - Consider the strength of each evidence type
          - Be explicit about missing or weak evidence
          - Provide specific next steps for improvement
        PROMPT
      end
    end
  end
end

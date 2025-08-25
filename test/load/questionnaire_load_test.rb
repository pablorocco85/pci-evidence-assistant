require 'test_helper'
require 'parsers/questionnaire_parser'
require 'services/ai_service'
require 'benchmark'
require 'logger'
require 'json'

module PCIEvidence
  class QuestionnaireLoadTest < Minitest::Test
    def setup
      @logger = Logger.new(STDOUT)
      @logger.formatter = proc do |severity, datetime, progname, msg|
        "#{severity} [#{datetime}] #{msg}\n"
      end
      
      # Load the questionnaire
      @questionnaire_path = File.join(
        Dir.pwd, 'data', 'input', 'questionnaires',
        'Shopify Program_PCI DSS 4.0.1 Evidence Request Listing.xlsx'
      )
      
      @parser = Parsers::QuestionnaireParser.new(@questionnaire_path, logger: @logger)
      @ai_service = Services::AIService.new(logger: @logger)
      
      @results = {
        total_requests: 0,
        successful_requests: 0,
        failed_requests: 0,
        total_time: 0,
        average_response_time: 0,
        errors: [],
        performance_metrics: {
          memory_usage: {},
          response_times: []
        }
      }
    end

    def test_load_200_requests
      # Parse questionnaire
      parsed_data = @parser.parse
      assert parsed_data[:evidence_requests].any?, "No questions parsed from questionnaire"
      
      @results[:total_requests] = parsed_data[:evidence_requests].size
      @logger.info("Starting load test with #{@results[:total_requests]} questions")

      # Track memory usage before
      @results[:performance_metrics][:memory_usage][:before] = get_memory_usage

      total_time = Benchmark.realtime do
        parsed_data[:evidence_requests].each_with_index do |question, index|
          process_single_request(question, index + 1)
          
          # Progress update every 10 questions
          if (index + 1) % 10 == 0
            log_progress(index + 1, questions.size)
          end
        end
      end

      # Track memory usage after
      @results[:performance_metrics][:memory_usage][:after] = get_memory_usage
      
      # Calculate final metrics
      @results[:total_time] = total_time
      @results[:average_response_time] = @results[:performance_metrics][:response_times].sum / @results[:total_requests].to_f

      # Output results
      output_results
      
      # Assertions
      assert_operator @results[:successful_requests], :>, 0, "No successful requests"
      assert_operator @results[:failed_requests], :<, @results[:total_requests] * 0.2, "Too many failed requests"
      assert_operator @results[:average_response_time], :<, 5.0, "Average response time too high"
    end

    private

    def process_single_request(question, index)
      start_time = Time.now
      
      begin
        response = @ai_service.analyze_evidence(
          "Analyze evidence for requirement #{question[:requirement_id]}",
          evidence: { question: question }
        )
        
        @results[:successful_requests] += 1
      rescue => e
        @results[:failed_requests] += 1
        @results[:errors] << {
          question_index: index,
          error: e.message
        }
        @logger.error("Error processing question #{index}: #{e.message}")
      end

      response_time = Time.now - start_time
      @results[:performance_metrics][:response_times] << response_time
    end

    def log_progress(current, total)
      percentage = (current.to_f / total * 100).round(2)
      success_rate = (@results[:successful_requests].to_f / current * 100).round(2)
      
      @logger.info("Progress: #{current}/#{total} (#{percentage}%) - Success rate: #{success_rate}%")
    end

    def get_memory_usage
      {
        rss: `ps -o rss= -p #{Process.pid}`.to_i, # Resident Set Size in KB
        vmsize: `ps -o vsz= -p #{Process.pid}`.to_i # Virtual Memory Size in KB
      }
    end

    def output_results
      @logger.info("\n=== Load Test Results ===")
      @logger.info("Total Requests: #{@results[:total_requests]}")
      @logger.info("Successful: #{@results[:successful_requests]}")
      @logger.info("Failed: #{@results[:failed_requests]}")
      @logger.info("Total Time: #{@results[:total_time].round(2)} seconds")
      @logger.info("Average Response Time: #{@results[:average_response_time].round(2)} seconds")
      
      @logger.info("\nMemory Usage:")
      @logger.info("Before: RSS: #{@results[:performance_metrics][:memory_usage][:before][:rss]}KB, " \
                   "VMSize: #{@results[:performance_metrics][:memory_usage][:before][:vmsize]}KB")
      @logger.info("After: RSS: #{@results[:performance_metrics][:memory_usage][:after][:rss]}KB, " \
                   "VMSize: #{@results[:performance_metrics][:memory_usage][:after][:vmsize]}KB")

      if @results[:errors].any?
        @logger.info("\nErrors:")
        @results[:errors].each do |error|
          @logger.info("Question #{error[:question_index]}: #{error[:error]}")
        end
      end

      # Save results to file
      results_path = File.join(Dir.pwd, 'test', 'load', 'results', 'load_test_results.json')
      FileUtils.mkdir_p(File.dirname(results_path))
      File.write(results_path, JSON.pretty_generate(@results))
      @logger.info("\nDetailed results saved to: #{results_path}")
    end
  end
end

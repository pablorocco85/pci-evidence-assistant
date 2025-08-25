require 'test_helper'
require 'services/github_evidence_fetcher'

module PCIEvidence
  module Services
    class GitHubEvidenceFetcherTest < Minitest::Test
      def setup
        @logger = mock
        @fetcher = GitHubEvidenceFetcher.new(logger: @logger)
        @requirement_id = '1.2.3'
      end

      def test_fetch_github_evidence
        # Set up logger expectations in sequence
        logger_sequence = sequence('logger_sequence')
        @logger.expects(:info).with("Fetching GitHub evidence for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:info).with("Fetching issues for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:info).with("Fetching pull requests for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:info).with("Fetching commits for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:info).with("Fetching Terraform evidence for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:info).with("Looking for local clone of shopify-restricted").in_sequence(logger_sequence)
        @logger.expects(:info).with("Found shopify-restricted, updating content...").in_sequence(logger_sequence)

        # Mock issue search
        issue_json = JSON.generate([{
          number: 123,
          title: 'Test Issue',
          body: 'Test body',
          labels: ['security'],
          state: 'open',
          createdAt: '2024-01-01T00:00:00Z',
          closedAt: nil,
          url: 'https://github.com/Shopify/test/issues/123'
        }])

        # Mock PR search
        pr_json = JSON.generate([{
          number: 456,
          title: 'Test PR',
          body: 'Test body',
          labels: ['security'],
          state: 'merged',
          createdAt: '2024-01-01T00:00:00Z',
          mergedAt: '2024-01-02T00:00:00Z',
          url: 'https://github.com/Shopify/test/pull/456',
          files: ['test.rb']
        }])

        # Mock commit search
        commit_json = JSON.generate([{
          sha: 'abc123',
          commit: {
            message: 'Test commit',
            author: {
              name: 'Test Author',
              email: 'test@example.com',
              date: '2024-01-01T00:00:00Z'
            }
          },
          url: 'https://github.com/Shopify/test/commit/abc123',
          files: ['test.rb']
        }])

        # Mock command executions
        Open3.expects(:capture3).with(
          'gh', 'issue', 'list',
          '--search', @requirement_id.gsub('.', '\.'),
          '--json', 'number,title,body,labels,state,createdAt,closedAt,url',
          '--repo', 'shopify-cardserver',
          '--repo', 'shopify-restricted'
        ).returns([issue_json, '', mock('status', success?: true)])

        Open3.expects(:capture3).with(
          'gh', 'pr', 'list',
          '--search', @requirement_id.gsub('.', '\.'),
          '--json', 'number,title,body,labels,state,createdAt,mergedAt,url,files',
          '--repo', 'shopify-cardserver',
          '--repo', 'shopify-restricted'
        ).returns([pr_json, '', mock('status', success?: true)])

        Open3.expects(:capture3).with(
          'gh', 'api',
          '/search/commits',
          '--method', 'GET',
          '--field', "q=#{@requirement_id.gsub('.', '\.')}",
          '--jq', '.items[] | {sha, commit, url, files}'
        ).returns([commit_json, '', mock('status', success?: true)])

        # Mock dev cd and repo update
        dev_cd_status = mock('dev_cd_status')
        dev_cd_status.expects(:success?).returns(true)
        Open3.expects(:capture3).with('dev', 'cd', 'shopify-restricted')
             .returns(['', '', dev_cd_status])
        
        # Mock git status check
        git_status = mock('git_status')
        git_status.stubs(:success?).returns(true)
        git_status.stubs(:empty?).returns(true)
        Open3.expects(:capture3).with('git', 'status', '--porcelain')
             .returns(['', '', git_status])
        
        # Mock dev up
        dev_up_status = mock('dev_up_status')
        dev_up_status.expects(:success?).returns(true)
        Open3.expects(:capture3).with('dev', 'up')
             .returns(['', '', dev_up_status])

        # Mock current directory
        Dir.expects(:pwd).returns('/test/shopify-restricted')
        
        # Mock terraform file search
        Open3.expects(:capture3).with(
          'grep', '-r', '-l', '-i',
          '--include=*.tf',
          @requirement_id.to_s,
          '/test/shopify-restricted'
        ).returns(['test.tf', '', mock('status', success?: true)])

        # Mock Terraform file reading
        File.expects(:read).with('test.tf').returns('test terraform content')
        File.expects(:mtime).with('test.tf').returns(Time.now)
        File.expects(:size).with('test.tf').returns(100)
        File.expects(:dirname).with('test.tf').returns('/test/dir')

        result = @fetcher.fetch_github_evidence(@requirement_id)

        assert_equal @requirement_id, result[:requirement_id]
        assert_kind_of Hash, result[:evidence]
        assert_kind_of Array, result[:evidence][:issues]
        assert_kind_of Array, result[:evidence][:pull_requests]
        assert_kind_of Array, result[:evidence][:commits]
        assert_kind_of Array, result[:evidence][:terraform]
        assert_kind_of String, result[:metadata][:fetched_at]
        assert Time.parse(result[:metadata][:fetched_at])
        assert_equal ['shopify-cardserver', 'shopify-restricted'], result[:metadata][:source_repos]
      end

      def test_fetch_github_evidence_with_filters
        options = {
          labels: ['security', 'pci'],
          state: 'open',
          since: '2024-01-01',
          review_state: 'approved',
          author: 'test-author'
        }

        # Set up logger expectations in sequence
        logger_sequence = sequence('logger_sequence')
        @logger.expects(:info).with("Fetching GitHub evidence for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:info).with("Fetching issues for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:info).with("Fetching pull requests for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:info).with("Fetching commits for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:info).with("Fetching Terraform evidence for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:info).with("Looking for local clone of shopify-restricted").in_sequence(logger_sequence)
        @logger.expects(:info).with("Found shopify-restricted, updating content...").in_sequence(logger_sequence)

        # Mock command executions with filters
        Open3.expects(:capture3).with(
          'gh', 'issue', 'list',
          '--search', "#{@requirement_id.gsub('.', '\.')} label:security label:pci state:open created:>=2024-01-01",
          '--json', 'number,title,body,labels,state,createdAt,closedAt,url',
          '--repo', 'shopify-cardserver',
          '--repo', 'shopify-restricted'
        ).returns(['[]', '', mock('status', success?: true)])

        Open3.expects(:capture3).with(
          'gh', 'pr', 'list',
          '--search', "#{@requirement_id.gsub('.', '\.')} label:security label:pci state:open created:>=2024-01-01 review:approved",
          '--json', 'number,title,body,labels,state,createdAt,mergedAt,url,files',
          '--repo', 'shopify-cardserver',
          '--repo', 'shopify-restricted'
        ).returns(['[]', '', mock('status', success?: true)])

        Open3.expects(:capture3).with(
          'gh', 'api',
          '/search/commits',
          '--method', 'GET',
          '--field', "q=#{@requirement_id.gsub('.', '\.')} author:test-author committer-date:>=2024-01-01",
          '--jq', '.items[] | {sha, commit, url, files}'
        ).returns(['[]', '', mock('status', success?: true)])

        # Mock dev cd and repo update
        dev_cd_status = mock('dev_cd_status')
        dev_cd_status.expects(:success?).returns(true)
        Open3.expects(:capture3).with('dev', 'cd', 'shopify-restricted')
             .returns(['', '', dev_cd_status])
        
        # Mock git status check
        git_status = mock('git_status')
        git_status.stubs(:success?).returns(true)
        git_status.stubs(:empty?).returns(true)
        Open3.expects(:capture3).with('git', 'status', '--porcelain')
             .returns(['', '', git_status])
        
        # Mock dev up
        dev_up_status = mock('dev_up_status')
        dev_up_status.expects(:success?).returns(true)
        Open3.expects(:capture3).with('dev', 'up')
             .returns(['', '', dev_up_status])

        # Mock current directory
        Dir.expects(:pwd).returns('/test/shopify-restricted')
        
        # Mock terraform file search
        Open3.expects(:capture3).with(
          'grep', '-r', '-l', '-i',
          '--include=*.tf',
          @requirement_id.to_s,
          '/test/shopify-restricted'
        ).returns(['', '', mock('status', success?: true)])

        result = @fetcher.fetch_github_evidence(@requirement_id, filters: options)

        assert_equal @requirement_id, result[:requirement_id]
        assert_empty result[:evidence][:issues]
        assert_empty result[:evidence][:pull_requests]
        assert_empty result[:evidence][:commits]
        assert_empty result[:evidence][:terraform]
        assert_equal options, result[:metadata][:filters_applied]
      end

      def test_fetch_github_evidence_handles_errors
        # Set up logger expectations in sequence
        logger_sequence = sequence('logger_sequence')
        @logger.expects(:info).with("Fetching GitHub evidence for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:info).with("Fetching issues for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:error).with("Error fetching issues: Failed to fetch issues: error").in_sequence(logger_sequence)
        @logger.expects(:info).with("Fetching pull requests for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:error).with("Error fetching pull requests: Failed to fetch PRs: error").in_sequence(logger_sequence)
        @logger.expects(:info).with("Fetching commits for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:error).with("Error fetching commits: Failed to fetch commits: error").in_sequence(logger_sequence)
        @logger.expects(:info).with("Fetching Terraform evidence for requirement #{@requirement_id}").in_sequence(logger_sequence)
        @logger.expects(:info).with("Looking for local clone of shopify-restricted").in_sequence(logger_sequence)
        @logger.expects(:warn).with("Could not find shopify-restricted using dev cd: error").in_sequence(logger_sequence)
        @logger.expects(:warn).with("Could not find shopify-restricted in common paths").in_sequence(logger_sequence)

        # Mock failed command executions
        issue_status = mock('issue_status')
        issue_status.expects(:success?).returns(false)
        Open3.expects(:capture3).with(
          'gh', 'issue', 'list',
          '--search', @requirement_id.gsub('.', '\\.'),
          '--json', 'number,title,body,labels,state,createdAt,closedAt,url',
          '--repo', 'shopify-cardserver',
          '--repo', 'shopify-restricted'
        ).returns(['', 'error', issue_status])

        pr_status = mock('pr_status')
        pr_status.expects(:success?).returns(false)
        Open3.expects(:capture3).with(
          'gh', 'pr', 'list',
          '--search', @requirement_id.gsub('.', '\\.'),
          '--json', 'number,title,body,labels,state,createdAt,mergedAt,url,files',
          '--repo', 'shopify-cardserver',
          '--repo', 'shopify-restricted'
        ).returns(['', 'error', pr_status])

        commit_status = mock('commit_status')
        commit_status.expects(:success?).returns(false)
        Open3.expects(:capture3).with(
          'gh', 'api',
          '/search/commits',
          '--method', 'GET',
          '--field', "q=#{@requirement_id.gsub('.', '\\.')}",
          '--jq', '.items[] | {sha, commit, url, files}'
        ).returns(['', 'error', commit_status])

        # Mock failed dev cd
        dev_cd_status = mock('dev_cd_status')
        dev_cd_status.expects(:success?).returns(false)
        Open3.expects(:capture3).with('dev', 'cd', 'shopify-restricted')
             .returns(['', 'error', dev_cd_status])
        
        # Mock fallback path check
        Dir.expects(:exist?).times(3).returns(false)  # Check all fallback paths

        result = @fetcher.fetch_github_evidence(@requirement_id)

        assert_equal @requirement_id, result[:requirement_id]
        assert_empty result[:evidence][:issues]
        assert_empty result[:evidence][:pull_requests]
        assert_empty result[:evidence][:commits]
        assert_empty result[:evidence][:terraform]
      end
    end
  end
end

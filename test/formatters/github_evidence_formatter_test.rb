require 'test_helper'
require 'formatters/github_evidence_formatter'
require 'services/github_evidence_fetcher'

module PCIEvidence
  module Formatters
    class GitHubEvidenceFormatterTest < Minitest::Test
      def setup
        @logger = mock
        @formatter = GitHubEvidenceFormatter.new(logger: @logger)
        @requirement_id = '1.2.3'
        @timestamp = '2024-01-01T00:00:00Z'
      end

      def test_format_empty_evidence
        assert_equal "", @formatter.format(nil)
        assert_equal "", @formatter.format({})
      end

      def test_format_cde_only
        evidence = {
          requirement_id: @requirement_id,
          evidence: {
            cde: {
              pull_requests: [mock_pr]
            },
            application: {
              pull_requests: []
            },
            infrastructure: {
              pull_requests: []
            }
          },
          metadata: mock_metadata
        }

        result = @formatter.format(evidence)

        # Check main sections
        assert_match %r{^# GitHub Evidence}, result
        assert_match %r{^## Metadata}, result
        assert_match %r{^## CDE Evidence}, result
        refute_match %r{^## Application Evidence}, result
        refute_match %r{^## Infrastructure Evidence}, result

        # Check PR details
        assert_match %r{### \[#456\] Test PR}, result
        assert_match %r{\*\*Status:\*\* Merged on #{@timestamp}}, result
        assert_match %r{\*\*Labels:\*\* enhancement}, result
        assert_match %r{\*\*URL:\*\* https://github.com/test/456}, result
        assert_match %r{\*\*Files Changed:\*\*   - src/test.rb}, result
        assert_match %r{\*\*Related Commits:\*\*   - abcdef0: Test commit}, result
        assert_match %r{\*\*Description:\*\*   Test PR description}, result

        # Check section order
        sections = result.scan(/^#.*$/).reject { |s| s.start_with?('### ') }
        assert_equal ["# GitHub Evidence", "## Metadata", "## CDE Evidence"], sections.map(&:strip)

        # Check subsection order
        subsections = result.scan(/^###.*$/)
        assert_equal ["### [#456] Test PR"], subsections.map(&:strip)

        # Check subsubsection order
        subsubsections = result.scan(/^####.*$/)
        assert_equal [], subsubsections.map(&:strip)

        # Check content order
        content = result.split("\n")
        assert_includes content, "**Status:** Merged on #{@timestamp}"
        assert_includes content, "**Labels:** enhancement"
        assert_includes content, "**URL:** https://github.com/test/456"
        assert_includes content, "**Files Changed:**   - src/test.rb"
        assert_includes content, "**Related Commits:**   - abcdef0: Test commit"
        assert_includes content, "**Description:**   Test PR description"

        # Check that there are no extra sections
        refute_match %r{## Commits}, result
        refute_match %r{## Pull Requests}, result
        refute_match %r{## Issues}, result
        refute_match %r{## Terraform Evidence}, result

        # Check that there are no duplicate sections
        assert_equal 1, result.scan(/## CDE Evidence/).count

        # Check that there are no empty sections
        refute_match %r{## CDE Evidence\n\n## }, result

        # Check that there are no extra newlines
        refute_match %r{\n\n\n}, result

        # Check that there are no missing newlines
        assert_match %r{# GitHub Evidence\n\n}, result
        assert_match %r{## CDE Evidence\n\n}, result
        assert_match %r{### \[#456\] Test PR\n\n}, result
      end

      def test_format_application_only
        evidence = {
          requirement_id: @requirement_id,
          evidence: {
            cde: {
              pull_requests: []
            },
            application: {
              pull_requests: [mock_pr]
            },
            infrastructure: {
              pull_requests: []
            }
          },
          metadata: mock_metadata(scope: :application)
        }

        result = @formatter.format(evidence)

        # Check main sections
        assert_match %r{^# GitHub Evidence}, result
        assert_match %r{^## Metadata}, result
        assert_match %r{^## CDE Evidence}, result
        assert_match %r{^## Application Evidence}, result
        refute_match %r{^## Infrastructure Evidence}, result

        # Check PR details
        assert_match %r{### \[#456\] Test PR}, result
        assert_match %r{\*\*Status:\*\* Merged on #{@timestamp}}, result
        assert_match %r{\*\*Labels:\*\* enhancement}, result
        assert_match %r{\*\*URL:\*\* https://github.com/test/456}, result
        assert_match %r{\*\*Files Changed:\*\*   - src/test.rb}, result
        assert_match %r{\*\*Related Commits:\*\*   - abcdef0: Test commit}, result
        assert_match %r{\*\*Description:\*\*   Test PR description}, result

        # Check section order
        sections = result.scan(/^#.*$/).reject { |s| s.start_with?('### ') }
        assert_equal ["# GitHub Evidence", "## Metadata", "## CDE Evidence", "## Application Evidence"], sections.map(&:strip)

        # Check subsection order
        subsections = result.scan(/^###.*$/)
        assert_equal ["### [#456] Test PR"], subsections.map(&:strip)

        # Check subsubsection order
        subsubsections = result.scan(/^####.*$/)
        assert_equal [], subsubsections.map(&:strip)

        # Check content order
        content = result.split("\n")
        assert_includes content, "**Status:** Merged on #{@timestamp}"
        assert_includes content, "**Labels:** enhancement"
        assert_includes content, "**URL:** https://github.com/test/456"
        assert_includes content, "**Files Changed:**   - src/test.rb"
        assert_includes content, "**Related Commits:**   - abcdef0: Test commit"
        assert_includes content, "**Description:**   Test PR description"

        # Check that there are no extra sections
        refute_match %r{## Commits}, result
        refute_match %r{## Pull Requests}, result
        refute_match %r{## Issues}, result
        refute_match %r{## Terraform Evidence}, result

        # Check that there are no duplicate sections
        assert_equal 1, result.scan(/## Application Evidence/).count

        # Check that there are no empty sections
        refute_match %r{## CDE Evidence\n\n\n## }, result
        refute_match %r{## Application Evidence\n\n\n## }, result

        # Check that there are no extra newlines
        refute_match %r{\n\n\n}, result

        # Check that there are no missing newlines
        assert_match %r{# GitHub Evidence\n\n}, result
        assert_match %r{## CDE Evidence\n\n}, result
        assert_match %r{## Application Evidence\n\n}, result
        assert_match %r{### \[#456\] Test PR\n\n}, result
      end

      def test_format_infrastructure_only
        evidence = {
          requirement_id: @requirement_id,
          evidence: {
            cde: {
              pull_requests: []
            },
            application: {
              pull_requests: []
            },
            infrastructure: {
              pull_requests: [mock_pr_with_terraform]
            }
          },
          metadata: mock_metadata(scope: :infrastructure)
        }

        result = @formatter.format(evidence)

        # Check main sections
        assert_match %r{^# GitHub Evidence}, result
        assert_match %r{^## Metadata}, result
        assert_match %r{^## CDE Evidence}, result
        refute_match %r{^## Application Evidence}, result
        assert_match %r{^## Infrastructure Evidence}, result

        # Check PR details
        assert_match %r{### \[#456\] Test PR}, result
        assert_match %r{\*\*Status:\*\* Merged on #{@timestamp}}, result
        assert_match %r{\*\*Labels:\*\* enhancement}, result
        assert_match %r{\*\*URL:\*\* https://github.com/test/456}, result
        assert_match %r{\*\*Files Changed:\*\*   - terraform/test.tf}, result
        assert_match %r{\*\*Related Commits:\*\*   - abcdef0: Test commit}, result
        assert_match %r{\*\*Description:\*\*   Test PR description}, result

        # Check Terraform changes
        assert_match %r{#### Terraform Changes}, result
        assert_match %r{#### terraform/test.tf}, result
        assert_match %r{\*\*Last Modified:\*\* #{@timestamp}}, result
        assert_match %r{\*\*Size:\*\* 100 bytes}, result
        assert_match %r{\*\*Directory:\*\* terraform}, result
        assert_match %r{```hcl\nresource "test" "example" \{\n\}\n```}, result

        # Check section order
        sections = result.scan(/^#.*$/).reject { |s| s.start_with?('### ') || s.start_with?('#### ') }
        assert_equal ["# GitHub Evidence", "## Metadata", "## CDE Evidence", "## Infrastructure Evidence"], sections.map(&:strip)

        # Check subsection order
        subsections = result.scan(/^###.*$/).reject { |s| s.start_with?('#### ') }
        assert_equal ["### [#456] Test PR"], subsections.map(&:strip)

        # Check subsubsection order
        subsubsections = result.scan(/^####.*$/)
        assert_equal ["#### Terraform Changes", "#### terraform/test.tf"], subsubsections.map(&:strip)

        # Check content order
        content = result.split("\n")
        assert_includes content, "**Status:** Merged on #{@timestamp}"
        assert_includes content, "**Labels:** enhancement"
        assert_includes content, "**URL:** https://github.com/test/456"
        assert_includes content, "**Files Changed:**   - terraform/test.tf"
        assert_includes content, "**Related Commits:**   - abcdef0: Test commit"
        assert_includes content, "**Description:**   Test PR description"
        assert_includes content, "**Last Modified:** #{@timestamp}"
        assert_includes content, "**Size:** 100 bytes"
        assert_includes content, "**Directory:** terraform"
        assert_includes content, "```hcl"
        assert_includes content, "resource \"test\" \"example\" {"
        assert_includes content, "}"
        assert_includes content, "```"

        # Check that there are no extra sections
        refute_match %r{## Commits}, result
        refute_match %r{## Pull Requests}, result
        refute_match %r{## Issues}, result
        refute_match %r{## Terraform Evidence}, result

        # Check that there are no duplicate sections
        assert_equal 1, result.scan(/## Infrastructure Evidence/).count

        # Check that there are no empty sections
        refute_match %r{## CDE Evidence\n\n\n## }, result
        refute_match %r{## Infrastructure Evidence\n\n\n## }, result

        # Check that there are no extra newlines
        refute_match %r{\n\n\n}, result

        # Check that there are no missing newlines
        assert_match %r{# GitHub Evidence\n\n}, result
        assert_match %r{## CDE Evidence\n\n}, result
        assert_match %r{## Infrastructure Evidence\n\n}, result
        assert_match %r{### \[#456\] Test PR\n\n}, result
        assert_match %r{#### Terraform Changes\n\n}, result
        assert_match %r{#### terraform/test.tf\n\n}, result
      end

      def test_format_with_filters
        evidence = {
          requirement_id: @requirement_id,
          evidence: {
            cde: {
              pull_requests: [mock_pr]
            },
            application: {
              pull_requests: []
            },
            infrastructure: {
              pull_requests: []
            }
          },
          metadata: mock_metadata(
            scope: :cde,
            filters: {
              labels: ['security'],
              state: 'merged',
              since: '2024-01-01'
            }
          )
        }

        result = @formatter.format(evidence)

        # Check filters in metadata
        assert_match %r{\*\*Filters:\*\*}, result
        assert_match %r{- labels: security}, result
        assert_match %r{- state: merged}, result
        assert_match %r{- since: 2024-01-01}, result
      end

      private

      def mock_metadata(scope: :cde, filters: nil)
        {
          fetched_at: @timestamp,
          source_repos: ['Shopify/shopify-cardserver', 'Shopify/shopify-restricted'],
          scope: {
            type: scope,
            name: Services::GitHubEvidenceFetcher::REPOSITORIES[scope][:name],
            description: Services::GitHubEvidenceFetcher::REPOSITORIES[scope][:description]
          },
          filters_applied: filters || {}
        }
      end

      def mock_pr
        {
          number: 456,
          title: "Test PR",
          body: "Test PR description",
          labels: ['enhancement'],
          state: 'merged',
          created_at: @timestamp,
          merged_at: @timestamp,
          url: 'https://github.com/test/456',
          files: ['src/test.rb'],
          commits: [
            {
              sha: 'abcdef0123456789',
              message: 'Test commit',
              author: {
                'name' => 'Test User',
                'email' => 'test@example.com'
              },
              url: 'https://github.com/test/abcdef0'
            }
          ]
        }
      end

      def mock_pr_with_terraform
        pr = mock_pr
        pr[:files] = ['terraform/test.tf']
        pr[:terraform_changes] = [
          {
            file_path: 'terraform/test.tf',
            content: "resource \"test\" \"example\" {\n}",
            metadata: {
              last_modified: @timestamp,
              size: 100,
              directory: 'terraform'
            }
          }
        ]
        pr
      end
    end
  end
end
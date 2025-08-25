require 'json'
require 'open3'

module PCIEvidence
  module Services
    class GitHubEvidenceFetcher
      class FetchError < StandardError; end

      # Define repository categories
      REPOSITORIES = {
        infrastructure: {
          name: "Infrastructure",
          description: "Infrastructure and platform configuration",
          org: "Shopify",
          repos: ["shopify-restricted", "shopify-vault"]
        },
        application: {
          name: "Application",
          description: "Payment application components",
          org: "ShopifyUS",
          repos: ["cardserver", "hostedfields", "cardsink"]
        },
        cde: {
          name: "CDE",
          description: "Core CDE components",
          org: "Shopify",
          repos: ["shopify-cardserver"]
        }
      }.freeze

      DEFAULT_SCOPE = :cde  # Default to CDE scope

      def initialize(logger: nil)
        @logger = logger || Logger.new(STDOUT)
      end

      # Fetch evidence from GitHub issues and PRs
      def fetch_github_evidence(requirement_id, options = {})
        @logger.info("Fetching GitHub evidence for requirement #{requirement_id}")

        # Determine scope and repositories
        scope = options[:scope] || DEFAULT_SCOPE
        scope_config = REPOSITORIES[scope]
        repos = options[:repositories] || scope_config[:repos]

        # Initialize evidence structure by category
        evidence = {
          infrastructure: {
            pull_requests: []  # Each PR will include its commits and terraform changes
          },
          application: {
            pull_requests: []
          },
          cde: {
            pull_requests: []
          }
        }

        # Helper to categorize evidence by repo
        def categorize_repo(repo)
          REPOSITORIES.each do |category, config|
            return category if config[:repos].include?(repo)
          end
          :infrastructure  # Default to infrastructure if unknown
        end

        # Helper to add evidence to the correct category
        def add_evidence(evidence, repo, pr_data)
          category = categorize_repo(repo)
          evidence[category][:pull_requests] << pr_data
        end

        # Fetch evidence for each repository
        repos.each do |repo|
          # Determine organization
          org = REPOSITORIES.find { |_, config| config[:repos].include?(repo) }&.last[:org] || "Shopify"
          repo_with_org = "#{org}/#{repo}"

          # Fetch merged PRs
          begin
            prs = fetch_pull_requests(requirement_id, options.merge(
              repository: repo_with_org,
              state: 'merged'  # Only fetch merged PRs
            ))

            # For each merged PR, fetch its commits and files
            prs.each do |pr|
              # Fetch PR commits
              pr_commits = fetch_pr_commits(pr[:number], options.merge(repository: repo_with_org))
              pr[:commits] = pr_commits

              # For infrastructure repos, check if PR modifies Terraform files
              if categorize_repo(repo) == :infrastructure && pr[:files].any? { |f| f.end_with?('.tf') }
                pr[:terraform_changes] = fetch_terraform_changes(pr[:files], repo)
              end

              add_evidence(evidence, repo, pr)
            end
          rescue => e
            @logger.error("Failed to fetch PRs from #{repo_with_org}: #{e.message}")
          end
        end

        {
          requirement_id: requirement_id,
          evidence: evidence,
          metadata: {
            fetched_at: Time.now.utc.iso8601,
            scope: {
              type: scope,
              name: REPOSITORIES[scope][:name],
              description: REPOSITORIES[scope][:description]
            },
            source_repos: repos.map { |repo| 
              org = REPOSITORIES.find { |_, config| config[:repos].include?(repo) }&.last[:org] || "Shopify"
              "#{org}/#{repo}"
            },
            filters_applied: options[:filters] || {}
          }
        }
      end

      private

      def fetch_issues(requirement_id, options)
        @logger.info("Fetching issues for requirement #{requirement_id}")
        
        # Build search query
        query = build_issue_search_query(requirement_id, options)
        
        # Use gh CLI to search issues
        stdout, stderr, status = Open3.capture3('gh', 'issue', 'list',
          '--search', query,
          '--json', 'number,title,body,labels,state,createdAt,closedAt,url',
          '--repo', options[:repository]
        )

        raise FetchError, "Failed to fetch issues: #{stderr}" unless status.success?

        parse_issues(stdout)
      rescue => e
        @logger.error("Error fetching issues: #{e.message}")
        []
      end

      def fetch_pull_requests(requirement_id, options)
        @logger.info("Fetching pull requests for requirement #{requirement_id}")
        
        # Build search query
        query = build_pr_search_query(requirement_id, options)
        
        # Use gh CLI to search PRs
        stdout, stderr, status = Open3.capture3('gh', 'pr', 'list',
          '--search', query,
          '--json', 'number,title,body,labels,state,createdAt,mergedAt,url,files',
          '--repo', options[:repository]
        )

        raise FetchError, "Failed to fetch PRs: #{stderr}" unless status.success?

        parse_pull_requests(stdout)
      rescue => e
        @logger.error("Error fetching pull requests: #{e.message}")
        []
      end

      def fetch_pr_commits(pr_number, options)
        @logger.info("Fetching commits for PR ##{pr_number}")
        
        # Use gh CLI to fetch PR commits
        stdout, stderr, status = Open3.capture3('gh', 'pr', 'view',
          pr_number.to_s,
          '--repo', options[:repository],
          '--json', 'commits',
          '--jq', '.commits[] | {sha: .oid, message: .messageHeadline, author: {name: .authors[0].name, email: .authors[0].email}, url}'
        )

        raise FetchError, "Failed to fetch PR commits: #{stderr}" unless status.success?

        parse_pr_commits(stdout)
      rescue => e
        @logger.error("Error fetching PR commits: #{e.message}")
        []
      end

      def fetch_terraform_changes(files, repo)
        terraform_files = files.select { |f| f.end_with?('.tf') }
        return [] if terraform_files.empty?

        @logger.info("Fetching Terraform changes for #{terraform_files.size} files in #{repo}")
        
        # Find local repo
        repo_path = find_local_repo(repo)
        return [] unless repo_path

        # Read current state of Terraform files
        terraform_files.map do |file|
          file_path = File.join(repo_path, file)
          next unless File.exist?(file_path)

          {
            file_path: file,
            content: File.read(file_path),
            metadata: extract_terraform_metadata(file_path)
          }
        end.compact
      rescue => e
        @logger.error("Error fetching Terraform changes: #{e.message}")
        []
      end

      def fetch_terraform_evidence(requirement_id, options)
        @logger.info("Fetching Terraform evidence for requirement #{requirement_id}")
        
        evidence = []
        
        # Check if repo is cloned locally
        repo_path = find_local_repo(options[:repository].split('/').last)
        return [] unless repo_path

        # Search for relevant Terraform files
        terraform_files = find_terraform_files(repo_path, requirement_id)
        
        terraform_files.each do |file|
          evidence << {
            file_path: file,
            content: File.read(file),
            metadata: extract_terraform_metadata(file)
          }
        end

        evidence
      rescue => e
        @logger.error("Error fetching Terraform evidence: #{e.message}")
        []
      end

      def build_issue_search_query(requirement_id, options)
        filters = []
        
        # Add requirement ID
        filters << requirement_id.gsub('.', '\.')
        
        # Add label filters
        if options.dig(:filters, :labels)
          filters.concat(options[:filters][:labels].map { |l| "label:#{l}" })
        end
        
        # Add state filter
        if options.dig(:filters, :state)
          filters << "state:#{options[:filters][:state]}"
        end
        
        # Add date range
        if options.dig(:filters, :since)
          filters << "created:>=#{options[:filters][:since]}"
        end

        filters.join(' ')
      end

      def build_pr_search_query(requirement_id, options)
        filters = []
        
        # Add requirement ID
        filters << requirement_id.gsub('.', '\.')
        
        # Add label filters
        if options.dig(:filters, :labels)
          filters.concat(options[:filters][:labels].map { |l| "label:#{l}" })
        end
        
        # Add state filter
        if options.dig(:filters, :state)
          filters << "state:#{options[:filters][:state]}"
        end
        
        # Add date range
        if options.dig(:filters, :since)
          filters << "created:>=#{options[:filters][:since]}"
        end

        # Add review state
        if options.dig(:filters, :review_state)
          filters << "review:#{options[:filters][:review_state]}"
        end

        filters.join(' ')
      end

      def build_commit_search_query(requirement_id, options)
        filters = []
        
        # Add requirement ID
        filters << requirement_id.gsub('.', '\.')
        
        # Add author filter
        if options.dig(:filters, :author)
          filters << "author:#{options[:filters][:author]}"
        end
        
        # Add date range
        if options.dig(:filters, :since)
          filters << "committer-date:>=#{options[:filters][:since]}"
        end

        filters.join(' ')
      end

      def find_local_repo(repo_name)
        @logger.info("Looking for local clone of #{repo_name}")

        # Try to navigate to repo using dev
        _, stderr, status = Open3.capture3('dev', 'cd', repo_name)
        
        if status.success?
          @logger.info("Found #{repo_name}, updating content...")
          
          # Check if repo needs update
          _, _, git_status = Open3.capture3('git', 'status', '--porcelain')
          if git_status.empty?
            # No local changes, safe to update
            _, update_stderr, update_status = Open3.capture3('dev', 'up')
            unless update_status.success?
              @logger.warn("Failed to update #{repo_name}: #{update_stderr}")
            end
          else
            @logger.warn("Local changes detected in #{repo_name}, skipping update")
          end

          # Return current directory as repo path
          Dir.pwd
        else
          @logger.warn("Could not find #{repo_name} using dev cd: #{stderr}")
          
          # Fallback to checking common paths
          paths = [
            File.expand_path("~/src/github.com/Shopify/#{repo_name}"),
            File.expand_path("~/src/github.com/ShopifyUS/#{repo_name}"),
            File.expand_path("~/shopify/#{repo_name}"),
            File.expand_path("~/#{repo_name}")
          ]

          repo_path = paths.find { |path| Dir.exist?(path) }
          if repo_path
            @logger.info("Found #{repo_name} at #{repo_path}")
          else
            @logger.warn("Could not find #{repo_name} in common paths")
          end

          repo_path
        end
      rescue => e
        @logger.error("Error accessing #{repo_name}: #{e.message}")
        nil
      end

      def find_terraform_files(repo_path, requirement_id)
        # Use grep to find Terraform files that might be relevant
        stdout, _, status = Open3.capture3('grep',
          '-r',                    # Recursive search
          '-l',                    # Only show file names
          '-i',                    # Case insensitive
          '--include=*.tf',        # Only search Terraform files
          requirement_id.to_s,     # Search for requirement ID
          repo_path
        )

        status.success? ? stdout.split("\n") : []
      end

      def extract_terraform_metadata(file_path)
        # Try to extract useful metadata from Terraform files
        {
          last_modified: File.mtime(file_path),
          size: File.size(file_path),
          directory: File.dirname(file_path)
        }
      end

      def parse_issues(json_str)
        JSON.parse(json_str).map do |issue|
          {
            number: issue['number'],
            title: issue['title'],
            body: issue['body'],
            labels: issue['labels'],
            state: issue['state'],
            created_at: issue['createdAt'],
            closed_at: issue['closedAt'],
            url: issue['url']
          }
        end
      end

      def parse_pull_requests(json_str)
        JSON.parse(json_str).map do |pr|
          {
            number: pr['number'],
            title: pr['title'],
            body: pr['body'],
            labels: pr['labels'],
            state: pr['state'],
            created_at: pr['createdAt'],
            merged_at: pr['mergedAt'],
            url: pr['url'],
            files: pr['files']
          }
        end
      end

      def parse_pr_commits(json_str)
        JSON.parse(json_str).map do |commit|
          {
            sha: commit['sha'],
            message: commit['message'],
            author: commit['author'],
            url: commit['url']
          }
        end
      end
    end
  end
end
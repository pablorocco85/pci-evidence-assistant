# PCI Evidence Assistant

AI-powered system to streamline PCI DSS assessment responses by automatically gathering and analyzing evidence from multiple sources.

## Project Structure

```
pci-evidence-assistant/
├── bin/                    # Executable scripts
├── config/                 # Configuration files
├── lib/                    # Core library code
│   ├── parsers/           # Input parsing (requirements, documents)
│   ├── connectors/        # Source system integrations
│   ├── ai/                # AI processing and response generation
│   └── models/            # Data models and storage
└── test/                  # Test files
```

## Components

### Parsers
- Requirement Parser: Processes PCI DSS requirements
- Document Parser: Handles various document formats
- Response Parser: Processes and validates responses

### Connectors
- GitHub Connector: Repository and issue access
- GCP Connector: Cloud resource information
- Docusaurus Connector: Documentation access

### AI Processing
- AI Client: Gemini/GPT integration
- Prompt Manager: Handles AI interactions
- Response Generator: Creates structured responses

### Models
- Requirement: PCI DSS requirement representation
- Evidence: Gathered evidence structure
- Response: Generated response format
- Confidence: Scoring and validation

## Development

### Setup
```bash
# Install dependencies
bundle install

# Run tests
bundle exec rake test

# Run specific component
bundle exec bin/[script-name]
```

### Configuration
- Create `config/settings.yml` for source configurations
- Set up necessary API tokens in environment

## Usage

### Processing Questionnaires
1. Place your PCI DSS evidence request questionnaire in `/data/input/questionnaires/`
2. Run the evidence assistant:
   ```bash
   bundle exec bin/process_questionnaire
   ```
3. Results will be stored in `/data/output/`

The tool supports:
- Multiple questionnaires in the input directory
- Excel (.xlsx) format
- PCI DSS 4.0.1 evidence request format
- Automatic evidence gathering from:
  - GitHub repositories (PRs, commits, changes)
  - GCP configurations (firewall rules, IAM policies)
  - Documentation and other sources

### Load Testing
To run load tests (e.g., processing 200 requests):
```bash
bundle exec rake test:load
```
This will:
- Process all questions from input questionnaires
- Show real-time progress
- Generate performance metrics
- Output detailed results for analysis

## Testing

Each component includes:
- Unit tests
- Integration tests
- Sample data for testing

## Status

Currently in Phase 2: AI Integration & Analysis
- Core AI integration completed
- Evidence collection system implemented
- Working on load testing and batch processing

## Future Enhancements (Product Backlog) 🔮

These features are not part of the current MVP but captured here for future iterations:

### Input Processing
- 🤖 AI-powered questionnaire parser
  - Auto-detect and parse various questionnaire formats
  - Interactive format confirmation with users
  - Support for custom/non-standard formats
  - Learning from corrections and confirmations

### Evidence Collection
- 📚 Additional evidence sources
  - GitHub issues with evidence-specific labels
  - Wiki integration for documentation
  - Slack thread analysis for assessment channels
    - Extract preliminary responses from QSA meetings
    - Auto-suggest GitHub issue updates based on thread content
    - Link Slack discussions to corresponding evidence requests
- 🔄 Real-time evidence updates
  - Watch for infrastructure changes (40% auto-response potential)
  - Monitor configuration files in repositories
  - Automatic re-assessment triggers
  - Continuous compliance status updates

### User Experience
- 🎨 Web interface for:
  - Questionnaire upload and validation
  - Progress monitoring
  - Evidence review and adjustment
- 📊 Interactive dashboards
  - Compliance status visualization
  - Evidence coverage metrics
  - Confidence score trends

### AI Capabilities
- 🧠 Enhanced analysis features
  - Cross-requirement impact analysis
    - Identify linked requirements
    - Ensure response consistency
    - Highlight dependency chains
  - Historical compliance tracking
  - Predictive compliance scoring
    - Risk assessment per requirement
    - Early warning system for potential issues
    - Impact analysis of infrastructure changes
- 🔍 Advanced evidence correlation
  - Pattern recognition across sources
  - Temporal evidence linking
  - Conflict detection and resolution
  - Auto-linking of related evidence across requirements

Note: These are potential future enhancements. The current focus is on delivering core functionality for PCI DSS evidence collection and analysis.

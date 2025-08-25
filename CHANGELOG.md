# Changelog

All notable changes to the PCI Evidence Assistant will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]
### Added
- Load testing framework (in progress)
- Batch processing capabilities (planned)
- Performance metrics collection (planned)

## [2.1.0] - 2025-08-25
### Added
- PR-centric GitHub evidence formatting
- Scope-aware evidence collection (CDE/Application/Infrastructure)
- Comprehensive test coverage for formatters
- Newline and header level standardization
- Error handling improvements

### Changed
- Switched to PR-based evidence collection
- Updated GitHub fetcher to handle multiple organizations
- Refined markdown generation for consistency

## [2.0.0] - 2025-08-20
### Added
- Quick AI integration with local proxy
- GPT-4.1 and Gemini-2.5-pro support
- Response validation framework
- Error handling and recovery system
- Evidence formatters base implementation
- GCP evidence fetcher with gcloud and MCP
- GitHub evidence fetcher with multi-org support

### Changed
- Moved to AI-powered analysis
- Enhanced error handling architecture
- Improved evidence collection strategy

## [1.1.0] - 2025-08-15
### Added
- StandardParser for regular requirements
- QuestionnaireParser improvements
- PriorityToolParser enhancements

### Changed
- Skipped appendix requirements (parked)
- Simplified text handling approach

## [1.0.0] - 2025-08-10
### Added
- Core Ruby architecture
- Basic parsers implementation
- Initial test framework
- Project structure and documentation
- GCP integration exploration
- Source connector foundations

### Changed
- Established project baseline
- Defined core architecture patterns

## Notes

### Version Numbering
- 1.x.x: Foundation & Parser Implementation Phase
  - Focus on core architecture and basic parsing
  - Establishing project structure
  
- 2.x.x: AI Integration & Analysis Phase
  - AI service integration
  - Evidence collection and formatting
  - Enhanced validation and testing

### Future Versions (Planned)
- 3.x.x: Response System Phase
  - Response generation
  - Evidence linking
  - Review interface

- 4.x.x: Testing & Refinement Phase
  - Historical requirement testing
  - Accuracy metrics
  - Response refinement
  - Learning system

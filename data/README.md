# Data Directory Structure

## Input Data
Place input files in the appropriate directories:

### `/data/input/questionnaires/`
- Place QSA evidence request Excel files here
- Current questionnaire: `Shopify Program_PCI DSS 4.0.1 Evidence Request Listing.xlsx`
- For new questionnaires:
  - Add them to this directory
  - Supported formats: .xlsx
  - Must follow PCI DSS evidence request format
  - Tool will automatically detect and process new questionnaires
- Expected columns:
  - Evidence request
  - PCI DSS requirement reference
  - Additional context (if any)
  - Testing procedures

### `/data/input/standards/`
- Place PCI DSS standard files here:
  - `pci_dss_v4.pdf` - Full standard
  - `pci_dss_v4_prioritized.xlsx` - Prioritized approach tool
  - Other reference materials

### `/data/processed/`
- Parser output will be stored here
- Structured JSON format
- Maintains relationships between:
  - QSA requests
  - PCI DSS requirements
  - AI-enhanced understanding

### `/data/output/`
- Final generated responses
- Evidence mappings
- Confidence scores
- Review notes

## .gitignore Note
The `/data/input/` directory is gitignored to avoid committing sensitive assessment data.
Use `sample_data/` for test files and examples.

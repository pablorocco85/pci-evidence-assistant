#!/usr/bin/env python3
import sys
import json
import re
from PyPDF2 import PdfReader

def extract_text_with_positions(pdf_path):
    requirements = {}
    current_requirement = None
    current_section = None
    
    # Define section headers
    section_headers = [
        'Defined Approach Requirements',
        'Defined Approach Testing Procedures',
        'Purpose',
        'Customized Approach Objective',
        'Good Practice',
        'Examples',
        'Applicability Notes',
        'Further Information',
        'Guidance'
    ]

    # Process each page
    reader = PdfReader(pdf_path)
    for page_num, page in enumerate(reader.pages):
        text = page.extract_text()
        
        # Skip pages without requirements
        if 'Table of Contents' in text or 'Payment Card Industry Data Security Standard' in text:
            continue
            
        # Split text into lines
        lines = text.split('\n')
        
        # Process each line
        for line in lines:
            line = line.strip()
            if not line:
                continue
                
            # Check for section headers
            is_section_header = False
            for header in section_headers:
                if header in line:
                    current_section = header
                    is_section_header = True
                    break
            if is_section_header:
                continue
                
            # Check for requirement numbers
            req_match = re.match(r'(?:^|\s+)(\d+\.\d+(?:\.\d+)?(?:\.[a-z])?|A\d+\.\d+(?:\.\d+)?(?:\.[a-z])?)\s+', line)
            if req_match:
                req_number = req_match.group(1)
                
                # Skip if this looks like a version number or page number
                if re.match(r'^\d+\.\d+$', req_number) and float(req_number) < 10.0:
                    continue
                    
                # Initialize requirement if not exists
                if req_number not in requirements:
                    requirements[req_number] = {
                        'raw_requirement': req_number,
                        'requirement_number': req_number,
                        'sections': {}
                    }
                
                # Extract text after requirement number
                text_after = line[line.index(req_number) + len(req_number):].strip()
                
                # Add text to section
                section = current_section or 'Defined Approach Requirements'
                if section not in requirements[req_number]['sections']:
                    requirements[req_number]['sections'][section] = ''
                requirements[req_number]['sections'][section] += ' ' + text_after
                requirements[req_number]['sections'][section] = requirements[req_number]['sections'][section].strip()
                
                current_requirement = req_number
            elif current_requirement and current_section:
                # Add text to current section
                if current_section not in requirements[current_requirement]['sections']:
                    requirements[current_requirement]['sections'][current_section] = ''
                requirements[current_requirement]['sections'][current_section] += ' ' + line
                requirements[current_requirement]['sections'][current_section] = requirements[current_requirement]['sections'][current_section].strip()
    
    return requirements

if __name__ == '__main__':
    if len(sys.argv) != 2:
        print('Usage: python extract_pdf_text.py <pdf_file>')
        sys.exit(1)
        
    pdf_path = sys.argv[1]
    requirements = extract_text_with_positions(pdf_path)
    print(json.dumps({
        'metadata': {
            'filename': pdf_path,
            'total_requirements': len(requirements)
        },
        'requirements': requirements
    }, indent=2))
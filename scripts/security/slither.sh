#!/bin/bash
# Slither static analysis for SpiralToken contracts

set -e

echo "🔍 Running Slither static analysis..."
echo ""

# Check if slither is installed
if ! command -v slither &> /dev/null; then
    echo "❌ Slither is not installed. Install it with:"
    echo "   pip install slither-analyzer"
    exit 1
fi

# Run slither on the main contract
echo "Analyzing SpiralToken.sol..."
slither ethereum/SpiralToken.sol \
    --solc-version 0.8.30 \
    --exclude-informational \
    --exclude-optimization \
    --print human-summary \
    --json slither-report.json 2>&1 | tee slither-output.txt

echo ""
echo "✅ Slither analysis complete!"
echo "📄 Full report saved to: slither-report.json"
echo "📄 Human-readable output: slither-output.txt"


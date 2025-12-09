#!/bin/bash
# Mythril symbolic execution analysis for SpiralToken contracts

set -e

echo "🔍 Running Mythril symbolic execution..."
echo ""

# Check if mythril is installed
if ! command -v myth &> /dev/null; then
    echo "❌ Mythril is not installed. Install it with:"
    echo "   pip install mythril"
    exit 1
fi

# Run mythril on the main contract
echo "Analyzing SpiralToken.sol..."
myth analyze ethereum/SpiralToken.sol \
    --solv 0.8.30 \
    --execution-timeout 300 \
    --max-depth 12 \
    --solver-timeout 10000 \
    --format json \
    -o mythril-report.json 2>&1 | tee mythril-output.txt

echo ""
echo "✅ Mythril analysis complete!"
echo "📄 Full report saved to: mythril-report.json"
echo "📄 Human-readable output: mythril-output.txt"


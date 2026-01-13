#!/bin/bash
# Simple progress checker for calculator models

cd "$(dirname "$0")"

echo "=== Calculator Models Progress Check ==="
echo ""

if [ -f "calculator_run_improved.log" ]; then
    echo "Log file exists. Last 10 lines:"
    tail -10 calculator_run_improved.log
    echo ""
fi

if [ -f "outputs/calculator_models_summary.csv" ]; then
    echo "=== Results Summary ==="
    head -10 outputs/calculator_models_summary.csv
    echo ""
    echo "File size: $(wc -l < outputs/calculator_models_summary.csv) lines"
else
    echo "Results file not created yet - script still running..."
fi

echo ""
echo "To view full log: tail -f calculator_run_improved.log"

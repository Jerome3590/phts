# Logging Standards

Consistent logging patterns across all analysis workflows and scripts.

## Standard Prefixes

- **`→`** - Action/process in progress (e.g., "→ Reading MC-CV results...")
- **`✓`** - Success/completion (e.g., "✓ Saved: feature_importance_heatmap.png")
- **`⚠`** - Warning (e.g., "⚠ No data available to generate cohort Sankey diagram.")
- **`✗`** - Error (typically used with `stop()` or `warning()`)

## Message Patterns

### Actions (In Progress)
```r
cat("→ Reading MC-CV results...\n")
cat("→ Creating feature importance heatmap...\n")
cat(sprintf("→ Cleaning %d existing plot files...\n", length(plot_files)))
```

### Success Messages
```r
cat("✓ Plots directory cleaned\n")
cat("✓ Saved: feature_importance_heatmap.png\n")
cat(sprintf("✓ Loaded %d/%d expected feature files\n", loaded_count, expected_files))
```

### Multi-line Success Messages
```r
cat(sprintf("✓ Loaded %d/%d expected feature files\n", loaded_count, expected_files))
cat(sprintf("  Total features loaded: %d\n", nrow(all_features)))
cat(sprintf("  Unique features: %d\n", length(unique(all_features$feature))))
```

### Warnings
```r
cat("⚠ No data available to generate cohort Sankey diagram.\n")
warning(sprintf("File not found: %s", file_path))
```

### Errors
```r
stop("Cannot find outputs directory. Expected 'outputs/' relative to current working directory: ", current_dir)
```

## Section Headers

Use consistent separators for major sections:

```r
cat("\n========================================\n")
cat("Visualization Summary\n")
cat("========================================\n")
```

## Summary Outputs

All visualization scripts end with a consistent summary format:

```r
cat("\n========================================\n")
cat("Visualization Summary\n")
cat("========================================\n")
cat(sprintf("Plots saved to: %s\n", normalizePath(plot_dir)))
cat("Created visualizations:\n")
cat("  1. feature_importance_heatmap.png - Description\n")
cat("  2. cindex_heatmap.png - Description\n")
# ... etc
```

## Implementation

### Current Status

✅ **Standardized:**
- `scripts/R/create_visualizations.R`
- `scripts/R/create_visualizations_cohort.R`

### Notes

- Always end single-line messages with `\n`
- Use `cat(sprintf(...))` for formatted messages with variables
- Use `cat(...)` for simple static messages
- Use `print()` for data frames/tables when displaying to console
- Keep messages concise but informative


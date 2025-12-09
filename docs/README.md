# Documentation Index

This directory contains detailed documentation for all analysis workflows, organized by workflow.

## Structure

```
docs/
├── cohort_analysis/          # Clinical cohort analysis documentation
├── feature_importance/       # Global feature importance documentation
└── scripts/                  # Scripts and standards documentation
```

## Documentation by Workflow

### Clinical Cohort Analysis (`docs/cohort_analysis/`)

- **[Notebook Guide](cohort_analysis/README_notebook_guide.md)** - Detailed walkthrough of the clinical cohort analysis notebook
- **[Ready to Run](cohort_analysis/README_ready_to_run.md)** - Step-by-step execution instructions
- **[MC-CV Parallel EC2](cohort_analysis/README_mc_cv_parallel_ec2.md)** - EC2 deployment and parallel processing guide
- **[Original vs Updated Study](cohort_analysis/README_original_vs_updated_study.md)** - Methodology comparison with original study
- **[Validation & Leakage](shared/README_validation_concordance_variables_leakage.md)** - Validation procedures and leakage prevention (shared)

### Global Feature Importance (`docs/feature_importance/`)

- **[Graft Loss Overview](feature_importance/README_graft_loss.md)** - Overview of the graft loss analysis
- **[Notebook Guide](feature_importance/README_notebook_guide.md)** - Detailed walkthrough of the feature importance notebook
- **[Ready to Run](feature_importance/README_ready_to_run.md)** - Step-by-step execution instructions
- **[MC-CV Parallel EC2](feature_importance/README_mc_cv_parallel_ec2.md)** - EC2 deployment and parallel processing guide
- **[Original vs Updated Study](feature_importance/README_original_vs_updated_study.md)** - Methodology comparison with original study
- **[Target Leakage](feature_importance/README_target_leakage.md)** - Target leakage prevention strategies
- **[Validation & Leakage](shared/README_validation_concordance_variables_leakage.md)** - Validation procedures and leakage prevention (shared)

### Shared Documentation (`docs/shared/`)

- **[Validation & Leakage](shared/README_validation_concordance_variables_leakage.md)** - Validation procedures, C-index implementation, variable mapping, and target leakage prevention (applies to all workflows)

### Scripts & Standards (`docs/scripts/`)

- **[Standards & Conventions](scripts/README_standards.md)** - Consolidated standards document covering logging, outputs structure, and script organization

## Quick Links

- **Main Project README**: [../README.md](../README.md)
- **Clinical Cohort Analysis**: [../graft-loss/cohort_analysis/README.md](../graft-loss/cohort_analysis/README.md)
- **Global Feature Importance**: [../graft-loss/feature_importance/README.md](../graft-loss/feature_importance/README.md)
- **Scripts Directory**: [../scripts/README.md](../scripts/README.md)


# Predictive Model Concordance Index and Feature Importance Across Cohorts

Across three cohorts, the concordance index (c-index) results reveal key differences in predictive performance for the RSF (Random Survival Forest) and CatBoost algorithms, influenced by both cohort composition and feature selection.

### Comparison Across Cohorts

| Cohort | RSF c-index (Top 15) | CatBoost c-index (Top 15) | RSF c-index (All) | CatBoost c-index (All) |
| :-- | :-- | :-- | :-- | :-- |
| Original | 0.8143 | 0.8721 | 0.8215 | 0.8777 |
| Full | 0.8478 | 0.7952 | 0.8544 | 0.8119 |
| Full_No_Covid | 0.8184 | 0.8603 | 0.8251 | 0.8678 |

#### Trends and Interpretation

- **Original Cohort:** CatBoost outperforms RSF for both feature sets, with c-index values around 0.87 compared to RSF’s 0.81–0.82, indicating better discrimination by CatBoost in this setting.
- **Full Cohort:** RSF achieves its highest c-index in this cohort (~0.85), while CatBoost’s performance drops to ~0.80–0.81, reversing their relative ranking.
- **Full_No_Covid Cohort:** CatBoost regains an edge with c-indexes near 0.86, while RSF remains stable near 0.82–0.83.


#### Algorithm and Feature Effects

- CatBoost generally excels in the original and COVID-excluded cohorts, while RSF peaks in the full cohort—suggesting sensitivity to cohort composition and possibly relevance of certain features.
- Using all available features (19) slightly boosts both algorithms, especially RSF, but CatBoost’s relative advantage is preserved across most scenarios.


### Summary

The concordance index analysis indicates that CatBoost offers superior outcome discrimination in the original and COVID-excluded cohorts, while RSF overtakes CatBoost in the full cohort. Choice of algorithm is cohort- and feature-dependent.

***

## Feature Importance: Agreement and Differences

Comparison of feature importance shows substantial overlap but meaningful differences between RSF and CatBoost.

### Where the Models Agree

Both models consistently rank certain features among the most important across all cohorts:

- Common top predictors include age at listing, transplantation year, type of bun ratio, alternate transplant marker, transplant year, and recipient weight.
- For example, in the "original" cohort, both agree on age_listing, listing_year, txalt, txbun_r, txpl_year, and weight_txpl in their top 10 rankings.
- This consensus repeats for most cohorts, suggesting these variables predict outcomes robustly, regardless of cohort.


### Where the Models Differ

Distinct splits are observed:

- CatBoost consistently ranks bmi_txpl and egfr_tx highly among its top variables, whereas RSF features clinical diagnostic variables (prim_dx, hxsurg, txecmo) at the top, and rarely highlights BMI or eGFR markers.
- RSF emphasizes comorbidity variables: prim_dx, txecmo, and hxsurg, almost always in the highest slots, but CatBoost places them much lower.
- RSF sometimes highlights pra_listing and height_txpl, which are less important for CatBoost.


### Top 10 Feature Comparison by Cohort

| Cohort | RSF Top Features | CatBoost Top Features | Overlap |
| :-- | :-- | :-- | :-- |
| Original | prim_dx, txecmo, hxsurg, txbun_r, height_txpl, txpl_year, weight_txpl, listing_year, txalt, age_listing | bmi_txpl, txbun_r, txalt, egfr_tx, txsa_r, listing_year, weight_txpl, txpl_year, age_listing, age_txpl | age_listing, listing_year, txalt, txbun_r, txpl_year, weight_txpl |
| Full | prim_dx, txecmo, hxsurg, txbun_r, age_listing, pra_listing, age_txpl, weight_txpl, height_txpl, txalt | txpl_year, listing_year, bmi_txpl, txalt, txbun_r, egfr_tx, txsa_r, age_listing, weight_txpl, age_txpl | age_listing, age_txpl, txalt, txbun_r, weight_txpl |
| Full_No_Covid | prim_dx, txecmo, hxsurg, weight_txpl, height_txpl, txbun_r, txalt, age_listing, txpl_year, age_txpl | bmi_txpl, txalt, txbun_r, egfr_tx, txpl_year, listing_year, txsa_r, age_listing, weight_txpl, age_txpl | age_listing, age_txpl, txalt, txbun_r, txpl_year, weight_txpl |

### Summary

- Both models agree on a core set of six predictors (age_listing, listing_year, txalt, txbun_r, txpl_year, weight_txpl) for every cohort analyzed.
- Disagreement centers on CatBoost's consistently high ranking of bmi_txpl and egfr_tx, versus RSF's focus on diagnostic and comorbidity features.
- RSF may better capture clinical/outcome elements, while CatBoost emphasizes quantitative biomarkers.

Combining features from both approaches may yield stronger, more robust predictions.

***

## Feature Importance During COVID

During the COVID period ("full" cohort), RSF and CatBoost models identify both overlapping and distinct top features.

### Most Important Features During COVID

| Rank | RSF Top Feature | CatBoost Top Feature |
| :-- | :-- | :-- |
| 1 | prim_dx | txpl_year |
| 2 | txecmo | listing_year |
| 3 | hxsurg | bmi_txpl |
| 4 | txbun_r | txalt |
| 5 | age_listing | txbun_r |
| 6 | pra_listing | egfr_tx |
| 7 | age_txpl | txsa_r |
| 8 | weight_txpl | age_listing |
| 9 | height_txpl | weight_txpl |
| 10 | txalt | age_txpl |

- Shared importance: txbun_r, txalt, age_listing, weight_txpl, and age_txpl rank in the top 10 for both models, showing robust predictive value.
- Unique to RSF: Clinical outcome and comorbidity indicators such as prim_dx, txecmo (ECMO usage), hxsurg (surgical history), and pra_listing (panel reactive antibody listing) reflect risk factors specific to the clinical environment during COVID.
- Unique to CatBoost: Emphasizes quantitative/biomarker features like bmi_txpl (BMI), egfr_tx (kidney function), and txsa_r (possibly sodium or other transplant marker), leveraging lab markers and administrative variables.


### Key Trends

- Transplant timing and recipient characteristics (age, weight) remained important during COVID.
- RSF maintained emphasis on comorbidity and acute support features, while CatBoost leaned toward lab and administrative data.

During the pandemic, outcome prediction depended on both patient risk factors and detailed clinical/lab measures; each model surfaced top features reflecting complementary aspects of COVID-era outcomes.


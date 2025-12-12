// Main application JavaScript

let metadata = null;
let currentCohort = 'CHD';
let baselineFeatures = null;

// Initialize application
document.addEventListener('DOMContentLoaded', async () => {
    await loadMetadata();
    setupEventListeners();
    renderFeatureForm();
});

// Load metadata from API
async function loadMetadata() {
    try {
        const response = await fetch(`${CONFIG.API_URL}${CONFIG.ENDPOINTS.METADATA}`);
        if (!response.ok) throw new Error('Failed to load metadata');
        
        metadata = await response.json();
        
        // Update model info in footer
        const modelInfo = document.getElementById('model-info');
        if (metadata.models && metadata.models[currentCohort]) {
            const model = metadata.models[currentCohort];
            modelInfo.textContent = `${currentCohort}: ${model.best_model} (C-index: ${model.c_index.toFixed(3)})`;
        }
    } catch (error) {
        console.error('Error loading metadata:', error);
        document.getElementById('feature-form').innerHTML = 
            '<p class="error">Failed to load feature definitions. Please refresh the page.</p>';
    }
}

// Setup event listeners
function setupEventListeners() {
    // Cohort selection
    document.querySelectorAll('input[name="cohort"]').forEach(radio => {
        radio.addEventListener('change', (e) => {
            currentCohort = e.target.value;
            renderFeatureForm();
            if (metadata && metadata.models && metadata.models[currentCohort]) {
                const model = metadata.models[currentCohort];
                document.getElementById('model-info').textContent = 
                    `${currentCohort}: ${model.best_model} (C-index: ${model.c_index.toFixed(3)})`;
            }
        });
    });

    // Calculate risk button
    document.getElementById('calculate-risk').addEventListener('click', calculateRisk);
    
    // Compare scenarios button
    document.getElementById('compare-scenarios').addEventListener('click', compareScenarios);
    
    // Reset button
    document.getElementById('reset-form').addEventListener('click', resetForm);
}

// Render feature input form
function renderFeatureForm() {
    if (!metadata || !metadata.features) return;
    
    const form = document.getElementById('feature-form');
    const features = metadata.features;
    
    // Group features by category
    const categories = {};
    Object.keys(features).forEach(feature => {
        const info = features[feature];
        const category = info.category || 'Other';
        if (!categories[category]) {
            categories[category] = [];
        }
        categories[category].push({ name: feature, ...info });
    });
    
    // Render form
    let html = '';
    Object.keys(categories).sort().forEach(category => {
        html += `<div class="feature-category">
            <h3>${category}</h3>
            <div class="feature-group">`;
        
        categories[category].forEach(feature => {
            html += renderFeatureInput(feature);
        });
        
        html += `</div></div>`;
    });
    
    form.innerHTML = html;
}

// Render individual feature input
function renderFeatureInput(feature) {
    const { name, type, range, modifiability } = feature;
    
    let inputHtml = '';
    if (type === 'numeric' && range) {
        const [min, max] = range;
        inputHtml = `
            <label>
                <span class="feature-name">${name}</span>
                <span class="feature-modifiability">${modifiability}</span>
                <input type="number" 
                       id="feature-${name}" 
                       name="${name}" 
                       step="0.01" 
                       min="${min}" 
                       max="${max}"
                       placeholder="${min} - ${max}">
            </label>
        `;
    } else if (type === 'categorical') {
        inputHtml = `
            <label>
                <span class="feature-name">${name}</span>
                <span class="feature-modifiability">${modifiability}</span>
                <select id="feature-${name}" name="${name}">
                    <option value="">Select...</option>
                    ${feature.values.map(v => `<option value="${v}">${v}</option>`).join('')}
                </select>
            </label>
        `;
    } else {
        inputHtml = `
            <label>
                <span class="feature-name">${name}</span>
                <span class="feature-modifiability">${modifiability}</span>
                <input type="text" id="feature-${name}" name="${name}" placeholder="Enter value">
            </label>
        `;
    }
    
    return inputHtml;
}

// Collect feature values from form
function collectFeatures() {
    const features = {};
    const inputs = document.querySelectorAll('#feature-form input, #feature-form select');
    
    inputs.forEach(input => {
        if (input.value && input.value !== '') {
            const name = input.name;
            const value = input.type === 'number' ? parseFloat(input.value) : input.value;
            features[name] = value;
        }
    });
    
    return features;
}

// Calculate risk
async function calculateRisk() {
    const features = collectFeatures();
    
    if (Object.keys(features).length === 0) {
        alert('Please enter at least one feature value');
        return;
    }
    
    try {
        const response = await fetch(`${CONFIG.API_URL}${CONFIG.ENDPOINTS.RISK}`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                cohort: currentCohort,
                features: features
            })
        });
        
        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.error || 'Failed to calculate risk');
        }
        
        const result = await response.json();
        displayResults(result);
        baselineFeatures = { ...features };
        
    } catch (error) {
        console.error('Error calculating risk:', error);
        alert(`Error: ${error.message}`);
    }
}

// Display results
function displayResults(result) {
    // Show results section
    document.getElementById('results-section').style.display = 'block';
    
    // Update risk score
    document.getElementById('risk-score').textContent = 
        (result.risk_score * 100).toFixed(1) + '%';
    
    // Update confidence interval
    const ci = result.confidence_interval;
    document.getElementById('confidence-interval').textContent = 
        `95% CI: ${(ci[0] * 100).toFixed(1)}% - ${(ci[1] * 100).toFixed(1)}%`;
    
    // Update percentile
    document.getElementById('risk-percentile').textContent = 
        result.risk_percentile + 'th';
    
    // Display feature contributions
    const contributions = result.feature_contributions || {};
    const contributionsList = document.getElementById('contributions-list');
    contributionsList.innerHTML = '';
    
    const sortedContributions = Object.entries(contributions)
        .sort((a, b) => Math.abs(b[1]) - Math.abs(a[1]))
        .slice(0, 5);
    
    sortedContributions.forEach(([feature, contrib]) => {
        const item = document.createElement('div');
        item.className = 'contribution-item';
        item.innerHTML = `
            <span class="feature-name">${feature}</span>
            <span class="contribution-value ${contrib > 0 ? 'positive' : 'negative'}">
                ${contrib > 0 ? '+' : ''}${(contrib * 100).toFixed(2)}%
            </span>
        `;
        contributionsList.appendChild(item);
    });
    
    // Display recommendations
    const recommendationsList = document.getElementById('recommendations-list');
    recommendationsList.innerHTML = '';
    
    (result.recommendations || []).forEach(rec => {
        const li = document.createElement('li');
        li.textContent = rec;
        recommendationsList.appendChild(li);
    });
}

// Compare scenarios
async function compareScenarios() {
    if (!baselineFeatures) {
        alert('Please calculate baseline risk first');
        return;
    }
    
    const interventionFeatures = collectFeatures();
    
    if (Object.keys(interventionFeatures).length === 0) {
        alert('Please enter intervention feature values');
        return;
    }
    
    try {
        const response = await fetch(`${CONFIG.API_URL}${CONFIG.ENDPOINTS.COMPARISON}`, {
            method: 'POST',
            headers: {
                'Content-Type': 'application/json'
            },
            body: JSON.stringify({
                cohort: currentCohort,
                baseline_features: baselineFeatures,
                intervention_features: interventionFeatures
            })
        });
        
        if (!response.ok) {
            const error = await response.json();
            throw new Error(error.error || 'Failed to compare scenarios');
        }
        
        const result = await response.json();
        displayComparison(result);
        
    } catch (error) {
        console.error('Error comparing scenarios:', error);
        alert(`Error: ${error.message}`);
    }
}

// Display comparison results
function displayComparison(result) {
    document.getElementById('comparison-section').style.display = 'block';
    
    document.getElementById('baseline-risk').textContent = 
        (result.baseline_risk * 100).toFixed(1) + '%';
    
    document.getElementById('intervention-risk').textContent = 
        (result.intervention_risk * 100).toFixed(1) + '%';
    
    document.getElementById('risk-reduction').textContent = 
        (result.risk_reduction * 100).toFixed(1) + '%';
    
    document.getElementById('relative-reduction').textContent = 
        `(${result.relative_risk_reduction.toFixed(1)}% relative reduction)`;
}

// Reset form
function resetForm() {
    document.querySelectorAll('#feature-form input, #feature-form select').forEach(input => {
        input.value = '';
    });
    
    document.getElementById('results-section').style.display = 'none';
    document.getElementById('comparison-section').style.display = 'none';
    baselineFeatures = null;
}


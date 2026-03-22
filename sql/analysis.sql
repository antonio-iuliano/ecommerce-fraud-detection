-- =====================================
-- E-commerce Fraud Detection Project
-- =====================================

-- =======================================
-- 1. SQL Data Preparation & Validation
-- =======================================

-- =========================
-- 1.1 Basic dataset checks
-- =========================

-- Goal: understand dataset size before any transformation

-- Total number of transactions in the raw dataset
SELECT COUNT(*) AS total_transactions
FROM fraud_data;

-- Expected: ~151k transactions
-- This is our reference baseline


-- Total number of IP ranges available for country mapping
SELECT COUNT(*) AS total_ip_ranges
FROM ip_country;

-- ~138k ranges
-- These ranges will be used to map each transaction to a country


-- =========================
-- 1.2 Validate IP-country join
-- =========================

-- Goal: check if IP-to-country mapping works correctly

-- Count how many rows result from the join
SELECT COUNT(*) AS join_rows
FROM fraud_data f
JOIN ip_country c
  ON CAST(f.ip_address AS BIGINT)
     BETWEEN c.lower_bound_ip_address 
         AND c.upper_bound_ip_address;

-- Observation:
-- Result is MUCH larger than original dataset (~1.2M rows vs 151k)
-- → This indicates that each transaction matches multiple IP ranges
-- → Therefore, the join introduces duplicates


-- Check how many matches each transaction has
SELECT 
    f.user_id,
    COUNT(*) AS matches
FROM fraud_data f
JOIN ip_country c
  ON CAST(f.ip_address AS BIGINT)
     BETWEEN c.lower_bound_ip_address 
         AND c.upper_bound_ip_address
GROUP BY f.user_id
ORDER BY matches DESC
LIMIT 10;

-- Observation:
-- Each transaction matches ~13 IP ranges on average
-- → Confirms duplication problem
-- → We need to select ONE country per transaction


-- =========================
-- 1.3 Create clean dataset
-- =========================

-- Goal: build a usable dataset with exactly one country per transaction

-- Remove existing table if re-running script
DROP TABLE IF EXISTS fraud_with_country;

-- Create cleaned dataset
CREATE TABLE fraud_with_country AS
SELECT DISTINCT ON (f.user_id)
    f.*,
    c.country
FROM fraud_data f
JOIN ip_country c
  ON CAST(f.ip_address AS BIGINT)
     BETWEEN c.lower_bound_ip_address 
         AND c.upper_bound_ip_address
ORDER BY f.user_id, c.lower_bound_ip_address;

-- Explanation:
-- DISTINCT ON ensures only one match per transaction
-- ORDER BY ensures consistency (smallest IP range is selected)
-- This avoids randomness in country assignment


-- =========================
-- 1.4 Validate cleaned dataset
-- =========================

-- Check number of transactions after cleaning
SELECT COUNT(*) AS cleaned_transactions
FROM fraud_with_country;

-- Observation:
-- Result ≈ 131k rows
-- → lower than original dataset (~151k)
-- → indicates some transactions did not match any IP range


-- Count how many transactions could not be mapped to a country
SELECT 
    COUNT(*) AS missing_country_rows
FROM fraud_data f
LEFT JOIN ip_country c
  ON CAST(f.ip_address AS BIGINT)
     BETWEEN c.lower_bound_ip_address 
         AND c.upper_bound_ip_address
WHERE c.country IS NULL;

-- Interpretation:
-- ~19k transactions have no country
-- → normal limitation of IP mapping datasets
-- → these rows are excluded from further analysis


-- =========================
-- Conclusion of this section
-- =========================

-- We successfully transformed raw data into a clean analytical dataset:
-- - Removed duplicate matches from IP range joins
-- - Assigned one country per transaction
-- - Filtered out transactions with unknown location

-- The table `fraud_with_country` is now ready for analysis





-- =====================================
-- 2. Exploratory Data Analysis (EDA)
-- =====================================


-- =========================
-- 2.1 Global Fraud Overview
-- =========================

-- Goal:
-- Understand the overall scale of fraud in the dataset
-- This provides a baseline for all further analysis


-- Total number of transactions and fraud cases
SELECT 
    COUNT(*) AS total_transactions,
    SUM(class) AS total_fraud,
    ROUND(100.0 * SUM(class) / COUNT(*), 2) AS fraud_rate_percent
FROM fraud_with_country;
-- Observation:
-- The dataset contains 131,729 transactions, including 12,542 fraud cases.

-- Interpretation:
-- Fraud represents a small portion of the data but remains significant.



-- Distribution of fraud vs non-fraud transactions
SELECT 
    class,
    COUNT(*) AS transaction_count,
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (), 2) AS percentage
FROM fraud_with_country
GROUP BY class;
-- Observation:
-- Fraud accounts for 9.52% of transactions, while 90.48% are legitimate.

-- Interpretation:
-- The dataset is imbalanced, which is typical for fraud detection.




-- =========================
-- 2.2 Fraud by Country
-- =========================

-- Goal:
-- Identify geographic patterns in fraudulent transactions
-- Compare both fraud volume and fraud rate across countries


-- Fraud volume by country
SELECT 
    country,
    COUNT(*) AS total_transactions,
    SUM(class) AS total_fraud
FROM fraud_with_country
GROUP BY country
ORDER BY total_fraud DESC
LIMIT 10;
-- Observation:
-- Australia has the highest number of fraud cases, followed by the Netherlands and the United States.

-- Interpretation:
-- These countries likely have higher transaction volumes, which naturally leads to more fraud cases.
-- High fraud volume does not necessarily indicate higher risk.



-- Fraud rate by country (only countries with enough data)
SELECT 
    country,
    COUNT(*) AS total_transactions,
    SUM(class) AS total_fraud,
    ROUND(100.0 * SUM(class) / COUNT(*), 2) AS fraud_rate_percent
FROM fraud_with_country
GROUP BY country
HAVING COUNT(*) > 100
ORDER BY fraud_rate_percent DESC
LIMIT 10;
-- Observation:
-- Japan, Korea, and Brazil show the highest fraud rates, all above 10%.

-- Interpretation:
-- These countries appear to have a higher fraud risk per transaction,
-- suggesting that fraud is more concentrated in these regions compared to others.

-- Key Insight:
-- Fraud is not evenly distributed geographically:
-- some countries drive volume, while others show higher risk.





-- =========================
-- 2.3 Fraud by Device and Browser
-- =========================

-- Goal:
-- Identify whether certain devices or browsers are associated with more fraud



-- Fraud rate by browser
SELECT
    browser,
    COUNT(*) AS total_transactions,
    SUM(class) AS total_fraud,
    ROUND(100.0 * SUM(class) / COUNT(*), 2) AS fraud_rate_percent
FROM fraud_with_country
GROUP BY browser
ORDER BY fraud_rate_percent DESC;
-- Observation:
-- Chrome shows the highest fraud rate (~10.12%), while Internet Explorer has the lowest (~8.71%).

-- Interpretation:
-- Differences between browsers are relatively small,
-- suggesting that browser type alone is not a strong indicator of fraud risk.



-- Fraud rate by source
SELECT
    source,
    COUNT(*) AS total_transactions,
    SUM(class) AS total_fraud,
    ROUND(100.0 * SUM(class) / COUNT(*), 2) AS fraud_rate_percent
FROM fraud_with_country
GROUP BY source
ORDER BY fraud_rate_percent DESC;
-- Observation:
-- Direct traffic has the highest fraud rate (~10.47%), followed by Ads and SEO.

-- Interpretation:
-- Traffic source does not appear to be a strong differentiating factor for fraud in this dataset.
-- This suggests that fraudulent activity is relatively evenly distributed across acquisition channels.



-- =========================
-- 2.4 Time Analysis
-- =========================

-- Goal:
-- Identify when fraud is more likely to occur


-- Fraud by hour of day
SELECT
    EXTRACT(HOUR FROM purchase_time::timestamp) AS hour_of_day,
    COUNT(*) AS total_transactions,
    SUM(class) AS total_fraud,
    ROUND(100.0 * SUM(class) / COUNT(*), 2) AS fraud_rate_percent
FROM fraud_with_country
GROUP BY hour_of_day
ORDER BY hour_of_day;
-- Observation:
-- Fraud rates vary slightly throughout the day, with peaks around 8–10 AM and late afternoon (around 5 PM).

-- Interpretation:
-- Fraud activity does not strongly depend on time of day,
-- although slight increases during active hours may reflect higher transaction volume.



-- Fraud by day of week
SELECT
    EXTRACT(DOW FROM purchase_time::timestamp) AS hour_of_day,
    COUNT(*) AS total_transactions,
    SUM(class) AS total_fraud,
    ROUND(100.0 * SUM(class) / COUNT(*), 2) AS fraud_rate_percent
FROM fraud_with_country
GROUP BY hour_of_day
ORDER BY hour_of_day;
-- Observation:
-- Fraud rates are relatively consistent across all days of the week.

-- Interpretation:
-- There is no strong weekly pattern in fraud behavior,
-- suggesting that fraudulent activity occurs steadily rather than being concentrated on specific days.



-- Time to purchase grouped into buckets
SELECT
    CASE
        WHEN EXTRACT(EPOCH FROM (purchase_time::timestamp - signup_time::timestamp)) / 60 < 1 THEN '<1 min'
        WHEN EXTRACT(EPOCH FROM (purchase_time::timestamp - signup_time::timestamp)) / 60 < 10 THEN '1-10 min'
        WHEN EXTRACT(EPOCH FROM (purchase_time::timestamp - signup_time::timestamp)) / 60 < 60 THEN '10-60 min'
        WHEN EXTRACT(EPOCH FROM (purchase_time::timestamp - signup_time::timestamp)) / 60 < 1440 THEN '1-24h'
        ELSE '>24h'
    END AS time_bucket,
    COUNT(*) AS total_transactions,
    SUM(class) AS total_fraud,
    ROUND(100.0 * SUM(class) / COUNT(*), 2) AS fraud_rate_percent
FROM fraud_with_country
GROUP BY time_bucket
ORDER BY time_bucket;
-- Observation:
-- Transactions made within less than 1 minute after signup have a 100% fraud rate,
-- while transactions occurring after longer periods show significantly lower fraud rates.

-- Interpretation:
-- Extremely fast purchases after account creation are highly suspicious,
-- suggesting automated or fraudulent behavior.
-- This is the strongest fraud signal observed so far.

-- Note:
-- The 100% fraud rate for very fast transactions may indicate either a strong fraud pattern
-- or a potential bias/feature of the dataset.
-- This should be interpreted with caution.



-- =========================================
-- 3. User behavior analysis
-- =========================================

-- Goal:
-- Analyze whether fraudulent users behave differently from normal users

-- Transactions per user
SELECT
    user_id,
    COUNT(*) AS nb_transactions,
    SUM(class) AS nb_fraud
FROM fraud_with_country
GROUP BY user_id;
-- Observation:
-- Each user appears only once in the dataset (one transaction per user).

-- Interpretation:
-- As a result, it is not possible to analyze user-level behavioral patterns
-- such as repeat fraud or differences between fraudulent and normal users.

-- Conclusion:
-- The analysis will therefore focus on transaction-level features only.





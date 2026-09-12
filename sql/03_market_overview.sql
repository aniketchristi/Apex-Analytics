-- Apex Analytics
-- Market overview analysis

-- 1. Brand-level market overview
SELECT
    manufacturer,
    COUNT(*) AS listings,
    ROUND(AVG(price)::numeric, 2) AS avg_price,
    ROUND(
        PERCENTILE_CONT(0.5)
        WITHIN GROUP (ORDER BY price)::numeric,
        2
    ) AS median_price,
    ROUND(AVG(mileage)::numeric, 0) AS avg_mileage,
    MIN(year) AS earliest_year,
    MAX(year) AS latest_year
FROM vehicle_listings
GROUP BY manufacturer
ORDER BY listings DESC;


-- 2. Model-family overview
SELECT
    manufacturer,
    model_family,
    project_scope,
    COUNT(*) AS listings,
    ROUND(
        PERCENTILE_CONT(0.5)
        WITHIN GROUP (ORDER BY price)::numeric,
        2
    ) AS median_price,
    ROUND(
        PERCENTILE_CONT(0.5)
        WITHIN GROUP (ORDER BY mileage)::numeric,
        0
    ) AS median_mileage,
    MIN(year) AS earliest_year,
    MAX(year) AS latest_year
FROM vehicle_listings
GROUP BY
    manufacturer,
    model_family,
    project_scope
ORDER BY listings DESC;


-- 3. Core vs Supporting scope
SELECT
    project_scope,
    COUNT(*) AS listings,
    ROUND(
        PERCENTILE_CONT(0.5)
        WITHIN GROUP (ORDER BY price)::numeric,
        2
    ) AS median_price,
    ROUND(
        PERCENTILE_CONT(0.5)
        WITHIN GROUP (ORDER BY mileage)::numeric,
        0
    ) AS median_mileage
FROM vehicle_listings
GROUP BY project_scope
ORDER BY listings DESC;

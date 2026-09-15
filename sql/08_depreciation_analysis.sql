-- Apex Analytics
-- Cross-sectional depreciation / age-price analysis
--
-- Important:
-- This dataset contains current marketplace asking prices,
-- not longitudinal transaction histories.
-- Therefore, results are interpreted as age-price relationships
-- and depreciation proxies rather than observed depreciation.


-- 1. Evaluate model/generation coverage for age-price analysis
WITH eligible_listings AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        price,
        NULLIF(mileage, 0) AS analysis_mileage

    FROM vehicle_listings

    WHERE generation_quality_flag = 'Mapped'
      AND price > 0
      AND mileage > 0
),

model_generation_coverage AS (
    SELECT
        manufacturer,
        model,
        generation,

        COUNT(*) AS listings,
        COUNT(DISTINCT year) AS model_years,

        MIN(year) AS earliest_year,
        MAX(year) AS latest_year,

        MAX(year) - MIN(year) AS year_span

    FROM eligible_listings

    GROUP BY
        manufacturer,
        model,
        generation
)

SELECT
    COUNT(*) AS model_generation_groups,

    COUNT(*) FILTER (
        WHERE model_years >= 3
          AND listings >= 30
    ) AS groups_3years_30listings,

    SUM(listings) FILTER (
        WHERE model_years >= 3
          AND listings >= 30
    ) AS listings_3years_30listings,

    COUNT(*) FILTER (
        WHERE model_years >= 4
          AND listings >= 50
    ) AS groups_4years_50listings,

    SUM(listings) FILTER (
        WHERE model_years >= 4
          AND listings >= 50
    ) AS listings_4years_50listings,

    COUNT(*) FILTER (
        WHERE model_years >= 5
          AND listings >= 75
    ) AS groups_5years_75listings,

    SUM(listings) FILTER (
        WHERE model_years >= 5
          AND listings >= 75
    ) AS listings_5years_75listings

FROM model_generation_coverage;


-- 2. Cross-sectional age-price slope by model and generation
--
-- Each model year contributes one median-price observation
-- so high-volume years do not dominate the regression.
--
-- Positive slope:
-- newer model years tend to have higher asking prices.
--
-- This is an age-price proxy, not observed longitudinal depreciation.

WITH eligible_listings AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        price,
        NULLIF(mileage, 0) AS analysis_mileage

    FROM vehicle_listings

    WHERE generation_quality_flag = 'Mapped'
      AND price > 0
      AND mileage > 0
),

year_stats AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,

        COUNT(*) AS listings,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price)
            AS median_price,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY analysis_mileage)
            AS median_mileage

    FROM eligible_listings

    GROUP BY
        manufacturer,
        model,
        generation,
        year
),

qualified_models AS (
    SELECT
        manufacturer,
        model,
        generation,

        COUNT(*) AS model_years,
        SUM(listings) AS listings,

        MIN(year) AS earliest_year,
        MAX(year) AS latest_year,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY median_price)
            AS overall_median_price

    FROM year_stats

    GROUP BY
        manufacturer,
        model,
        generation

    HAVING COUNT(*) >= 4
       AND SUM(listings) >= 50
),

regression_results AS (
    SELECT
        y.manufacturer,
        y.model,
        y.generation,

        COUNT(*) AS model_years,
        SUM(y.listings) AS listings,

        MIN(y.year) AS earliest_year,
        MAX(y.year) AS latest_year,

        REGR_SLOPE(
            y.median_price,
            y.year
        ) AS price_change_per_model_year,

        REGR_R2(
            y.median_price,
            y.year
        ) AS price_year_r2,

        q.overall_median_price

    FROM year_stats y

    JOIN qualified_models q
        ON y.manufacturer = q.manufacturer
        AND y.model = q.model
        AND y.generation = q.generation

    GROUP BY
        y.manufacturer,
        y.model,
        y.generation,
        q.overall_median_price
)

SELECT
    manufacturer,
    model,
    generation,
    model_years,
    listings,
    earliest_year,
    latest_year,

    ROUND(
        price_change_per_model_year::numeric,
        2
    ) AS price_change_per_model_year,

    ROUND(
        (
            price_change_per_model_year
            / NULLIF(overall_median_price, 0)
            * 100
        )::numeric,
        1
    ) AS annual_price_change_pct_of_median,

    ROUND(
        price_year_r2::numeric,
        3
    ) AS price_year_r2

FROM regression_results

ORDER BY annual_price_change_pct_of_median DESC;


-- 3. Evaluate reliability thresholds for age-price regressions
WITH eligible_listings AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        price,
        NULLIF(mileage, 0) AS analysis_mileage

    FROM vehicle_listings

    WHERE generation_quality_flag = 'Mapped'
      AND price > 0
      AND mileage > 0
),

year_stats AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,

        COUNT(*) AS listings,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price)
            AS median_price

    FROM eligible_listings

    GROUP BY
        manufacturer,
        model,
        generation,
        year
),

qualified_models AS (
    SELECT
        manufacturer,
        model,
        generation,

        COUNT(*) AS model_years,
        SUM(listings) AS listings

    FROM year_stats

    GROUP BY
        manufacturer,
        model,
        generation

    HAVING COUNT(*) >= 4
       AND SUM(listings) >= 50
),

regression_results AS (
    SELECT
        y.manufacturer,
        y.model,
        y.generation,

        COUNT(*) AS model_years,
        SUM(y.listings) AS listings,

        REGR_R2(
            y.median_price,
            y.year
        ) AS price_year_r2

    FROM year_stats y

    JOIN qualified_models q
        ON y.manufacturer = q.manufacturer
        AND y.model = q.model
        AND y.generation = q.generation

    GROUP BY
        y.manufacturer,
        y.model,
        y.generation
)

SELECT
    COUNT(*) AS total_groups,

    COUNT(*) FILTER (
        WHERE price_year_r2 >= 0.50
    ) AS groups_r2_50,

    SUM(listings) FILTER (
        WHERE price_year_r2 >= 0.50
    ) AS listings_r2_50,

    COUNT(*) FILTER (
        WHERE price_year_r2 >= 0.70
    ) AS groups_r2_70,

    SUM(listings) FILTER (
        WHERE price_year_r2 >= 0.70
    ) AS listings_r2_70,

    COUNT(*) FILTER (
        WHERE price_year_r2 >= 0.80
    ) AS groups_r2_80,

    SUM(listings) FILTER (
        WHERE price_year_r2 >= 0.80
    ) AS listings_r2_80

FROM regression_results;


-- 4. Evaluate coverage for mileage-adjusted age-price analysis
--
-- Model-year effects will be estimated separately within
-- mileage bands so age is not compared across radically
-- different mileage levels.

WITH prepared_listings AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        price,

        CASE
            WHEN mileage > 0 AND mileage < 10000 THEN '00-09k'
            WHEN mileage >= 10000 AND mileage < 25000 THEN '10-24k'
            WHEN mileage >= 25000 AND mileage < 50000 THEN '25-49k'
            WHEN mileage >= 50000 AND mileage < 75000 THEN '50-74k'
            WHEN mileage >= 75000 AND mileage < 100000 THEN '75-99k'
            WHEN mileage >= 100000 THEN '100k+'
            ELSE NULL
        END AS mileage_band

    FROM vehicle_listings

    WHERE generation_quality_flag = 'Mapped'
      AND price > 0
      AND mileage > 0
),

year_band_stats AS (
    SELECT
        manufacturer,
        model,
        generation,
        mileage_band,
        year,

        COUNT(*) AS listings,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price)
            AS median_price

    FROM prepared_listings

    GROUP BY
        manufacturer,
        model,
        generation,
        mileage_band,
        year

    HAVING COUNT(*) >= 3
),

band_coverage AS (
    SELECT
        manufacturer,
        model,
        generation,
        mileage_band,

        COUNT(*) AS model_years,
        SUM(listings) AS listings

    FROM year_band_stats

    GROUP BY
        manufacturer,
        model,
        generation,
        mileage_band

    HAVING COUNT(*) >= 3
),

model_coverage AS (
    SELECT
        manufacturer,
        model,
        generation,

        COUNT(*) AS usable_mileage_bands,
        SUM(listings) AS listings

    FROM band_coverage

    GROUP BY
        manufacturer,
        model,
        generation
)

SELECT
    COUNT(*) AS model_generation_groups,

    COUNT(*) FILTER (
        WHERE usable_mileage_bands >= 1
    ) AS groups_with_1_band,

    SUM(listings) FILTER (
        WHERE usable_mileage_bands >= 1
    ) AS listings_with_1_band,

    COUNT(*) FILTER (
        WHERE usable_mileage_bands >= 2
    ) AS groups_with_2_bands,

    SUM(listings) FILTER (
        WHERE usable_mileage_bands >= 2
    ) AS listings_with_2_bands,

    COUNT(*) FILTER (
        WHERE usable_mileage_bands >= 3
    ) AS groups_with_3_bands,

    SUM(listings) FILTER (
        WHERE usable_mileage_bands >= 3
    ) AS listings_with_3_bands

FROM model_coverage;


-- 5. Evaluate reliability of mileage-band age-price regressions
WITH prepared_listings AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        price,

        CASE
            WHEN mileage > 0 AND mileage < 10000 THEN '00-09k'
            WHEN mileage >= 10000 AND mileage < 25000 THEN '10-24k'
            WHEN mileage >= 25000 AND mileage < 50000 THEN '25-49k'
            WHEN mileage >= 50000 AND mileage < 75000 THEN '50-74k'
            WHEN mileage >= 75000 AND mileage < 100000 THEN '75-99k'
            WHEN mileage >= 100000 THEN '100k+'
            ELSE NULL
        END AS mileage_band

    FROM vehicle_listings

    WHERE generation_quality_flag = 'Mapped'
      AND price > 0
      AND mileage > 0
),

year_band_stats AS (
    SELECT
        manufacturer,
        model,
        generation,
        mileage_band,
        year,

        COUNT(*) AS listings,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price)
            AS median_price

    FROM prepared_listings

    GROUP BY
        manufacturer,
        model,
        generation,
        mileage_band,
        year

    HAVING COUNT(*) >= 3
),

band_regressions AS (
    SELECT
        manufacturer,
        model,
        generation,
        mileage_band,

        COUNT(*) AS model_years,
        SUM(listings) AS listings,

        REGR_SLOPE(
            median_price,
            year
        ) AS price_change_per_model_year,

        REGR_R2(
            median_price,
            year
        ) AS price_year_r2

    FROM year_band_stats

    GROUP BY
        manufacturer,
        model,
        generation,
        mileage_band

    HAVING COUNT(*) >= 3
),

model_reliability AS (
    SELECT
        manufacturer,
        model,
        generation,

        COUNT(*) AS total_usable_bands,

        COUNT(*) FILTER (
            WHERE price_year_r2 >= 0.50
        ) AS reliable_bands_r2_50,

        COUNT(*) FILTER (
            WHERE price_year_r2 >= 0.70
        ) AS reliable_bands_r2_70,

        SUM(listings) FILTER (
            WHERE price_year_r2 >= 0.50
        ) AS listings_r2_50,

        SUM(listings) FILTER (
            WHERE price_year_r2 >= 0.70
        ) AS listings_r2_70

    FROM band_regressions

    GROUP BY
        manufacturer,
        model,
        generation
)

SELECT
    COUNT(*) FILTER (
        WHERE reliable_bands_r2_50 >= 2
    ) AS groups_2bands_r2_50,

    SUM(listings_r2_50) FILTER (
        WHERE reliable_bands_r2_50 >= 2
    ) AS listings_2bands_r2_50,

    COUNT(*) FILTER (
        WHERE reliable_bands_r2_70 >= 2
    ) AS groups_2bands_r2_70,

    SUM(listings_r2_70) FILTER (
        WHERE reliable_bands_r2_70 >= 2
    ) AS listings_2bands_r2_70

FROM model_reliability;


-- 6. Final mileage-adjusted age-price retention proxy
--
-- Methodology:
-- - exact model + generation
-- - at least 4 model years and 50 listings overall
-- - annual median prices calculated within mileage bands
-- - at least 3 listings per model-year / mileage-band cell
-- - at least 3 model years per mileage-band regression
-- - only mileage-band regressions with R² >= 0.70
-- - at least 2 reliable mileage bands per model/generation
--
-- Lower positive values indicate stronger age-related
-- price retention within comparable mileage ranges.
--
-- Negative values would indicate that older model years
-- sometimes command higher prices and should be interpreted
-- as possible collector/market effects rather than depreciation.

WITH prepared_listings AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        price,

        CASE
            WHEN mileage > 0 AND mileage < 10000 THEN '00-09k'
            WHEN mileage >= 10000 AND mileage < 25000 THEN '10-24k'
            WHEN mileage >= 25000 AND mileage < 50000 THEN '25-49k'
            WHEN mileage >= 50000 AND mileage < 75000 THEN '50-74k'
            WHEN mileage >= 75000 AND mileage < 100000 THEN '75-99k'
            WHEN mileage >= 100000 THEN '100k+'
            ELSE NULL
        END AS mileage_band

    FROM vehicle_listings

    WHERE generation_quality_flag = 'Mapped'
      AND price > 0
      AND mileage > 0
),

overall_coverage AS (
    SELECT
        manufacturer,
        model,
        generation,

        COUNT(*) AS overall_listings,
        COUNT(DISTINCT year) AS overall_model_years

    FROM prepared_listings

    GROUP BY
        manufacturer,
        model,
        generation

    HAVING COUNT(*) >= 50
       AND COUNT(DISTINCT year) >= 4
),

year_band_stats AS (
    SELECT
        manufacturer,
        model,
        generation,
        mileage_band,
        year,

        COUNT(*) AS listings,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price)
            AS median_price

    FROM prepared_listings

    GROUP BY
        manufacturer,
        model,
        generation,
        mileage_band,
        year

    HAVING COUNT(*) >= 3
),

band_regressions AS (
    SELECT
        manufacturer,
        model,
        generation,
        mileage_band,

        COUNT(*) AS model_years,
        SUM(listings) AS listings,

        REGR_SLOPE(
            median_price,
            year
        ) AS price_change_per_model_year,

        REGR_R2(
            median_price,
            year
        ) AS price_year_r2,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY median_price)
            AS band_median_price

    FROM year_band_stats

    GROUP BY
        manufacturer,
        model,
        generation,
        mileage_band

    HAVING COUNT(*) >= 3
),

reliable_bands AS (
    SELECT
        *,

        (
            price_change_per_model_year
            / NULLIF(band_median_price, 0)
            * 100
        ) AS annual_age_price_gap_pct

    FROM band_regressions

    WHERE price_year_r2 >= 0.70
),

model_summary AS (
    SELECT
        r.manufacturer,
        r.model,
        r.generation,

        o.overall_model_years,
        o.overall_listings,

        COUNT(*) AS reliable_mileage_bands,

        SUM(r.listings)
            AS listings_in_reliable_bands,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (
                ORDER BY r.annual_age_price_gap_pct
            ) AS median_annual_age_price_gap_pct,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (
                ORDER BY r.price_year_r2
            ) AS median_band_r2,

        MIN(r.annual_age_price_gap_pct)
            AS lowest_band_age_price_gap_pct,

        MAX(r.annual_age_price_gap_pct)
            AS highest_band_age_price_gap_pct

    FROM reliable_bands r

    JOIN overall_coverage o
        ON r.manufacturer = o.manufacturer
        AND r.model = o.model
        AND r.generation = o.generation

    GROUP BY
        r.manufacturer,
        r.model,
        r.generation,
        o.overall_model_years,
        o.overall_listings

    HAVING COUNT(*) >= 2
)

SELECT
    manufacturer,
    model,
    generation,

    overall_model_years,
    overall_listings,
    reliable_mileage_bands,
    listings_in_reliable_bands,

    ROUND(
        median_annual_age_price_gap_pct::numeric,
        1
    ) AS median_annual_age_price_gap_pct,

    ROUND(
        median_band_r2::numeric,
        3
    ) AS median_band_r2,

    ROUND(
        lowest_band_age_price_gap_pct::numeric,
        1
    ) AS lowest_band_age_price_gap_pct,

    ROUND(
        highest_band_age_price_gap_pct::numeric,
        1
    ) AS highest_band_age_price_gap_pct

FROM model_summary

ORDER BY median_annual_age_price_gap_pct ASC;

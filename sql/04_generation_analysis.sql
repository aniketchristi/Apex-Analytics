-- Apex Analytics
-- Generation-level enthusiast market analysis


-- 1. Generation-level market overview
WITH generation_stats AS (
    SELECT
        manufacturer,
        model_family,
        generation,
        COUNT(*) AS listings,

        ROUND(
            PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price)::numeric,
            2
        ) AS median_price,

        ROUND(
            PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY NULLIF(mileage, 0))::numeric,
            0
        ) AS median_mileage,

        ROUND(
            AVG(price)::numeric,
            2
        ) AS avg_price,

        MIN(year) AS earliest_year,
        MAX(year) AS latest_year

    FROM vehicle_listings

    WHERE generation_quality_flag = 'Mapped'

    GROUP BY
        manufacturer,
        model_family,
        generation
)

SELECT *
FROM generation_stats
WHERE listings >= 20
ORDER BY
    model_family,
    earliest_year;


-- 2. Price change between successive generations
WITH lineage_data AS (
    SELECT
        *,
        CASE
            WHEN model_family LIKE 'Corvette C%'
                THEN 'Corvette'
            ELSE model_family
        END AS analysis_lineage
    FROM vehicle_listings
    WHERE generation_quality_flag = 'Mapped'
),

generation_stats AS (
    SELECT
        manufacturer,
        analysis_lineage,
        generation,
        COUNT(*) AS listings,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price) AS median_price,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY NULLIF(mileage, 0)) AS median_mileage,

        MIN(year) AS earliest_year,
        MAX(year) AS latest_year

    FROM lineage_data

    GROUP BY
        manufacturer,
        analysis_lineage,
        generation
),

qualified_generations AS (
    SELECT *
    FROM generation_stats
    WHERE listings >= 20
),

generation_comparison AS (
    SELECT
        *,

        LAG(generation) OVER (
            PARTITION BY manufacturer, analysis_lineage
            ORDER BY earliest_year, latest_year, generation
        ) AS previous_generation,

        LAG(median_price) OVER (
            PARTITION BY manufacturer, analysis_lineage
            ORDER BY earliest_year, latest_year, generation
        ) AS previous_median_price

    FROM qualified_generations
)

SELECT
    manufacturer,
    analysis_lineage,
    generation,
    previous_generation,
    listings,

    ROUND(median_price::numeric, 2) AS median_price,
    ROUND(previous_median_price::numeric, 2) AS previous_median_price,

    ROUND(
        (median_price - previous_median_price)::numeric,
        2
    ) AS price_change_dollars,

    ROUND(
        (
            (median_price - previous_median_price)
            / NULLIF(previous_median_price, 0)
            * 100
        )::numeric,
        1
    ) AS price_change_pct

FROM generation_comparison

ORDER BY
    analysis_lineage,
    earliest_year;


-- 3. Rank generations by median price within each analytical lineage
WITH lineage_data AS (
    SELECT
        *,
        CASE
            WHEN model_family LIKE 'Corvette C%'
                THEN 'Corvette'
            ELSE model_family
        END AS analysis_lineage
    FROM vehicle_listings
    WHERE generation_quality_flag = 'Mapped'
),

generation_stats AS (
    SELECT
        manufacturer,
        analysis_lineage,
        generation,
        COUNT(*) AS listings,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price) AS median_price,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY NULLIF(mileage, 0)) AS median_mileage

    FROM lineage_data

    GROUP BY
        manufacturer,
        analysis_lineage,
        generation
),

qualified_generations AS (
    SELECT *
    FROM generation_stats
    WHERE listings >= 20
),

ranked_generations AS (
    SELECT
        *,

        RANK() OVER (
            PARTITION BY manufacturer, analysis_lineage
            ORDER BY median_price DESC
        ) AS price_rank

    FROM qualified_generations
)

SELECT
    manufacturer,
    analysis_lineage,
    generation,
    listings,

    ROUND(median_price::numeric, 2) AS median_price,
    ROUND(median_mileage::numeric, 0) AS median_mileage,

    price_rank

FROM ranked_generations

ORDER BY
    analysis_lineage,
    price_rank;

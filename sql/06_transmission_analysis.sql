-- Apex Analytics
-- Transmission market analysis
--
-- Manual vs. automatic comparisons are made only within
-- comparable vehicle groups:
-- same manufacturer
-- same exact model
-- same generation
-- same model year
-- same mileage band


-- 1. Evaluate coverage for manual vs. automatic comparisons
WITH prepared_listings AS (
    SELECT
        source_row_id,
        manufacturer,
        model,
        generation,
        year,
        price,
        transmission_group,

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
      AND transmission_quality_flag <> 'Source inconsistency'
      AND transmission_group IN ('Manual', 'Automatic')
      AND mileage > 0
),

comparison_groups AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        mileage_band,

        COUNT(*) FILTER (
            WHERE transmission_group = 'Manual'
        ) AS manual_count,

        COUNT(*) FILTER (
            WHERE transmission_group = 'Automatic'
        ) AS automatic_count

    FROM prepared_listings

    GROUP BY
        manufacturer,
        model,
        generation,
        year,
        mileage_band

    HAVING
        COUNT(*) FILTER (
            WHERE transmission_group = 'Manual'
        ) > 0

        AND

        COUNT(*) FILTER (
            WHERE transmission_group = 'Automatic'
        ) > 0
)

SELECT
    COUNT(*) AS mixed_transmission_groups,

    SUM(manual_count + automatic_count)
        AS listings_in_mixed_groups,

    COUNT(*) FILTER (
        WHERE manual_count >= 2
          AND automatic_count >= 2
    ) AS groups_with_2_each,

    SUM(manual_count + automatic_count) FILTER (
        WHERE manual_count >= 2
          AND automatic_count >= 2
    ) AS listings_with_2_each,

    COUNT(*) FILTER (
        WHERE manual_count >= 3
          AND automatic_count >= 3
    ) AS groups_with_3_each,

    SUM(manual_count + automatic_count) FILTER (
        WHERE manual_count >= 3
          AND automatic_count >= 3
    ) AS listings_with_3_each,

    COUNT(*) FILTER (
        WHERE manual_count >= 5
          AND automatic_count >= 5
    ) AS groups_with_5_each,

    SUM(manual_count + automatic_count) FILTER (
        WHERE manual_count >= 5
          AND automatic_count >= 5
    ) AS listings_with_5_each

FROM comparison_groups;


-- 2. Manual price premium within comparable peer groups
WITH prepared_listings AS (
    SELECT
        source_row_id,
        manufacturer,
        model,
        generation,
        year,
        price,
        transmission_group,

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
      AND transmission_quality_flag <> 'Source inconsistency'
      AND transmission_group IN ('Manual', 'Automatic')
      AND mileage > 0
),

comparison_groups AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        mileage_band,

        COUNT(*) FILTER (
            WHERE transmission_group = 'Manual'
        ) AS manual_count,

        COUNT(*) FILTER (
            WHERE transmission_group = 'Automatic'
        ) AS automatic_count,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price)
            FILTER (
                WHERE transmission_group = 'Manual'
            ) AS manual_median_price,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price)
            FILTER (
                WHERE transmission_group = 'Automatic'
            ) AS automatic_median_price

    FROM prepared_listings

    GROUP BY
        manufacturer,
        model,
        generation,
        year,
        mileage_band

    HAVING
        COUNT(*) FILTER (
            WHERE transmission_group = 'Manual'
        ) >= 3

        AND

        COUNT(*) FILTER (
            WHERE transmission_group = 'Automatic'
        ) >= 3
)

SELECT
    manufacturer,
    model,
    generation,
    year,
    mileage_band,

    manual_count,
    automatic_count,

    ROUND(
        manual_median_price::numeric,
        2
    ) AS manual_median_price,

    ROUND(
        automatic_median_price::numeric,
        2
    ) AS automatic_median_price,

    ROUND(
        (
            manual_median_price
            - automatic_median_price
        )::numeric,
        2
    ) AS manual_premium_dollars,

    ROUND(
        (
            (
                manual_median_price
                - automatic_median_price
            )
            / NULLIF(automatic_median_price, 0)
            * 100
        )::numeric,
        1
    ) AS manual_premium_pct

FROM comparison_groups

ORDER BY manual_premium_pct DESC;


-- 3. Model-level summary of manual transmission premiums
-- Uses only matched groups with:
-- at least 3 manuals and 3 automatics
-- peer-price dispersion <= 35%

WITH prepared_listings AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        price,
        transmission_group,

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
      AND transmission_quality_flag <> 'Source inconsistency'
      AND transmission_group IN ('Manual', 'Automatic')
      AND mileage > 0
),

comparison_groups AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        mileage_band,

        COUNT(*) FILTER (
            WHERE transmission_group = 'Manual'
        ) AS manual_count,

        COUNT(*) FILTER (
            WHERE transmission_group = 'Automatic'
        ) AS automatic_count,

        PERCENTILE_CONT(0.25)
            WITHIN GROUP (ORDER BY price) AS q1,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price) AS overall_median_price,

        PERCENTILE_CONT(0.75)
            WITHIN GROUP (ORDER BY price) AS q3,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price)
            FILTER (
                WHERE transmission_group = 'Manual'
            ) AS manual_median_price,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price)
            FILTER (
                WHERE transmission_group = 'Automatic'
            ) AS automatic_median_price

    FROM prepared_listings

    GROUP BY
        manufacturer,
        model,
        generation,
        year,
        mileage_band

    HAVING
        COUNT(*) FILTER (
            WHERE transmission_group = 'Manual'
        ) >= 3

        AND

        COUNT(*) FILTER (
            WHERE transmission_group = 'Automatic'
        ) >= 3
),

qualified_groups AS (
    SELECT
        *,

        (
            (manual_median_price - automatic_median_price)
            / NULLIF(automatic_median_price, 0)
            * 100
        ) AS manual_premium_pct

    FROM comparison_groups

    WHERE
        (
            (q3 - q1)
            / NULLIF(overall_median_price, 0)
            * 100
        ) <= 35
)

SELECT
    manufacturer,
    model,
    generation,

    COUNT(*) AS matched_peer_groups,

    SUM(manual_count) AS manual_listings,
    SUM(automatic_count) AS automatic_listings,

    ROUND(
        PERCENTILE_CONT(0.5)
        WITHIN GROUP (
            ORDER BY manual_premium_pct
        )::numeric,
        1
    ) AS median_manual_premium_pct,

    COUNT(*) FILTER (
        WHERE manual_premium_pct > 0
    ) AS groups_with_manual_premium,

    COUNT(*) FILTER (
        WHERE manual_premium_pct < 0
    ) AS groups_with_manual_discount

FROM qualified_groups

GROUP BY
    manufacturer,
    model,
    generation

HAVING COUNT(*) >= 3

ORDER BY median_manual_premium_pct DESC;

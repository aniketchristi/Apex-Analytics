-- Apex Analytics
-- Vehicle history and ownership analysis

-- 1. Evaluate coverage for accident-history comparisons
WITH prepared_listings AS (
    SELECT
        source_row_id,
        manufacturer,
        model,
        generation,
        year,
        price,
        accident_history,

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
      AND mileage > 0
      AND accident_history IN (
          'Accident/Damage Reported',
          'No Accident/Damage Reported'
      )
),

comparison_groups AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        mileage_band,

        COUNT(*) FILTER (
            WHERE accident_history = 'Accident/Damage Reported'
        ) AS accident_count,

        COUNT(*) FILTER (
            WHERE accident_history = 'No Accident/Damage Reported'
        ) AS clean_count

    FROM prepared_listings

    GROUP BY
        manufacturer,
        model,
        generation,
        year,
        mileage_band

    HAVING
        COUNT(*) FILTER (
            WHERE accident_history = 'Accident/Damage Reported'
        ) > 0
        AND
        COUNT(*) FILTER (
            WHERE accident_history = 'No Accident/Damage Reported'
        ) > 0
)

SELECT
    COUNT(*) AS mixed_history_groups,

    SUM(accident_count + clean_count)
        AS listings_in_mixed_groups,

    COUNT(*) FILTER (
        WHERE accident_count >= 2
          AND clean_count >= 2
    ) AS groups_with_2_each,

    SUM(accident_count + clean_count) FILTER (
        WHERE accident_count >= 2
          AND clean_count >= 2
    ) AS listings_with_2_each,

    COUNT(*) FILTER (
        WHERE accident_count >= 3
          AND clean_count >= 3
    ) AS groups_with_3_each,

    SUM(accident_count + clean_count) FILTER (
        WHERE accident_count >= 3
          AND clean_count >= 3
    ) AS listings_with_3_each,

    COUNT(*) FILTER (
        WHERE accident_count >= 5
          AND clean_count >= 5
    ) AS groups_with_5_each,

    SUM(accident_count + clean_count) FILTER (
        WHERE accident_count >= 5
          AND clean_count >= 5
    ) AS listings_with_5_each

FROM comparison_groups;


-- 2. Accident-history price effect within comparable vehicles
-- Requires at least 3 accident-history and 3 clean-history
-- listings per group, plus peer-price dispersion <= 35%.

WITH prepared_listings AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        price,
        accident_history,

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
      AND mileage > 0
      AND accident_history IN (
          'Accident/Damage Reported',
          'No Accident/Damage Reported'
      )
),

comparison_groups AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        mileage_band,

        COUNT(*) FILTER (
            WHERE accident_history = 'Accident/Damage Reported'
        ) AS accident_count,

        COUNT(*) FILTER (
            WHERE accident_history = 'No Accident/Damage Reported'
        ) AS clean_count,

        PERCENTILE_CONT(0.25)
            WITHIN GROUP (ORDER BY price) AS q1,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price) AS overall_median_price,

        PERCENTILE_CONT(0.75)
            WITHIN GROUP (ORDER BY price) AS q3,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price)
            FILTER (
                WHERE accident_history = 'Accident/Damage Reported'
            ) AS accident_median_price,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price)
            FILTER (
                WHERE accident_history = 'No Accident/Damage Reported'
            ) AS clean_median_price

    FROM prepared_listings

    GROUP BY
        manufacturer,
        model,
        generation,
        year,
        mileage_band

    HAVING
        COUNT(*) FILTER (
            WHERE accident_history = 'Accident/Damage Reported'
        ) >= 3

        AND

        COUNT(*) FILTER (
            WHERE accident_history = 'No Accident/Damage Reported'
        ) >= 3
),

qualified_groups AS (
    SELECT
        *,

        (
            (q3 - q1)
            / NULLIF(overall_median_price, 0)
            * 100
        ) AS peer_dispersion_pct,

        (
            (accident_median_price - clean_median_price)
            / NULLIF(clean_median_price, 0)
            * 100
        ) AS accident_price_effect_pct

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
    year,
    mileage_band,

    accident_count,
    clean_count,

    ROUND(
        accident_median_price::numeric,
        2
    ) AS accident_median_price,

    ROUND(
        clean_median_price::numeric,
        2
    ) AS clean_median_price,

    ROUND(
        (
            accident_median_price
            - clean_median_price
        )::numeric,
        2
    ) AS accident_price_difference,

    ROUND(
        accident_price_effect_pct::numeric,
        1
    ) AS accident_price_effect_pct,

    ROUND(
        peer_dispersion_pct::numeric,
        1
    ) AS peer_dispersion_pct

FROM qualified_groups

ORDER BY accident_price_effect_pct ASC;


-- 3. Model-level summary of accident-history price effects
WITH prepared_listings AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        price,
        accident_history,

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
      AND mileage > 0
      AND accident_history IN (
          'Accident/Damage Reported',
          'No Accident/Damage Reported'
      )
),

comparison_groups AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        mileage_band,

        COUNT(*) FILTER (
            WHERE accident_history = 'Accident/Damage Reported'
        ) AS accident_count,

        COUNT(*) FILTER (
            WHERE accident_history = 'No Accident/Damage Reported'
        ) AS clean_count,

        PERCENTILE_CONT(0.25)
            WITHIN GROUP (ORDER BY price) AS q1,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price) AS overall_median_price,

        PERCENTILE_CONT(0.75)
            WITHIN GROUP (ORDER BY price) AS q3,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price)
            FILTER (
                WHERE accident_history = 'Accident/Damage Reported'
            ) AS accident_median_price,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price)
            FILTER (
                WHERE accident_history = 'No Accident/Damage Reported'
            ) AS clean_median_price

    FROM prepared_listings

    GROUP BY
        manufacturer,
        model,
        generation,
        year,
        mileage_band

    HAVING
        COUNT(*) FILTER (
            WHERE accident_history = 'Accident/Damage Reported'
        ) >= 3
        AND
        COUNT(*) FILTER (
            WHERE accident_history = 'No Accident/Damage Reported'
        ) >= 3
),

qualified_groups AS (
    SELECT
        *,

        (
            (accident_median_price - clean_median_price)
            / NULLIF(clean_median_price, 0)
            * 100
        ) AS accident_price_effect_pct

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

    SUM(accident_count) AS accident_history_listings,
    SUM(clean_count) AS clean_history_listings,

    ROUND(
        PERCENTILE_CONT(0.5)
        WITHIN GROUP (
            ORDER BY accident_price_effect_pct
        )::numeric,
        1
    ) AS median_accident_price_effect_pct,

    COUNT(*) FILTER (
        WHERE accident_price_effect_pct < 0
    ) AS groups_with_accident_discount,

    COUNT(*) FILTER (
        WHERE accident_price_effect_pct > 0
    ) AS groups_with_accident_premium

FROM qualified_groups

GROUP BY
    manufacturer,
    model,
    generation

HAVING COUNT(*) >= 3

ORDER BY median_accident_price_effect_pct ASC;


-- 4. Evaluate coverage for one-owner comparisons
WITH prepared_listings AS (
    SELECT
        source_row_id,
        manufacturer,
        model,
        generation,
        year,
        price,
        one_owner_status,

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
      AND mileage > 0
      AND one_owner_status IN (
          'One Owner',
          'Not One Owner'
      )
),

comparison_groups AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        mileage_band,

        COUNT(*) FILTER (
            WHERE one_owner_status = 'One Owner'
        ) AS one_owner_count,

        COUNT(*) FILTER (
            WHERE one_owner_status = 'Not One Owner'
        ) AS multiple_owner_count

    FROM prepared_listings

    GROUP BY
        manufacturer,
        model,
        generation,
        year,
        mileage_band

    HAVING
        COUNT(*) FILTER (
            WHERE one_owner_status = 'One Owner'
        ) > 0
        AND
        COUNT(*) FILTER (
            WHERE one_owner_status = 'Not One Owner'
        ) > 0
)

SELECT
    COUNT(*) AS mixed_owner_groups,

    SUM(one_owner_count + multiple_owner_count)
        AS listings_in_mixed_groups,

    COUNT(*) FILTER (
        WHERE one_owner_count >= 2
          AND multiple_owner_count >= 2
    ) AS groups_with_2_each,

    SUM(one_owner_count + multiple_owner_count) FILTER (
        WHERE one_owner_count >= 2
          AND multiple_owner_count >= 2
    ) AS listings_with_2_each,

    COUNT(*) FILTER (
        WHERE one_owner_count >= 3
          AND multiple_owner_count >= 3
    ) AS groups_with_3_each,

    SUM(one_owner_count + multiple_owner_count) FILTER (
        WHERE one_owner_count >= 3
          AND multiple_owner_count >= 3
    ) AS listings_with_3_each,

    COUNT(*) FILTER (
        WHERE one_owner_count >= 5
          AND multiple_owner_count >= 5
    ) AS groups_with_5_each,

    SUM(one_owner_count + multiple_owner_count) FILTER (
        WHERE one_owner_count >= 5
          AND multiple_owner_count >= 5
    ) AS listings_with_5_each

FROM comparison_groups;


-- 5. One-owner price effect within comparable vehicles
-- Requires at least 3 one-owner and 3 multiple-owner
-- listings per group, plus peer-price dispersion <= 35%.

WITH prepared_listings AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        price,
        one_owner_status,

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
      AND mileage > 0
      AND one_owner_status IN (
          'One Owner',
          'Not One Owner'
      )
),

comparison_groups AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        mileage_band,

        COUNT(*) FILTER (
            WHERE one_owner_status = 'One Owner'
        ) AS one_owner_count,

        COUNT(*) FILTER (
            WHERE one_owner_status = 'Not One Owner'
        ) AS multiple_owner_count,

        PERCENTILE_CONT(0.25)
            WITHIN GROUP (ORDER BY price) AS q1,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price) AS overall_median_price,

        PERCENTILE_CONT(0.75)
            WITHIN GROUP (ORDER BY price) AS q3,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price)
            FILTER (
                WHERE one_owner_status = 'One Owner'
            ) AS one_owner_median_price,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price)
            FILTER (
                WHERE one_owner_status = 'Not One Owner'
            ) AS multiple_owner_median_price

    FROM prepared_listings

    GROUP BY
        manufacturer,
        model,
        generation,
        year,
        mileage_band

    HAVING
        COUNT(*) FILTER (
            WHERE one_owner_status = 'One Owner'
        ) >= 3

        AND

        COUNT(*) FILTER (
            WHERE one_owner_status = 'Not One Owner'
        ) >= 3
),

qualified_groups AS (
    SELECT
        *,

        (
            (q3 - q1)
            / NULLIF(overall_median_price, 0)
            * 100
        ) AS peer_dispersion_pct,

        (
            (one_owner_median_price - multiple_owner_median_price)
            / NULLIF(multiple_owner_median_price, 0)
            * 100
        ) AS one_owner_price_effect_pct

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
    year,
    mileage_band,

    one_owner_count,
    multiple_owner_count,

    ROUND(
        one_owner_median_price::numeric,
        2
    ) AS one_owner_median_price,

    ROUND(
        multiple_owner_median_price::numeric,
        2
    ) AS multiple_owner_median_price,

    ROUND(
        (
            one_owner_median_price
            - multiple_owner_median_price
        )::numeric,
        2
    ) AS one_owner_price_difference,

    ROUND(
        one_owner_price_effect_pct::numeric,
        1
    ) AS one_owner_price_effect_pct,

    ROUND(
        peer_dispersion_pct::numeric,
        1
    ) AS peer_dispersion_pct

FROM qualified_groups

ORDER BY one_owner_price_effect_pct DESC;


-- 6. Overall summary of one-owner price effects
WITH prepared_listings AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        price,
        one_owner_status,

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
      AND mileage > 0
      AND one_owner_status IN (
          'One Owner',
          'Not One Owner'
      )
),

comparison_groups AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        mileage_band,

        COUNT(*) FILTER (
            WHERE one_owner_status = 'One Owner'
        ) AS one_owner_count,

        COUNT(*) FILTER (
            WHERE one_owner_status = 'Not One Owner'
        ) AS multiple_owner_count,

        PERCENTILE_CONT(0.25)
            WITHIN GROUP (ORDER BY price) AS q1,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price) AS overall_median_price,

        PERCENTILE_CONT(0.75)
            WITHIN GROUP (ORDER BY price) AS q3,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price)
            FILTER (
                WHERE one_owner_status = 'One Owner'
            ) AS one_owner_median_price,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price)
            FILTER (
                WHERE one_owner_status = 'Not One Owner'
            ) AS multiple_owner_median_price

    FROM prepared_listings

    GROUP BY
        manufacturer,
        model,
        generation,
        year,
        mileage_band

    HAVING
        COUNT(*) FILTER (
            WHERE one_owner_status = 'One Owner'
        ) >= 3
        AND
        COUNT(*) FILTER (
            WHERE one_owner_status = 'Not One Owner'
        ) >= 3
),

qualified_groups AS (
    SELECT
        *,

        (
            (one_owner_median_price - multiple_owner_median_price)
            / NULLIF(multiple_owner_median_price, 0)
            * 100
        ) AS one_owner_price_effect_pct

    FROM comparison_groups

    WHERE
        (
            (q3 - q1)
            / NULLIF(overall_median_price, 0)
            * 100
        ) <= 35
)

SELECT
    COUNT(*) AS qualified_groups,

    SUM(one_owner_count + multiple_owner_count)
        AS qualified_listings,

    ROUND(
        PERCENTILE_CONT(0.5)
        WITHIN GROUP (
            ORDER BY one_owner_price_effect_pct
        )::numeric,
        1
    ) AS median_one_owner_effect_pct,

    COUNT(*) FILTER (
        WHERE one_owner_price_effect_pct > 0
    ) AS groups_with_one_owner_premium,

    COUNT(*) FILTER (
        WHERE one_owner_price_effect_pct < 0
    ) AS groups_with_one_owner_discount,

    ROUND(
        100.0 *
        COUNT(*) FILTER (
            WHERE one_owner_price_effect_pct > 0
        )
        / COUNT(*),
        1
    ) AS pct_groups_with_premium

FROM qualified_groups;


-- 7. Evaluate coverage for personal-use comparisons
WITH prepared_listings AS (
    SELECT
        source_row_id,
        manufacturer,
        model,
        generation,
        year,
        price,
        personal_use_status,

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
      AND mileage > 0
      AND personal_use_status IN (
          'Personal Use Only',
          'Not Personal Use Only'
      )
),

comparison_groups AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        mileage_band,

        COUNT(*) FILTER (
            WHERE personal_use_status = 'Personal Use Only'
        ) AS personal_use_count,

        COUNT(*) FILTER (
            WHERE personal_use_status = 'Not Personal Use Only'
        ) AS non_personal_use_count

    FROM prepared_listings

    GROUP BY
        manufacturer,
        model,
        generation,
        year,
        mileage_band

    HAVING
        COUNT(*) FILTER (
            WHERE personal_use_status = 'Personal Use Only'
        ) > 0
        AND
        COUNT(*) FILTER (
            WHERE personal_use_status = 'Not Personal Use Only'
        ) > 0
)

SELECT
    COUNT(*) AS mixed_personal_use_groups,

    SUM(personal_use_count + non_personal_use_count)
        AS listings_in_mixed_groups,

    COUNT(*) FILTER (
        WHERE personal_use_count >= 2
          AND non_personal_use_count >= 2
    ) AS groups_with_2_each,

    SUM(personal_use_count + non_personal_use_count) FILTER (
        WHERE personal_use_count >= 2
          AND non_personal_use_count >= 2
    ) AS listings_with_2_each,

    COUNT(*) FILTER (
        WHERE personal_use_count >= 3
          AND non_personal_use_count >= 3
    ) AS groups_with_3_each,

    SUM(personal_use_count + non_personal_use_count) FILTER (
        WHERE personal_use_count >= 3
          AND non_personal_use_count >= 3
    ) AS listings_with_3_each,

    COUNT(*) FILTER (
        WHERE personal_use_count >= 5
          AND non_personal_use_count >= 5
    ) AS groups_with_5_each,

    SUM(personal_use_count + non_personal_use_count) FILTER (
        WHERE personal_use_count >= 5
          AND non_personal_use_count >= 5
    ) AS listings_with_5_each

FROM comparison_groups;


-- 8. Personal-use price effect within comparable vehicles
-- Requires at least 3 personal-use and 3 non-personal-use
-- listings per group, plus peer-price dispersion <= 35%.

WITH prepared_listings AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        price,
        personal_use_status,

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
      AND mileage > 0
      AND personal_use_status IN (
          'Personal Use Only',
          'Not Personal Use Only'
      )
),

comparison_groups AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        mileage_band,

        COUNT(*) FILTER (
            WHERE personal_use_status = 'Personal Use Only'
        ) AS personal_use_count,

        COUNT(*) FILTER (
            WHERE personal_use_status = 'Not Personal Use Only'
        ) AS non_personal_use_count,

        PERCENTILE_CONT(0.25)
            WITHIN GROUP (ORDER BY price) AS q1,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price) AS overall_median_price,

        PERCENTILE_CONT(0.75)
            WITHIN GROUP (ORDER BY price) AS q3,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price)
            FILTER (
                WHERE personal_use_status = 'Personal Use Only'
            ) AS personal_use_median_price,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price)
            FILTER (
                WHERE personal_use_status = 'Not Personal Use Only'
            ) AS non_personal_use_median_price

    FROM prepared_listings

    GROUP BY
        manufacturer,
        model,
        generation,
        year,
        mileage_band

    HAVING
        COUNT(*) FILTER (
            WHERE personal_use_status = 'Personal Use Only'
        ) >= 3

        AND

        COUNT(*) FILTER (
            WHERE personal_use_status = 'Not Personal Use Only'
        ) >= 3
),

qualified_groups AS (
    SELECT
        *,

        (
            (q3 - q1)
            / NULLIF(overall_median_price, 0)
            * 100
        ) AS peer_dispersion_pct,

        (
            (personal_use_median_price - non_personal_use_median_price)
            / NULLIF(non_personal_use_median_price, 0)
            * 100
        ) AS personal_use_price_effect_pct

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
    year,
    mileage_band,

    personal_use_count,
    non_personal_use_count,

    ROUND(
        personal_use_median_price::numeric,
        2
    ) AS personal_use_median_price,

    ROUND(
        non_personal_use_median_price::numeric,
        2
    ) AS non_personal_use_median_price,

    ROUND(
        (
            personal_use_median_price
            - non_personal_use_median_price
        )::numeric,
        2
    ) AS personal_use_price_difference,

    ROUND(
        personal_use_price_effect_pct::numeric,
        1
    ) AS personal_use_price_effect_pct,

    ROUND(
        peer_dispersion_pct::numeric,
        1
    ) AS peer_dispersion_pct

FROM qualified_groups

ORDER BY personal_use_price_effect_pct DESC;


-- 9. Overall summary of personal-use price effects
WITH prepared_listings AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        price,
        personal_use_status,

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
      AND mileage > 0
      AND personal_use_status IN (
          'Personal Use Only',
          'Not Personal Use Only'
      )
),

comparison_groups AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        mileage_band,

        COUNT(*) FILTER (
            WHERE personal_use_status = 'Personal Use Only'
        ) AS personal_use_count,

        COUNT(*) FILTER (
            WHERE personal_use_status = 'Not Personal Use Only'
        ) AS non_personal_use_count,

        PERCENTILE_CONT(0.25)
            WITHIN GROUP (ORDER BY price) AS q1,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price) AS overall_median_price,

        PERCENTILE_CONT(0.75)
            WITHIN GROUP (ORDER BY price) AS q3,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price)
            FILTER (
                WHERE personal_use_status = 'Personal Use Only'
            ) AS personal_use_median_price,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price)
            FILTER (
                WHERE personal_use_status = 'Not Personal Use Only'
            ) AS non_personal_use_median_price

    FROM prepared_listings

    GROUP BY
        manufacturer,
        model,
        generation,
        year,
        mileage_band

    HAVING
        COUNT(*) FILTER (
            WHERE personal_use_status = 'Personal Use Only'
        ) >= 3
        AND
        COUNT(*) FILTER (
            WHERE personal_use_status = 'Not Personal Use Only'
        ) >= 3
),

qualified_groups AS (
    SELECT
        *,

        (
            (personal_use_median_price - non_personal_use_median_price)
            / NULLIF(non_personal_use_median_price, 0)
            * 100
        ) AS personal_use_price_effect_pct

    FROM comparison_groups

    WHERE
        (
            (q3 - q1)
            / NULLIF(overall_median_price, 0)
            * 100
        ) <= 35
)

SELECT
    COUNT(*) AS qualified_groups,

    SUM(personal_use_count + non_personal_use_count)
        AS qualified_listings,

    ROUND(
        PERCENTILE_CONT(0.5)
        WITHIN GROUP (
            ORDER BY personal_use_price_effect_pct
        )::numeric,
        1
    ) AS median_personal_use_effect_pct,

    COUNT(*) FILTER (
        WHERE personal_use_price_effect_pct > 0
    ) AS groups_with_personal_use_premium,

    COUNT(*) FILTER (
        WHERE personal_use_price_effect_pct < 0
    ) AS groups_with_personal_use_discount,

    ROUND(
        100.0 *
        COUNT(*) FILTER (
            WHERE personal_use_price_effect_pct > 0
        )
        / COUNT(*),
        1
    ) AS pct_groups_with_premium

FROM qualified_groups;

-- Apex Analytics
-- Peer-based enthusiast vehicle value analysis
--
-- Comparable peers are defined as:
-- same manufacturer
-- same exact model
-- same generation
-- same model year
-- same mileage band
--
-- Peer groups require at least 5 listings.


-- 1. Peer-group coverage
WITH prepared_listings AS (
    SELECT
        source_row_id,
        manufacturer,
        model,
        generation,
        year,
        price,
        NULLIF(mileage, 0) AS analysis_mileage,

        CASE
            WHEN mileage > 0 AND mileage < 10000
                THEN '00-09k'
            WHEN mileage >= 10000 AND mileage < 25000
                THEN '10-24k'
            WHEN mileage >= 25000 AND mileage < 50000
                THEN '25-49k'
            WHEN mileage >= 50000 AND mileage < 75000
                THEN '50-74k'
            WHEN mileage >= 75000 AND mileage < 100000
                THEN '75-99k'
            WHEN mileage >= 100000
                THEN '100k+'
            ELSE NULL
        END AS mileage_band

    FROM vehicle_listings

    WHERE generation_quality_flag = 'Mapped'
),

peer_groups AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        mileage_band,
        COUNT(*) AS listings

    FROM prepared_listings

    WHERE analysis_mileage IS NOT NULL

    GROUP BY
        manufacturer,
        model,
        generation,
        year,
        mileage_band
)

SELECT
    COUNT(*) AS peer_groups,
    SUM(listings) AS usable_listings,

    COUNT(*) FILTER (
        WHERE listings >= 5
    ) AS qualified_peer_groups,

    SUM(listings) FILTER (
        WHERE listings >= 5
    ) AS qualified_listings,

    ROUND(
        100.0 *
        SUM(listings) FILTER (WHERE listings >= 5)
        / SUM(listings),
        1
    ) AS qualified_coverage_pct

FROM peer_groups;


-- 2. Price position relative to comparable peers
WITH prepared_listings AS (
    SELECT
        source_row_id,
        manufacturer,
        model,
        model_family,
        generation,
        year,
        price,
        NULLIF(mileage, 0) AS analysis_mileage,

        accident_history,
        one_owner_status,
        personal_use_status,
        transmission_group,
        transmission_quality_flag,
        drivetrain_quality_flag,

        CASE
            WHEN mileage > 0 AND mileage < 10000
                THEN '00-09k'
            WHEN mileage >= 10000 AND mileage < 25000
                THEN '10-24k'
            WHEN mileage >= 25000 AND mileage < 50000
                THEN '25-49k'
            WHEN mileage >= 50000 AND mileage < 75000
                THEN '50-74k'
            WHEN mileage >= 75000 AND mileage < 100000
                THEN '75-99k'
            WHEN mileage >= 100000
                THEN '100k+'
            ELSE NULL
        END AS mileage_band

    FROM vehicle_listings

    WHERE generation_quality_flag = 'Mapped'
),

peer_groups AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        mileage_band,

        COUNT(*) AS peer_count,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price) AS peer_median_price

    FROM prepared_listings

    WHERE analysis_mileage IS NOT NULL

    GROUP BY
        manufacturer,
        model,
        generation,
        year,
        mileage_band

    HAVING COUNT(*) >= 5
),

listing_value AS (
    SELECT
        p.*,
        g.peer_count,
        g.peer_median_price,

        p.price - g.peer_median_price
            AS price_vs_peer_dollars,

        (
            (p.price - g.peer_median_price)
            / NULLIF(g.peer_median_price, 0)
            * 100
        ) AS price_vs_peer_pct

    FROM prepared_listings p

    JOIN peer_groups g
        ON p.manufacturer = g.manufacturer
        AND p.model = g.model
        AND p.generation = g.generation
        AND p.year = g.year
        AND p.mileage_band = g.mileage_band
)

SELECT
    source_row_id,
    manufacturer,
    model,
    generation,
    year,

    ROUND(analysis_mileage::numeric, 0) AS mileage,
    mileage_band,
    peer_count,

    ROUND(price::numeric, 2) AS price,
    ROUND(peer_median_price::numeric, 2) AS peer_median_price,

    ROUND(
        price_vs_peer_dollars::numeric,
        2
    ) AS price_vs_peer_dollars,

    ROUND(
        price_vs_peer_pct::numeric,
        1
    ) AS price_vs_peer_pct,

    accident_history,
    one_owner_status,
    transmission_group

FROM listing_value

ORDER BY price_vs_peer_pct ASC

LIMIT 30;


-- 3. Rank plausible value opportunities after quality safeguards
WITH prepared_listings AS (
    SELECT
        source_row_id,
        manufacturer,
        model,
        model_family,
        generation,
        year,
        price,
        NULLIF(mileage, 0) AS analysis_mileage,

        accident_history,
        one_owner_status,
        personal_use_status,

        transmission_group,
        transmission_quality_flag,
        drivetrain_quality_flag,

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
),

peer_stats AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        mileage_band,

        COUNT(*) AS peer_count,

        PERCENTILE_CONT(0.25)
            WITHIN GROUP (ORDER BY price) AS q1,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price) AS peer_median_price,

        PERCENTILE_CONT(0.75)
            WITHIN GROUP (ORDER BY price) AS q3

    FROM prepared_listings

    WHERE analysis_mileage IS NOT NULL

    GROUP BY
        manufacturer,
        model,
        generation,
        year,
        mileage_band

    HAVING COUNT(*) >= 5
),

scored_listings AS (
    SELECT
        p.*,
        s.peer_count,
        s.peer_median_price,

        s.q1 - 1.5 * (s.q3 - s.q1) AS lower_bound,
        s.q3 + 1.5 * (s.q3 - s.q1) AS upper_bound,

        p.price - s.peer_median_price
            AS price_vs_peer_dollars,

        (
            (p.price - s.peer_median_price)
            / NULLIF(s.peer_median_price, 0)
            * 100
        ) AS price_vs_peer_pct

    FROM prepared_listings p

    JOIN peer_stats s
        ON p.manufacturer = s.manufacturer
        AND p.model = s.model
        AND p.generation = s.generation
        AND p.year = s.year
        AND p.mileage_band = s.mileage_band
)

SELECT
    source_row_id,
    manufacturer,
    model,
    generation,
    year,

    ROUND(analysis_mileage::numeric, 0) AS mileage,
    mileage_band,
    peer_count,

    ROUND(price::numeric, 2) AS price,
    ROUND(peer_median_price::numeric, 2) AS peer_median_price,

    ROUND(price_vs_peer_dollars::numeric, 2)
        AS price_vs_peer_dollars,

    ROUND(price_vs_peer_pct::numeric, 1)
        AS price_vs_peer_pct,

    accident_history,
    one_owner_status,
    transmission_group

FROM scored_listings

WHERE price BETWEEN lower_bound AND upper_bound

  AND accident_history = 'No Accident/Damage Reported'

  AND transmission_quality_flag <> 'Source inconsistency'

  AND drivetrain_quality_flag <> 'Source inconsistency'

  AND price_vs_peer_pct < 0

ORDER BY price_vs_peer_pct ASC

LIMIT 30;


-- 4. Final peer-adjusted value candidates
-- Excludes heterogeneous peer groups where
-- IQR exceeds 35% of the peer median.

WITH prepared_listings AS (
    SELECT
        source_row_id,
        manufacturer,
        model,
        model_family,
        generation,
        year,
        price,
        NULLIF(mileage, 0) AS analysis_mileage,

        accident_history,
        one_owner_status,
        personal_use_status,

        transmission_group,
        transmission_quality_flag,
        drivetrain_quality_flag,

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
),

peer_stats AS (
    SELECT
        manufacturer,
        model,
        generation,
        year,
        mileage_band,

        COUNT(*) AS peer_count,

        PERCENTILE_CONT(0.25)
            WITHIN GROUP (ORDER BY price) AS q1,

        PERCENTILE_CONT(0.5)
            WITHIN GROUP (ORDER BY price) AS peer_median_price,

        PERCENTILE_CONT(0.75)
            WITHIN GROUP (ORDER BY price) AS q3

    FROM prepared_listings

    WHERE analysis_mileage IS NOT NULL

    GROUP BY
        manufacturer,
        model,
        generation,
        year,
        mileage_band

    HAVING COUNT(*) >= 5
),

qualified_peer_stats AS (
    SELECT
        *,

        (
            (q3 - q1)
            / NULLIF(peer_median_price, 0)
            * 100
        ) AS peer_dispersion_pct

    FROM peer_stats

    WHERE
        (
            (q3 - q1)
            / NULLIF(peer_median_price, 0)
            * 100
        ) <= 35
),

scored_listings AS (
    SELECT
        p.*,

        s.peer_count,
        s.peer_median_price,
        s.peer_dispersion_pct,

        s.q1 - 1.5 * (s.q3 - s.q1)
            AS lower_bound,

        s.q3 + 1.5 * (s.q3 - s.q1)
            AS upper_bound,

        p.price - s.peer_median_price
            AS price_vs_peer_dollars,

        (
            (p.price - s.peer_median_price)
            / NULLIF(s.peer_median_price, 0)
            * 100
        ) AS price_vs_peer_pct

    FROM prepared_listings p

    JOIN qualified_peer_stats s
        ON p.manufacturer = s.manufacturer
        AND p.model = s.model
        AND p.generation = s.generation
        AND p.year = s.year
        AND p.mileage_band = s.mileage_band
)

SELECT
    source_row_id,
    manufacturer,
    model,
    generation,
    year,

    ROUND(analysis_mileage::numeric, 0) AS mileage,
    mileage_band,
    peer_count,

    ROUND(peer_dispersion_pct::numeric, 1)
        AS peer_dispersion_pct,

    ROUND(price::numeric, 2) AS price,

    ROUND(peer_median_price::numeric, 2)
        AS peer_median_price,

    ROUND(price_vs_peer_dollars::numeric, 2)
        AS price_vs_peer_dollars,

    ROUND(price_vs_peer_pct::numeric, 1)
        AS price_vs_peer_pct,

    accident_history,
    one_owner_status,
    personal_use_status,
    transmission_group

FROM scored_listings

WHERE price BETWEEN lower_bound AND upper_bound

  AND accident_history = 'No Accident/Damage Reported'

  AND transmission_quality_flag <> 'Source inconsistency'

  AND drivetrain_quality_flag <> 'Source inconsistency'

  AND price_vs_peer_pct < 0

ORDER BY price_vs_peer_pct ASC

LIMIT 30;

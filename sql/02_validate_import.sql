-- Apex Analytics
-- PostgreSQL import validation

SELECT
    COUNT(*) AS total_rows,
    COUNT(DISTINCT source_row_id) AS unique_source_rows,
    COUNT(DISTINCT manufacturer) AS manufacturers,
    COUNT(DISTINCT model_family) AS model_families,
    COUNT(DISTINCT generation) AS generations
FROM vehicle_listings;


SELECT
    COUNT(*) FILTER (
        WHERE mileage IS NULL
    ) AS missing_mileage,

    COUNT(*) FILTER (
        WHERE generation_quality_flag = 'Transition / Ambiguous'
    ) AS ambiguous_generation,

    COUNT(*) FILTER (
        WHERE transmission_quality_flag = 'Source inconsistency'
    ) AS transmission_source_inconsistency,

    COUNT(*) FILTER (
        WHERE drivetrain_quality_flag = 'Source inconsistency'
    ) AS drivetrain_source_inconsistency,

    COUNT(*) FILTER (
        WHERE model_family = 'Corvette C8'
          AND transmission_group = 'Manual'
    ) AS c8_manual_rows
FROM vehicle_listings;


SELECT
    manufacturer,
    COUNT(*) AS listings
FROM vehicle_listings
GROUP BY manufacturer
ORDER BY listings DESC;

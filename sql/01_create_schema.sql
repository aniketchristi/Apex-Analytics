DROP TABLE IF EXISTS vehicle_listings;

CREATE TABLE vehicle_listings (
    source_row_id BIGINT PRIMARY KEY,
    project_scope TEXT NOT NULL,

    manufacturer TEXT NOT NULL,
    model TEXT NOT NULL,
    model_family TEXT NOT NULL,
    generation TEXT NOT NULL,
    generation_quality_flag TEXT NOT NULL,
    year INTEGER NOT NULL,

    price DOUBLE PRECISION NOT NULL,
    price_drop DOUBLE PRECISION,
    mileage DOUBLE PRECISION,
    mileage_quality_flag TEXT NOT NULL,

    transmission TEXT,
    transmission_type TEXT NOT NULL,
    transmission_group TEXT NOT NULL,
    transmission_quality_flag TEXT NOT NULL,

    drivetrain TEXT,
    drivetrain_group TEXT NOT NULL,
    drivetrain_quality_flag TEXT NOT NULL,

    engine TEXT,
    engine_displacement_l DOUBLE PRECISION,
    engine_cylinders DOUBLE PRECISION,

    fuel_type TEXT,
    fuel_group TEXT NOT NULL,
    fuel_quality_flag TEXT NOT NULL,

    mpg TEXT,
    city_mpg DOUBLE PRECISION,
    highway_mpg DOUBLE PRECISION,
    combined_mpg_simple DOUBLE PRECISION,

    accidents_or_damage DOUBLE PRECISION,
    accident_history TEXT NOT NULL,

    one_owner DOUBLE PRECISION,
    one_owner_status TEXT NOT NULL,

    personal_use_only DOUBLE PRECISION,
    personal_use_status TEXT NOT NULL,

    exterior_color TEXT,
    interior_color TEXT,

    seller_rating DOUBLE PRECISION,
    driver_rating DOUBLE PRECISION,
    driver_reviews_num DOUBLE PRECISION,

    CONSTRAINT valid_project_scope
        CHECK (project_scope IN ('Core', 'Supporting')),

    CONSTRAINT positive_price
        CHECK (price > 0),

    CONSTRAINT nonnegative_mileage
        CHECK (mileage IS NULL OR mileage >= 0)
);

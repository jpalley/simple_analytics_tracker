-- Create databases
CREATE DATABASE simple_analytics_tracker_production;
CREATE DATABASE simple_analytics_tracker_production_cache;
CREATE DATABASE simple_analytics_tracker_production_queue;
CREATE DATABASE simple_analytics_tracker_production_cable;

-- Grant privileges
GRANT ALL PRIVILEGES ON DATABASE simple_analytics_tracker_production TO postgres;
GRANT ALL PRIVILEGES ON DATABASE simple_analytics_tracker_production_cache TO postgres;
GRANT ALL PRIVILEGES ON DATABASE simple_analytics_tracker_production_queue TO postgres;
GRANT ALL PRIVILEGES ON DATABASE simple_analytics_tracker_production_cable TO postgres; 
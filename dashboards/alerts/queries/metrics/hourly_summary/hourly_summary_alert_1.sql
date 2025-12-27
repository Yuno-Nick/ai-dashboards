-- ==============================================================================
-- HOURLY SUMMARY ALERT 1: Volume (Historical - Last 7 days by hour)
-- ==============================================================================
-- Metric: total_calls | Direction: LOWER is bad
-- ==============================================================================

WITH hourly_metrics AS (
    SELECT created_hour AS eval_hour, created_date AS eval_date, EXTRACT(HOUR FROM created_hour) AS hour_of_day, DAYOFWEEK(created_date) AS day_of_week,
        organization_code, organization_name, country, COUNT(*) AS total_calls
    FROM ai_calls_detail
    WHERE created_date >= CURRENT_DATE() - INTERVAL 14 DAY AND created_hour < DATE_TRUNC('hour', CURRENT_TIMESTAMP())
        [[AND {{organization_name}}]]
        [[AND {{country}}]]
    GROUP BY created_hour, created_date, organization_code, organization_name, country
),

display_metrics AS (SELECT * FROM hourly_metrics WHERE eval_date >= CURRENT_DATE() - INTERVAL 7 DAY),

stddev_all_days AS (
    SELECT organization_code, country, hour_of_day, COUNT(DISTINCT eval_date) AS sample_size, ROUND(STDDEV(total_calls), 2) AS stddev_value
    FROM hourly_metrics WHERE eval_date < CURRENT_DATE() GROUP BY organization_code, country, hour_of_day
),

stddev_same_weekday AS (
    SELECT organization_code, country, day_of_week, hour_of_day, COUNT(DISTINCT eval_date) AS sample_size, ROUND(AVG(total_calls), 0) AS avg_value, ROUND(STDDEV(total_calls), 2) AS stddev_value
    FROM hourly_metrics WHERE eval_date < CURRENT_DATE() GROUP BY organization_code, country, day_of_week, hour_of_day
),

baseline_dod AS (
    SELECT m.organization_code, m.country, m.hour_of_day, m.eval_date, d.total_calls AS baseline_value
    FROM display_metrics m LEFT JOIN hourly_metrics d ON m.organization_code = d.organization_code AND m.country = d.country AND m.hour_of_day = d.hour_of_day AND m.eval_date = d.eval_date + INTERVAL 1 DAY
),

baseline_wow AS (
    SELECT m.organization_code, m.country, m.hour_of_day, m.eval_date, w.total_calls AS baseline_value
    FROM display_metrics m LEFT JOIN hourly_metrics w ON m.organization_code = w.organization_code AND m.country = w.country AND m.hour_of_day = w.hour_of_day AND m.eval_date = w.eval_date + INTERVAL 7 DAY
)

SELECT m.eval_hour,
-- m.eval_date, m.hour_of_day,
    -- CASE m.day_of_week WHEN 1 THEN 'Sunday' WHEN 2 THEN 'Monday' WHEN 3 THEN 'Tuesday' WHEN 4 THEN 'Wednesday' WHEN 5 THEN 'Thursday' WHEN 6 THEN 'Friday' WHEN 7 THEN 'Saturday' END AS day_name,
    -- m.organization_code,
	m.organization_name, m.country,
    m.total_calls AS current_total_calls,
    dod.baseline_value AS baseline_dod_total_calls, m.total_calls - COALESCE(dod.baseline_value, 0) AS absolute_change_dod,
    CASE WHEN sad.stddev_value > 0 THEN ROUND((m.total_calls - dod.baseline_value) / sad.stddev_value, 2) ELSE NULL END AS z_score_dod,
    CASE WHEN dod.baseline_value IS NULL OR sad.sample_size < 5 THEN 'INSUFFICIENT_DATA' WHEN (m.total_calls - dod.baseline_value) / NULLIF(sad.stddev_value, 0) < -2.5 THEN 'CRITICAL' WHEN (m.total_calls - dod.baseline_value) / NULLIF(sad.stddev_value, 0) < -2.0 THEN 'WARNING' ELSE 'FINE' END AS severity_dod,
    wow.baseline_value AS baseline_wow_total_calls, m.total_calls - COALESCE(wow.baseline_value, 0) AS absolute_change_wow,
    CASE WHEN ssw.stddev_value > 0 THEN ROUND((m.total_calls - wow.baseline_value) / ssw.stddev_value, 2) ELSE NULL END AS z_score_wow,
    CASE WHEN wow.baseline_value IS NULL OR ssw.sample_size < 3 THEN 'INSUFFICIENT_DATA' WHEN (m.total_calls - wow.baseline_value) / NULLIF(ssw.stddev_value, 0) < -2.5 THEN 'CRITICAL' WHEN (m.total_calls - wow.baseline_value) / NULLIF(ssw.stddev_value, 0) < -2.0 THEN 'WARNING' ELSE 'FINE' END AS severity_wow,
    ssw.avg_value AS baseline_30d_avg_total_calls, m.total_calls - COALESCE(ssw.avg_value, 0) AS absolute_change_30d,
    CASE WHEN ssw.stddev_value > 0 THEN ROUND((m.total_calls - ssw.avg_value) / ssw.stddev_value, 2) ELSE NULL END AS z_score_30d,
    CASE WHEN ssw.avg_value IS NULL OR ssw.sample_size < 3 THEN 'INSUFFICIENT_DATA' WHEN (m.total_calls - ssw.avg_value) / NULLIF(ssw.stddev_value, 0) < -2.5 THEN 'CRITICAL' WHEN (m.total_calls - ssw.avg_value) / NULLIF(ssw.stddev_value, 0) < -2.0 THEN 'WARNING' ELSE 'FINE' END AS severity_30d
FROM display_metrics m
LEFT JOIN baseline_dod dod ON m.organization_code = dod.organization_code AND m.country = dod.country AND m.hour_of_day = dod.hour_of_day AND m.eval_date = dod.eval_date
LEFT JOIN baseline_wow wow ON m.organization_code = wow.organization_code AND m.country = wow.country AND m.hour_of_day = wow.hour_of_day AND m.eval_date = wow.eval_date
LEFT JOIN stddev_all_days sad ON m.organization_code = sad.organization_code AND m.country = sad.country AND m.hour_of_day = sad.hour_of_day
LEFT JOIN stddev_same_weekday ssw ON m.organization_code = ssw.organization_code AND m.country = ssw.country AND m.day_of_week = ssw.day_of_week AND m.hour_of_day = ssw.hour_of_day
ORDER BY m.eval_hour DESC, m.organization_name, m.country
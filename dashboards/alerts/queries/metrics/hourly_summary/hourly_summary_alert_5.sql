-- ==============================================================================
-- HOURLY ALERT 5: Call Duration (Historical - Last 7 days by hour)
-- ==============================================================================
-- Metric: avg_duration = AVG(call_duration_seconds) | Direction: BIDIRECTIONAL
-- ==============================================================================

WITH hourly_metrics AS (
    SELECT created_hour AS eval_hour, created_date AS eval_date, EXTRACT(HOUR FROM created_hour) AS hour_of_day, DAYOFWEEK(created_date) AS day_of_week,
        organization_code, organization_name, country, COUNT(*) AS completed_calls, ROUND(AVG(call_duration_seconds), 2) AS avg_duration
    FROM ai_calls_detail
    WHERE created_date >= CURRENT_DATE() - INTERVAL 14 DAY AND created_hour < DATE_TRUNC('hour', CURRENT_TIMESTAMP())
        AND call_classification IN ('good_calls', 'short_calls', 'completed') AND call_duration_seconds IS NOT NULL
        [[AND {{organization_name}}]]
        [[AND {{country}}]]
    GROUP BY created_hour, created_date, organization_code, organization_name, country HAVING COUNT(*) >= 5
),

display_metrics AS (SELECT * FROM hourly_metrics WHERE eval_date >= CURRENT_DATE() - INTERVAL 7 DAY),
stddev_all_days AS (SELECT organization_code, country, hour_of_day, COUNT(DISTINCT eval_date) AS sample_size, ROUND(STDDEV(avg_duration), 2) AS stddev_value FROM hourly_metrics WHERE eval_date < CURRENT_DATE() GROUP BY organization_code, country, hour_of_day),
stddev_same_weekday AS (SELECT organization_code, country, day_of_week, hour_of_day, COUNT(DISTINCT eval_date) AS sample_size, ROUND(AVG(avg_duration), 2) AS avg_value, ROUND(STDDEV(avg_duration), 2) AS stddev_value FROM hourly_metrics WHERE eval_date < CURRENT_DATE() GROUP BY organization_code, country, day_of_week, hour_of_day),
baseline_dod AS (SELECT m.organization_code, m.country, m.hour_of_day, m.eval_date, d.avg_duration AS baseline_value FROM display_metrics m LEFT JOIN hourly_metrics d ON m.organization_code = d.organization_code AND m.country = d.country AND m.hour_of_day = d.hour_of_day AND m.eval_date = d.eval_date + INTERVAL 1 DAY),
baseline_wow AS (SELECT m.organization_code, m.country, m.hour_of_day, m.eval_date, w.avg_duration AS baseline_value FROM display_metrics m LEFT JOIN hourly_metrics w ON m.organization_code = w.organization_code AND m.country = w.country AND m.hour_of_day = w.hour_of_day AND m.eval_date = w.eval_date + INTERVAL 7 DAY),

calculations AS (
    SELECT m.*, dod.baseline_value AS baseline_dod_avg_duration, wow.baseline_value AS baseline_wow_avg_duration, ssw.avg_value AS baseline_30d_avg_duration, sad.stddev_value AS stddev_all, ssw.stddev_value AS stddev_weekday, sad.sample_size AS sample_all, ssw.sample_size AS sample_weekday,
        CASE WHEN sad.stddev_value > 0 THEN ROUND((m.avg_duration - dod.baseline_value) / sad.stddev_value, 2) ELSE NULL END AS z_dod,
        CASE WHEN ssw.stddev_value > 0 THEN ROUND((m.avg_duration - wow.baseline_value) / ssw.stddev_value, 2) ELSE NULL END AS z_wow,
        CASE WHEN ssw.stddev_value > 0 THEN ROUND((m.avg_duration - ssw.avg_value) / ssw.stddev_value, 2) ELSE NULL END AS z_30d
    FROM display_metrics m
    LEFT JOIN baseline_dod dod ON m.organization_code = dod.organization_code AND m.country = dod.country AND m.hour_of_day = dod.hour_of_day AND m.eval_date = dod.eval_date
    LEFT JOIN baseline_wow wow ON m.organization_code = wow.organization_code AND m.country = wow.country AND m.hour_of_day = wow.hour_of_day AND m.eval_date = wow.eval_date
    LEFT JOIN stddev_all_days sad ON m.organization_code = sad.organization_code AND m.country = sad.country AND m.hour_of_day = sad.hour_of_day
    LEFT JOIN stddev_same_weekday ssw ON m.organization_code = ssw.organization_code AND m.country = ssw.country AND m.day_of_week = ssw.day_of_week AND m.hour_of_day = ssw.hour_of_day
)

SELECT eval_hour,
-- eval_date, hour_of_day,
    -- CASE day_of_week WHEN 1 THEN 'Sunday' WHEN 2 THEN 'Monday' WHEN 3 THEN 'Tuesday' WHEN 4 THEN 'Wednesday' WHEN 5 THEN 'Thursday' WHEN 6 THEN 'Friday' WHEN 7 THEN 'Saturday' END AS day_name,
    -- organization_code, 
	organization_name, country,
    completed_calls AS current_completed_calls, avg_duration AS current_avg_duration,
    CASE WHEN COALESCE(z_dod, 0) + COALESCE(z_wow, 0) + COALESCE(z_30d, 0) > 0 THEN 'TOO_LONG' WHEN COALESCE(z_dod, 0) + COALESCE(z_wow, 0) + COALESCE(z_30d, 0) < 0 THEN 'TOO_SHORT' ELSE 'NORMAL' END AS anomaly_type,
    baseline_dod_avg_duration, ROUND(avg_duration - COALESCE(baseline_dod_avg_duration, 0), 2) AS seconds_change_dod, z_dod AS z_score_dod,
    CASE WHEN baseline_dod_avg_duration IS NULL OR sample_all < 5 THEN 'INSUFFICIENT_DATA' WHEN ABS(z_dod) > 2.5 THEN 'CRITICAL' WHEN ABS(z_dod) > 2.0 THEN 'WARNING' ELSE 'FINE' END AS severity_dod,
    baseline_wow_avg_duration, ROUND(avg_duration - COALESCE(baseline_wow_avg_duration, 0), 2) AS seconds_change_wow, z_wow AS z_score_wow,
    CASE WHEN baseline_wow_avg_duration IS NULL OR sample_weekday < 3 THEN 'INSUFFICIENT_DATA' WHEN ABS(z_wow) > 2.5 THEN 'CRITICAL' WHEN ABS(z_wow) > 2.0 THEN 'WARNING' ELSE 'FINE' END AS severity_wow,
    baseline_30d_avg_duration, ROUND(avg_duration - COALESCE(baseline_30d_avg_duration, 0), 2) AS seconds_change_30d, z_30d AS z_score_30d,
    CASE WHEN baseline_30d_avg_duration IS NULL OR sample_weekday < 3 THEN 'INSUFFICIENT_DATA' WHEN ABS(z_30d) > 2.5 THEN 'CRITICAL' WHEN ABS(z_30d) > 2.0 THEN 'WARNING' ELSE 'FINE' END AS severity_30d
FROM calculations
ORDER BY eval_hour DESC, organization_name, country
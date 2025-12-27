-- ==============================================================================
-- CURRENT ALERT 2: Completion Rate
-- ==============================================================================
-- Metric: completion_rate = completed_calls / total_calls | Direction: LOWER is bad
-- ==============================================================================

WITH current_time_parts AS (
    SELECT EXTRACT(HOUR FROM CURRENT_TIMESTAMP()) AS current_hour, EXTRACT(MINUTE FROM CURRENT_TIMESTAMP()) AS current_minute
),

today AS (
    SELECT organization_code, organization_name, country, COUNT(*) AS total_calls,
        SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END) AS completed_calls,
        ROUND(CAST(SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END) AS FLOAT) / NULLIF(COUNT(*), 0), 4) AS completion_rate
    FROM ai_calls_detail, current_time_parts ctp
    WHERE created_date = CURRENT_DATE()
        AND (EXTRACT(HOUR FROM created_at) < ctp.current_hour OR (EXTRACT(HOUR FROM created_at) = ctp.current_hour AND EXTRACT(MINUTE FROM created_at) <= ctp.current_minute))
        [[AND {{organization_name}}]]
        [[AND {{country}}]]
    GROUP BY organization_code, organization_name, country
),

yesterday AS (
    SELECT organization_code, country, COUNT(*) AS total_calls,
        ROUND(CAST(SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END) AS FLOAT) / NULLIF(COUNT(*), 0), 4) AS completion_rate
    FROM ai_calls_detail, current_time_parts ctp
    WHERE created_date = CURRENT_DATE() - INTERVAL 1 DAY
        AND (EXTRACT(HOUR FROM created_at) < ctp.current_hour OR (EXTRACT(HOUR FROM created_at) = ctp.current_hour AND EXTRACT(MINUTE FROM created_at) <= ctp.current_minute))
        [[AND {{organization_name}}]]
        [[AND {{country}}]]
    GROUP BY organization_code, country
),

last_week AS (
    SELECT organization_code, country, COUNT(*) AS total_calls,
        ROUND(CAST(SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END) AS FLOAT) / NULLIF(COUNT(*), 0), 4) AS completion_rate
    FROM ai_calls_detail, current_time_parts ctp
    WHERE created_date = CURRENT_DATE() - INTERVAL 7 DAY
        AND (EXTRACT(HOUR FROM created_at) < ctp.current_hour OR (EXTRACT(HOUR FROM created_at) = ctp.current_hour AND EXTRACT(MINUTE FROM created_at) <= ctp.current_minute))
        [[AND {{organization_name}}]]
        [[AND {{country}}]]
    GROUP BY organization_code, country
),

stddev_all_days AS (
    SELECT organization_code, country, COUNT(DISTINCT created_date) AS sample_size, ROUND(STDDEV(daily_rate), 4) AS stddev_value
    FROM (
        SELECT organization_code, country, created_date,
            ROUND(CAST(SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END) AS FLOAT) / NULLIF(COUNT(*), 0), 4) AS daily_rate
        FROM ai_calls_detail, current_time_parts ctp
        WHERE created_date >= CURRENT_DATE() - INTERVAL 30 DAY AND created_date < CURRENT_DATE()
            AND (EXTRACT(HOUR FROM created_at) < ctp.current_hour OR (EXTRACT(HOUR FROM created_at) = ctp.current_hour AND EXTRACT(MINUTE FROM created_at) <= ctp.current_minute))
            [[AND {{organization_name}}]]
            [[AND {{country}}]]
        GROUP BY organization_code, country, created_date HAVING COUNT(*) >= 50
    ) t GROUP BY organization_code, country
),

stddev_same_weekday AS (
    SELECT organization_code, country, COUNT(DISTINCT created_date) AS sample_size, ROUND(AVG(daily_rate), 4) AS avg_value, ROUND(STDDEV(daily_rate), 4) AS stddev_value
    FROM (
        SELECT organization_code, country, created_date,
            ROUND(CAST(SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END) AS FLOAT) / NULLIF(COUNT(*), 0), 4) AS daily_rate
        FROM ai_calls_detail, current_time_parts ctp
        WHERE created_date >= CURRENT_DATE() - INTERVAL 30 DAY AND created_date < CURRENT_DATE()
            AND DAYOFWEEK(created_date) = DAYOFWEEK(CURRENT_DATE())
            AND (EXTRACT(HOUR FROM created_at) < ctp.current_hour OR (EXTRACT(HOUR FROM created_at) = ctp.current_hour AND EXTRACT(MINUTE FROM created_at) <= ctp.current_minute))
            [[AND {{organization_name}}]]
            [[AND {{country}}]]
        GROUP BY organization_code, country, created_date HAVING COUNT(*) >= 50
    ) t GROUP BY organization_code, country
),

calculations AS (
    SELECT t.organization_code, t.organization_name, t.country,
        t.total_calls AS current_total_calls, t.completion_rate AS current_completion_rate,
        y.total_calls AS baseline_dod_total_calls, y.completion_rate AS baseline_dod_completion_rate,
        ROUND((t.completion_rate - COALESCE(y.completion_rate, 0)) * 100, 2) AS pp_change_dod,
        CASE WHEN sad.stddev_value > 0 THEN ROUND((t.completion_rate - y.completion_rate) / sad.stddev_value, 2) ELSE NULL END AS z_score_dod,
        lw.total_calls AS baseline_wow_total_calls, lw.completion_rate AS baseline_wow_completion_rate,
        ROUND((t.completion_rate - COALESCE(lw.completion_rate, 0)) * 100, 2) AS pp_change_wow,
        CASE WHEN ssw.stddev_value > 0 THEN ROUND((t.completion_rate - lw.completion_rate) / ssw.stddev_value, 2) ELSE NULL END AS z_score_wow,
        ssw.avg_value AS baseline_30d_avg_completion_rate,
        ROUND((t.completion_rate - COALESCE(ssw.avg_value, 0)) * 100, 2) AS pp_change_30d,
        CASE WHEN ssw.stddev_value > 0 THEN ROUND((t.completion_rate - ssw.avg_value) / ssw.stddev_value, 2) ELSE NULL END AS z_score_30d,
        sad.sample_size AS sample_size_all_days, ssw.sample_size AS sample_size_weekday
    FROM today t
    LEFT JOIN yesterday y ON t.organization_code = y.organization_code AND t.country = y.country
    LEFT JOIN last_week lw ON t.organization_code = lw.organization_code AND t.country = lw.country
    LEFT JOIN stddev_all_days sad ON t.organization_code = sad.organization_code AND t.country = sad.country
    LEFT JOIN stddev_same_weekday ssw ON t.organization_code = ssw.organization_code AND t.country = ssw.country
)

SELECT CURRENT_TIMESTAMP() AS evaluated_at, 
-- CURRENT_DATE() AS evaluated_date,
    -- organization_code, 
	organization_name, country, current_total_calls, current_completion_rate,
    baseline_dod_total_calls, baseline_dod_completion_rate, pp_change_dod, z_score_dod,
    CASE WHEN current_total_calls < 50 OR baseline_dod_total_calls < 50 OR sample_size_all_days < 10 OR z_score_dod IS NULL THEN 'INSUFFICIENT_DATA' WHEN z_score_dod < -2.5 THEN 'CRITICAL' WHEN z_score_dod < -2.0 THEN 'WARNING' ELSE 'FINE' END AS severity_dod,
    baseline_wow_total_calls, baseline_wow_completion_rate, pp_change_wow, z_score_wow,
    CASE WHEN current_total_calls < 50 OR sample_size_weekday < 3 OR z_score_wow IS NULL THEN 'INSUFFICIENT_DATA' WHEN z_score_wow < -2.5 THEN 'CRITICAL' WHEN z_score_wow < -2.0 THEN 'WARNING' ELSE 'FINE' END AS severity_wow,
    baseline_30d_avg_completion_rate, pp_change_30d, z_score_30d,
    CASE WHEN current_total_calls < 50 OR sample_size_weekday < 3 OR z_score_30d IS NULL THEN 'INSUFFICIENT_DATA' WHEN z_score_30d < -2.5 THEN 'CRITICAL' WHEN z_score_30d < -2.0 THEN 'WARNING' ELSE 'FINE' END AS severity_30d,
    CASE
        WHEN (CASE WHEN current_total_calls < 50 OR baseline_dod_total_calls < 50 OR sample_size_all_days < 10 OR z_score_dod IS NULL THEN 'INSUFFICIENT_DATA' WHEN z_score_dod < -2.5 THEN 'CRITICAL' WHEN z_score_dod < -2.0 THEN 'WARNING' ELSE 'FINE' END) = 'CRITICAL'
         AND (CASE WHEN current_total_calls < 50 OR sample_size_weekday < 3 OR z_score_wow IS NULL THEN 'INSUFFICIENT_DATA' WHEN z_score_wow < -2.5 THEN 'CRITICAL' WHEN z_score_wow < -2.0 THEN 'WARNING' ELSE 'FINE' END) = 'CRITICAL'
         AND (CASE WHEN current_total_calls < 50 OR sample_size_weekday < 3 OR z_score_30d IS NULL THEN 'INSUFFICIENT_DATA' WHEN z_score_30d < -2.5 THEN 'CRITICAL' WHEN z_score_30d < -2.0 THEN 'WARNING' ELSE 'FINE' END) = 'CRITICAL' THEN 'CRITICAL'
        WHEN (CASE WHEN current_total_calls < 50 OR baseline_dod_total_calls < 50 OR sample_size_all_days < 10 OR z_score_dod IS NULL THEN 'INSUFFICIENT_DATA' WHEN z_score_dod < -2.5 THEN 'CRITICAL' WHEN z_score_dod < -2.0 THEN 'WARNING' ELSE 'FINE' END) IN ('CRITICAL', 'WARNING')
         AND (CASE WHEN current_total_calls < 50 OR sample_size_weekday < 3 OR z_score_wow IS NULL THEN 'INSUFFICIENT_DATA' WHEN z_score_wow < -2.5 THEN 'CRITICAL' WHEN z_score_wow < -2.0 THEN 'WARNING' ELSE 'FINE' END) IN ('CRITICAL', 'WARNING')
         AND (CASE WHEN current_total_calls < 50 OR sample_size_weekday < 3 OR z_score_30d IS NULL THEN 'INSUFFICIENT_DATA' WHEN z_score_30d < -2.5 THEN 'CRITICAL' WHEN z_score_30d < -2.0 THEN 'WARNING' ELSE 'FINE' END) IN ('CRITICAL', 'WARNING') THEN 'WARNING'
        ELSE 'FINE'
    END AS main_severity
FROM calculations
ORDER BY organization_name, country
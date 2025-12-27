-- ==============================================================================
-- CURRENT ALERT 1: Volume
-- ==============================================================================
-- Metric: total_calls | Direction: LOWER is bad
-- ==============================================================================

WITH current_time_parts AS (
    SELECT 
        EXTRACT(HOUR FROM CURRENT_TIMESTAMP()) AS current_hour,
        EXTRACT(MINUTE FROM CURRENT_TIMESTAMP()) AS current_minute
),

today AS (
    SELECT organization_code, organization_name, country, COUNT(*) AS total_calls
    FROM ai_calls_detail, current_time_parts ctp
    WHERE created_date = CURRENT_DATE()
        AND (EXTRACT(HOUR FROM created_at) < ctp.current_hour OR (EXTRACT(HOUR FROM created_at) = ctp.current_hour AND EXTRACT(MINUTE FROM created_at) <= ctp.current_minute))
        [[AND {{organization_name}}]]
        [[AND {{country}}]]
    GROUP BY organization_code, organization_name, country
),

yesterday AS (
    SELECT organization_code, country, COUNT(*) AS total_calls
    FROM ai_calls_detail, current_time_parts ctp
    WHERE created_date = CURRENT_DATE() - INTERVAL 1 DAY
        AND (EXTRACT(HOUR FROM created_at) < ctp.current_hour OR (EXTRACT(HOUR FROM created_at) = ctp.current_hour AND EXTRACT(MINUTE FROM created_at) <= ctp.current_minute))
        [[AND {{organization_name}}]]
        [[AND {{country}}]]
    GROUP BY organization_code, country
),

last_week AS (
    SELECT organization_code, country, COUNT(*) AS total_calls
    FROM ai_calls_detail, current_time_parts ctp
    WHERE created_date = CURRENT_DATE() - INTERVAL 7 DAY
        AND (EXTRACT(HOUR FROM created_at) < ctp.current_hour OR (EXTRACT(HOUR FROM created_at) = ctp.current_hour AND EXTRACT(MINUTE FROM created_at) <= ctp.current_minute))
        [[AND {{organization_name}}]]
        [[AND {{country}}]]
    GROUP BY organization_code, country
),

stddev_all_days AS (
    SELECT organization_code, country, COUNT(DISTINCT created_date) AS sample_size, ROUND(STDDEV(daily_calls), 2) AS stddev_value
    FROM (
        SELECT organization_code, country, created_date, COUNT(*) AS daily_calls
        FROM ai_calls_detail, current_time_parts ctp
        WHERE created_date >= CURRENT_DATE() - INTERVAL 30 DAY AND created_date < CURRENT_DATE()
            AND (EXTRACT(HOUR FROM created_at) < ctp.current_hour OR (EXTRACT(HOUR FROM created_at) = ctp.current_hour AND EXTRACT(MINUTE FROM created_at) <= ctp.current_minute))
            [[AND {{organization_name}}]]
            [[AND {{country}}]]
        GROUP BY organization_code, country, created_date
    ) t GROUP BY organization_code, country
),

stddev_same_weekday AS (
    SELECT organization_code, country, COUNT(DISTINCT created_date) AS sample_size, ROUND(AVG(daily_calls), 0) AS avg_value, ROUND(STDDEV(daily_calls), 2) AS stddev_value
    FROM (
        SELECT organization_code, country, created_date, COUNT(*) AS daily_calls
        FROM ai_calls_detail, current_time_parts ctp
        WHERE created_date >= CURRENT_DATE() - INTERVAL 30 DAY AND created_date < CURRENT_DATE()
            AND DAYOFWEEK(created_date) = DAYOFWEEK(CURRENT_DATE())
            AND (EXTRACT(HOUR FROM created_at) < ctp.current_hour OR (EXTRACT(HOUR FROM created_at) = ctp.current_hour AND EXTRACT(MINUTE FROM created_at) <= ctp.current_minute))
            [[AND {{organization_name}}]]
            [[AND {{country}}]]
        GROUP BY organization_code, country, created_date
    ) t GROUP BY organization_code, country
),

calculations AS (
    SELECT
        t.organization_code, t.organization_name, t.country,
        t.total_calls AS current_total_calls,
        y.total_calls AS baseline_dod_total_calls,
        t.total_calls - COALESCE(y.total_calls, 0) AS absolute_change_dod,
        CASE WHEN y.total_calls > 0 THEN ROUND((t.total_calls - y.total_calls) * 100.0 / y.total_calls, 1) ELSE NULL END AS pct_change_dod,
        CASE WHEN sad.stddev_value > 0 THEN ROUND((t.total_calls - y.total_calls) / sad.stddev_value, 2) ELSE NULL END AS z_score_dod,
        lw.total_calls AS baseline_wow_total_calls,
        t.total_calls - COALESCE(lw.total_calls, 0) AS absolute_change_wow,
        CASE WHEN lw.total_calls > 0 THEN ROUND((t.total_calls - lw.total_calls) * 100.0 / lw.total_calls, 1) ELSE NULL END AS pct_change_wow,
        CASE WHEN ssw.stddev_value > 0 THEN ROUND((t.total_calls - lw.total_calls) / ssw.stddev_value, 2) ELSE NULL END AS z_score_wow,
        ssw.avg_value AS baseline_30d_avg_total_calls,
        t.total_calls - COALESCE(ssw.avg_value, 0) AS absolute_change_30d,
        CASE WHEN ssw.avg_value > 0 THEN ROUND((t.total_calls - ssw.avg_value) * 100.0 / ssw.avg_value, 1) ELSE NULL END AS pct_change_30d,
        CASE WHEN ssw.stddev_value > 0 THEN ROUND((t.total_calls - ssw.avg_value) / ssw.stddev_value, 2) ELSE NULL END AS z_score_30d,
        sad.sample_size AS sample_size_all_days, ssw.sample_size AS sample_size_weekday
    FROM today t
    LEFT JOIN yesterday y ON t.organization_code = y.organization_code AND t.country = y.country
    LEFT JOIN last_week lw ON t.organization_code = lw.organization_code AND t.country = lw.country
    LEFT JOIN stddev_all_days sad ON t.organization_code = sad.organization_code AND t.country = sad.country
    LEFT JOIN stddev_same_weekday ssw ON t.organization_code = ssw.organization_code AND t.country = ssw.country
)

SELECT
    CURRENT_TIMESTAMP() AS evaluated_at,
	-- CURRENT_DATE() AS evaluated_date,
    -- organization_code,
	organization_name, country, current_total_calls,
    baseline_dod_total_calls, absolute_change_dod, pct_change_dod, z_score_dod,
    CASE WHEN baseline_dod_total_calls IS NULL OR sample_size_all_days < 10 OR z_score_dod IS NULL THEN 'INSUFFICIENT_DATA' WHEN z_score_dod < -2.5 THEN 'CRITICAL' WHEN z_score_dod < -2.0 THEN 'WARNING' ELSE 'FINE' END AS severity_dod,
    baseline_wow_total_calls, absolute_change_wow, pct_change_wow, z_score_wow,
    CASE WHEN baseline_wow_total_calls IS NULL OR sample_size_weekday < 3 OR z_score_wow IS NULL THEN 'INSUFFICIENT_DATA' WHEN z_score_wow < -2.5 THEN 'CRITICAL' WHEN z_score_wow < -2.0 THEN 'WARNING' ELSE 'FINE' END AS severity_wow,
    baseline_30d_avg_total_calls, absolute_change_30d, pct_change_30d, z_score_30d,
    CASE WHEN baseline_30d_avg_total_calls IS NULL OR sample_size_weekday < 3 OR z_score_30d IS NULL THEN 'INSUFFICIENT_DATA' WHEN z_score_30d < -2.5 THEN 'CRITICAL' WHEN z_score_30d < -2.0 THEN 'WARNING' ELSE 'FINE' END AS severity_30d,
    CASE
        WHEN (CASE WHEN baseline_dod_total_calls IS NULL OR sample_size_all_days < 10 OR z_score_dod IS NULL THEN 'INSUFFICIENT_DATA' WHEN z_score_dod < -2.5 THEN 'CRITICAL' WHEN z_score_dod < -2.0 THEN 'WARNING' ELSE 'FINE' END) = 'CRITICAL'
         AND (CASE WHEN baseline_wow_total_calls IS NULL OR sample_size_weekday < 3 OR z_score_wow IS NULL THEN 'INSUFFICIENT_DATA' WHEN z_score_wow < -2.5 THEN 'CRITICAL' WHEN z_score_wow < -2.0 THEN 'WARNING' ELSE 'FINE' END) = 'CRITICAL'
         AND (CASE WHEN baseline_30d_avg_total_calls IS NULL OR sample_size_weekday < 3 OR z_score_30d IS NULL THEN 'INSUFFICIENT_DATA' WHEN z_score_30d < -2.5 THEN 'CRITICAL' WHEN z_score_30d < -2.0 THEN 'WARNING' ELSE 'FINE' END) = 'CRITICAL' THEN 'CRITICAL'
        WHEN (CASE WHEN baseline_dod_total_calls IS NULL OR sample_size_all_days < 10 OR z_score_dod IS NULL THEN 'INSUFFICIENT_DATA' WHEN z_score_dod < -2.5 THEN 'CRITICAL' WHEN z_score_dod < -2.0 THEN 'WARNING' ELSE 'FINE' END) IN ('CRITICAL', 'WARNING')
         AND (CASE WHEN baseline_wow_total_calls IS NULL OR sample_size_weekday < 3 OR z_score_wow IS NULL THEN 'INSUFFICIENT_DATA' WHEN z_score_wow < -2.5 THEN 'CRITICAL' WHEN z_score_wow < -2.0 THEN 'WARNING' ELSE 'FINE' END) IN ('CRITICAL', 'WARNING')
         AND (CASE WHEN baseline_30d_avg_total_calls IS NULL OR sample_size_weekday < 3 OR z_score_30d IS NULL THEN 'INSUFFICIENT_DATA' WHEN z_score_30d < -2.5 THEN 'CRITICAL' WHEN z_score_30d < -2.0 THEN 'WARNING' ELSE 'FINE' END) IN ('CRITICAL', 'WARNING') THEN 'WARNING'
        ELSE 'FINE'
    END AS main_severity
FROM calculations
ORDER BY organization_name, country
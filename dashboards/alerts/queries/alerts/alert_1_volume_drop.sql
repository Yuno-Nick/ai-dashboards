-- ==============================================================================
-- Alert 1: Volume Drop - MAIN ALERT
-- ==============================================================================
-- Este es el ALERT PRINCIPAL que solo se dispara cuando los 3 sub-alerts
-- están en WARNING o CRITICAL simultáneamente.
-- 
-- Métrica: total_calls (volumen de llamadas)
-- Dirección: Lower is bad
--
-- Sub-alerts:
--   1.1: vs DoD (ayer mismo momento) - usa stddev_all_days
--   1.2: vs WoW (semana pasada mismo día/momento) - usa stddev_same_weekday
--   1.3: vs 30d Avg (promedio 30 días mismo weekday) - usa stddev_same_weekday
--
-- Esta alerta detecta CAÍDAS DE VOLUMEN significativas.
-- Para problemas de CALIDAD (completion rate), ver Alert 6.
-- ==============================================================================

WITH current_time_parts AS (
    SELECT 
        EXTRACT(HOUR FROM CURRENT_TIMESTAMP()) AS current_hour,
        EXTRACT(MINUTE FROM CURRENT_TIMESTAMP()) AS current_minute
),

today_metrics AS (
    SELECT
        organization_code,
        organization_name,
        country,
        DAYOFWEEK(CURRENT_DATE()) AS day_of_week,
        
        COUNT(*) AS total_calls,
        SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') 
                 THEN 1 ELSE 0 END) AS completed_calls,
        SUM(CASE WHEN call_classification = 'failed' THEN 1 ELSE 0 END) AS failed_calls
        
    FROM ai_calls_detail, current_time_parts ctp
    WHERE 
        created_date = CURRENT_DATE()
        AND (
            EXTRACT(HOUR FROM created_at) < ctp.current_hour
            OR (
                EXTRACT(HOUR FROM created_at) = ctp.current_hour
                AND EXTRACT(MINUTE FROM created_at) <= ctp.current_minute
            )
        )
    GROUP BY organization_code, organization_name, country
),

yesterday_metrics AS (
    SELECT
        organization_code,
        country,
        COUNT(*) AS total_calls,
        SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') 
                 THEN 1 ELSE 0 END) AS completed_calls
        
    FROM ai_calls_detail, current_time_parts ctp
    WHERE 
        created_date = CURRENT_DATE() - INTERVAL 1 DAY
        AND (
            EXTRACT(HOUR FROM created_at) < ctp.current_hour
            OR (
                EXTRACT(HOUR FROM created_at) = ctp.current_hour
                AND EXTRACT(MINUTE FROM created_at) <= ctp.current_minute
            )
        )
    GROUP BY organization_code, country
),

lastweek_metrics AS (
    SELECT
        organization_code,
        country,
        COUNT(*) AS total_calls,
        SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') 
                 THEN 1 ELSE 0 END) AS completed_calls
        
    FROM ai_calls_detail, current_time_parts ctp
    WHERE 
        created_date = CURRENT_DATE() - INTERVAL 7 DAY
        AND (
            EXTRACT(HOUR FROM created_at) < ctp.current_hour
            OR (
                EXTRACT(HOUR FROM created_at) = ctp.current_hour
                AND EXTRACT(MINUTE FROM created_at) <= ctp.current_minute
            )
        )
    GROUP BY organization_code, country
),

-- Stddev de TODOS los días (para DoD)
stddev_all_days AS (
    SELECT
        organization_code,
        country,
        COUNT(DISTINCT created_date) AS sample_size,
        ROUND(STDDEV(daily_total_calls), 2) AS stddev_total_calls
    FROM (
        SELECT
            d.organization_code,
            d.country,
            d.created_date,
            COUNT(*) AS daily_total_calls
        FROM ai_calls_detail d, current_time_parts ctp
        WHERE 
            d.created_date >= CURRENT_DATE() - INTERVAL 30 DAY
            AND d.created_date < CURRENT_DATE()
            AND (
                EXTRACT(HOUR FROM d.created_at) < ctp.current_hour
                OR (
                    EXTRACT(HOUR FROM d.created_at) = ctp.current_hour
                    AND EXTRACT(MINUTE FROM d.created_at) <= ctp.current_minute
                )
            )
        GROUP BY d.organization_code, d.country, d.created_date
    ) daily_stats
    GROUP BY organization_code, country
),

-- Stddev y promedio del MISMO DÍA DE SEMANA (para WoW y 30d)
stddev_same_weekday AS (
    SELECT
        organization_code,
        country,
        COUNT(DISTINCT created_date) AS sample_size,
        ROUND(AVG(daily_total_calls), 0) AS avg_total_calls,
        ROUND(STDDEV(daily_total_calls), 2) AS stddev_total_calls,
        ROUND(AVG(daily_completed_calls), 0) AS avg_completed_calls
    FROM (
        SELECT
            d.organization_code,
            d.country,
            d.created_date,
            COUNT(*) AS daily_total_calls,
            SUM(CASE WHEN d.call_classification IN ('good_calls', 'short_calls', 'completed') 
                     THEN 1 ELSE 0 END) AS daily_completed_calls
        FROM ai_calls_detail d, current_time_parts ctp
        WHERE 
            d.created_date >= CURRENT_DATE() - INTERVAL 30 DAY
            AND d.created_date < CURRENT_DATE()
            AND DAYOFWEEK(d.created_date) = DAYOFWEEK(CURRENT_DATE())
            AND (
                EXTRACT(HOUR FROM d.created_at) < ctp.current_hour
                OR (
                    EXTRACT(HOUR FROM d.created_at) = ctp.current_hour
                    AND EXTRACT(MINUTE FROM d.created_at) <= ctp.current_minute
                )
            )
        GROUP BY d.organization_code, d.country, d.created_date
    ) daily_stats
    GROUP BY organization_code, country
),

subalert_calculations AS (
    SELECT
        t.organization_code,
        t.organization_name,
        t.country,
        
        -- Métricas actuales
        t.total_calls AS current_total_calls,
        t.completed_calls AS current_completed_calls,
        t.failed_calls AS current_failed_calls,
        
        -- Baseline 1: DoD (ayer) - usa stddev_all_days
        y.total_calls AS baseline_dod,
        y.completed_calls AS baseline_dod_completed,
        sad.stddev_total_calls AS stddev_all_days,
        sad.sample_size AS sample_size_all_days,
        CASE 
            WHEN sad.stddev_total_calls IS NULL OR sad.stddev_total_calls = 0 THEN NULL
            ELSE ROUND((CAST(t.total_calls AS FLOAT) - y.total_calls) / sad.stddev_total_calls, 2)
        END AS z_score_dod,
        CASE 
            WHEN y.total_calls IS NULL OR y.total_calls = 0 THEN NULL
            ELSE ROUND((CAST(t.total_calls AS FLOAT) - y.total_calls) / y.total_calls * 100, 1)
        END AS pct_change_dod,
        t.total_calls - COALESCE(y.total_calls, 0) AS absolute_change_dod,
        
        -- Baseline 2: WoW (semana pasada) - usa stddev_same_weekday
        lw.total_calls AS baseline_wow,
        lw.completed_calls AS baseline_wow_completed,
        ssw.stddev_total_calls AS stddev_same_weekday,
        ssw.sample_size AS sample_size_weekday,
        CASE 
            WHEN ssw.stddev_total_calls IS NULL OR ssw.stddev_total_calls = 0 THEN NULL
            ELSE ROUND((CAST(t.total_calls AS FLOAT) - lw.total_calls) / ssw.stddev_total_calls, 2)
        END AS z_score_wow,
        CASE 
            WHEN lw.total_calls IS NULL OR lw.total_calls = 0 THEN NULL
            ELSE ROUND((CAST(t.total_calls AS FLOAT) - lw.total_calls) / lw.total_calls * 100, 1)
        END AS pct_change_wow,
        t.total_calls - COALESCE(lw.total_calls, 0) AS absolute_change_wow,
        
        -- Baseline 3: 30d Avg (mismo día de semana) - usa stddev_same_weekday
        ssw.avg_total_calls AS baseline_30d,
        ssw.avg_completed_calls AS baseline_30d_completed,
        CASE 
            WHEN ssw.stddev_total_calls IS NULL OR ssw.stddev_total_calls = 0 THEN NULL
            ELSE ROUND((CAST(t.total_calls AS FLOAT) - ssw.avg_total_calls) / ssw.stddev_total_calls, 2)
        END AS z_score_30d,
        CASE 
            WHEN ssw.avg_total_calls IS NULL OR ssw.avg_total_calls = 0 THEN NULL
            ELSE ROUND((CAST(t.total_calls AS FLOAT) - ssw.avg_total_calls) / ssw.avg_total_calls * 100, 1)
        END AS pct_change_30d,
        t.total_calls - COALESCE(ssw.avg_total_calls, 0) AS absolute_change_30d
        
    FROM today_metrics t
    LEFT JOIN yesterday_metrics y
        ON t.organization_code = y.organization_code
        AND t.country = y.country
    LEFT JOIN lastweek_metrics lw
        ON t.organization_code = lw.organization_code
        AND t.country = lw.country
    LEFT JOIN stddev_all_days sad
        ON t.organization_code = sad.organization_code
        AND t.country = sad.country
    LEFT JOIN stddev_same_weekday ssw
        ON t.organization_code = ssw.organization_code
        AND t.country = ssw.country
),

subalert_severities AS (
    SELECT
        *,
        
        -- Severidad Sub-alert 3.1 (DoD) - usa stddev_all_days
        CASE
            WHEN baseline_dod IS NULL THEN 'INSUFFICIENT_DATA'
            WHEN stddev_all_days IS NULL OR stddev_all_days = 0 THEN 'INSUFFICIENT_DATA'
            WHEN sample_size_all_days < 10 THEN 'INSUFFICIENT_DATA'
            WHEN z_score_dod < -2.5 THEN 'CRITICAL'
            WHEN z_score_dod < -2.0 THEN 'WARNING'
            ELSE 'FINE'
        END AS severity_dod,
        
        -- Severidad Sub-alert 3.2 (WoW) - usa stddev_same_weekday
        CASE
            WHEN baseline_wow IS NULL THEN 'INSUFFICIENT_DATA'
            WHEN stddev_same_weekday IS NULL OR stddev_same_weekday = 0 THEN 'INSUFFICIENT_DATA'
            WHEN sample_size_weekday < 3 THEN 'INSUFFICIENT_DATA'
            WHEN z_score_wow < -2.5 THEN 'CRITICAL'
            WHEN z_score_wow < -2.0 THEN 'WARNING'
            ELSE 'FINE'
        END AS severity_wow,
        
        -- Severidad Sub-alert 3.3 (30d Avg) - usa stddev_same_weekday
        CASE
            WHEN baseline_30d IS NULL THEN 'INSUFFICIENT_DATA'
            WHEN stddev_same_weekday IS NULL OR stddev_same_weekday = 0 THEN 'INSUFFICIENT_DATA'
            WHEN sample_size_weekday < 3 THEN 'INSUFFICIENT_DATA'
            WHEN z_score_30d < -2.5 THEN 'CRITICAL'
            WHEN z_score_30d < -2.0 THEN 'WARNING'
            ELSE 'FINE'
        END AS severity_30d
        
    FROM subalert_calculations
),

main_alert AS (
    SELECT
        *,
        
        CASE
            WHEN severity_dod = 'CRITICAL' 
                AND severity_wow = 'CRITICAL' 
                AND severity_30d = 'CRITICAL'
            THEN 'CRITICAL'
            
            WHEN severity_dod IN ('CRITICAL', 'WARNING')
                AND severity_wow IN ('CRITICAL', 'WARNING')
                AND severity_30d IN ('CRITICAL', 'WARNING')
            THEN 'WARNING'
            
            ELSE 'FINE'
        END AS main_severity
        
    FROM subalert_severities
)

SELECT
    CASE
        WHEN main_severity = 'CRITICAL' THEN
            CONCAT(
                '🔴 CRITICAL: ', organization_name, ' (', country, ') - CAÍDA DE VOLUMEN CONFIRMADA. ',
                'Volumen actual: ', CAST(current_total_calls AS VARCHAR), ' llamadas ',
                '(', CAST(current_completed_calls AS VARCHAR), ' completadas, ', 
                CAST(current_failed_calls AS VARCHAR), ' fallidas). ',
                '▼ vs Ayer: ', CAST(baseline_dod AS VARCHAR), ' → ', 
                CAST(pct_change_dod AS VARCHAR), '% (', CAST(absolute_change_dod AS VARCHAR), '). ',
                '▼ vs Semana pasada: ', CAST(baseline_wow AS VARCHAR), ' → ', 
                CAST(pct_change_wow AS VARCHAR), '% (', CAST(absolute_change_wow AS VARCHAR), '). ',
                '▼ vs Promedio 30d: ', CAST(baseline_30d AS VARCHAR), ' → ', 
                CAST(pct_change_30d AS VARCHAR), '% (', CAST(absolute_change_30d AS VARCHAR), '). ',
                'ACCIÓN REQUERIDA: Verificar integraciones, campañas activas y fuente de datos.'
            )
        
        WHEN main_severity = 'WARNING' THEN
            CONCAT(
                '🟠 WARNING: ', organization_name, ' (', country, ') - Volumen bajo en todas las comparaciones. ',
                'Volumen actual: ', CAST(current_total_calls AS VARCHAR), ' llamadas. ',
                'Comparaciones: Ayer ', CAST(baseline_dod AS VARCHAR), ' (', CAST(pct_change_dod AS VARCHAR), '%) | ',
                'Semana pasada ', CAST(baseline_wow AS VARCHAR), ' (', CAST(pct_change_wow AS VARCHAR), '%) | ',
                'Promedio 30d ', CAST(baseline_30d AS VARCHAR), ' (', CAST(pct_change_30d AS VARCHAR), '%). ',
                'Monitorear de cerca.'
            )
        
        ELSE NULL
    END AS alert_message

FROM main_alert
WHERE main_severity IN ('CRITICAL', 'WARNING')
ORDER BY 
    CASE main_severity 
        WHEN 'CRITICAL' THEN 1 
        WHEN 'WARNING' THEN 2 
        ELSE 3 
    END,
    LEAST(COALESCE(z_score_dod, 0), COALESCE(z_score_wow, 0), COALESCE(z_score_30d, 0)) ASC
-- ==============================================================================
-- Alert 5: Call Duration Anomaly - MAIN ALERT
-- ==============================================================================
-- Este es el ALERT PRINCIPAL que solo se dispara cuando los 3 sub-alerts
-- están en WARNING o CRITICAL simultáneamente.
-- 
-- Métrica: avg_call_duration_seconds
-- Dirección: BIDIRECCIONAL (anomalías tanto cortas como largas)
--
-- Sub-alerts:
--   5.1: vs DoD (ayer mismo momento) - usa stddev_all_days
--   5.2: vs WoW (semana pasada mismo día/momento) - usa stddev_same_weekday
--   5.3: vs 30d Avg (promedio 30 días mismo weekday) - usa stddev_same_weekday
--
-- Esta alerta detecta ANOMALÍAS EN LA DURACIÓN DE LLAMADAS.
-- TOO_SHORT: problemas de audio, hang-ups prematuros
-- TOO_LONG: loops en el agente, conversaciones sin cierre
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
        
        ROUND(AVG(call_duration_seconds), 2) AS avg_duration_seconds
        
    FROM ai_calls_detail, current_time_parts ctp
    WHERE 
        created_date = CURRENT_DATE()
        AND call_classification IN ('good_calls', 'short_calls', 'completed')
        AND call_duration_seconds IS NOT NULL
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
                 THEN 1 ELSE 0 END) AS completed_calls,
        ROUND(AVG(call_duration_seconds), 2) AS avg_duration_seconds
        
    FROM ai_calls_detail, current_time_parts ctp
    WHERE 
        created_date = CURRENT_DATE() - INTERVAL 1 DAY
        AND call_classification IN ('good_calls', 'short_calls', 'completed')
        AND call_duration_seconds IS NOT NULL
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
                 THEN 1 ELSE 0 END) AS completed_calls,
        ROUND(AVG(call_duration_seconds), 2) AS avg_duration_seconds
        
    FROM ai_calls_detail, current_time_parts ctp
    WHERE 
        created_date = CURRENT_DATE() - INTERVAL 7 DAY
        AND call_classification IN ('good_calls', 'short_calls', 'completed')
        AND call_duration_seconds IS NOT NULL
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
        ROUND(STDDEV(daily_avg_duration), 2) AS stddev_duration
    FROM (
        SELECT
            d.organization_code,
            d.country,
            d.created_date,
            ROUND(AVG(d.call_duration_seconds), 2) AS daily_avg_duration
        FROM ai_calls_detail d, current_time_parts ctp
        WHERE 
            d.created_date >= CURRENT_DATE() - INTERVAL 30 DAY
            AND d.created_date < CURRENT_DATE()
            AND d.call_classification IN ('good_calls', 'short_calls', 'completed')
            AND d.call_duration_seconds IS NOT NULL
            AND (
                EXTRACT(HOUR FROM d.created_at) < ctp.current_hour
                OR (
                    EXTRACT(HOUR FROM d.created_at) = ctp.current_hour
                    AND EXTRACT(MINUTE FROM d.created_at) <= ctp.current_minute
                )
            )
        GROUP BY d.organization_code, d.country, d.created_date
        HAVING COUNT(*) >= 30
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
        ROUND(AVG(daily_completed_calls), 0) AS avg_completed_calls,
        ROUND(AVG(daily_avg_duration), 2) AS avg_duration,
        ROUND(STDDEV(daily_avg_duration), 2) AS stddev_duration
    FROM (
        SELECT
            d.organization_code,
            d.country,
            d.created_date,
            COUNT(*) AS daily_total_calls,
            SUM(CASE WHEN d.call_classification IN ('good_calls', 'short_calls', 'completed') 
                     THEN 1 ELSE 0 END) AS daily_completed_calls,
            ROUND(AVG(d.call_duration_seconds), 2) AS daily_avg_duration
        FROM ai_calls_detail d, current_time_parts ctp
        WHERE 
            d.created_date >= CURRENT_DATE() - INTERVAL 30 DAY
            AND d.created_date < CURRENT_DATE()
            AND DAYOFWEEK(d.created_date) = DAYOFWEEK(CURRENT_DATE())
            AND d.call_classification IN ('good_calls', 'short_calls', 'completed')
            AND d.call_duration_seconds IS NOT NULL
            AND (
                EXTRACT(HOUR FROM d.created_at) < ctp.current_hour
                OR (
                    EXTRACT(HOUR FROM d.created_at) = ctp.current_hour
                    AND EXTRACT(MINUTE FROM d.created_at) <= ctp.current_minute
                )
            )
        GROUP BY d.organization_code, d.country, d.created_date
        HAVING COUNT(*) >= 30
    ) daily_stats
    GROUP BY organization_code, country
),

subalert_calculations AS (
    SELECT
        t.organization_code,
        t.organization_name,
        t.country,
        
        t.total_calls AS current_total_calls,
        t.completed_calls AS current_completed_calls,
        t.avg_duration_seconds AS current_avg_duration,
        
        -- Baseline 1: DoD (ayer)
        y.total_calls AS baseline_dod_total,
        y.completed_calls AS baseline_dod_completed,
        y.avg_duration_seconds AS baseline_dod_duration,
        sad.stddev_duration AS stddev_all_days,
        sad.sample_size AS sample_size_all_days,
        CASE 
            WHEN sad.stddev_duration IS NULL OR sad.stddev_duration = 0 THEN NULL
            ELSE ROUND((t.avg_duration_seconds - y.avg_duration_seconds) / sad.stddev_duration, 2)
        END AS z_score_dod,
        CASE 
            WHEN y.avg_duration_seconds IS NULL THEN NULL
            ELSE ROUND(t.avg_duration_seconds - y.avg_duration_seconds, 1)
        END AS seconds_change_dod,
        
        -- Baseline 2: WoW (semana pasada)
        lw.total_calls AS baseline_wow_total,
        lw.completed_calls AS baseline_wow_completed,
        lw.avg_duration_seconds AS baseline_wow_duration,
        ssw.stddev_duration AS stddev_same_weekday,
        ssw.sample_size AS sample_size_weekday,
        CASE 
            WHEN ssw.stddev_duration IS NULL OR ssw.stddev_duration = 0 THEN NULL
            ELSE ROUND((t.avg_duration_seconds - lw.avg_duration_seconds) / ssw.stddev_duration, 2)
        END AS z_score_wow,
        CASE 
            WHEN lw.avg_duration_seconds IS NULL THEN NULL
            ELSE ROUND(t.avg_duration_seconds - lw.avg_duration_seconds, 1)
        END AS seconds_change_wow,
        
        -- Baseline 3: 30d Avg (mismo día de semana)
        ssw.avg_total_calls AS baseline_30d_total,
        ssw.avg_completed_calls AS baseline_30d_completed,
        ssw.avg_duration AS baseline_30d_duration,
        CASE 
            WHEN ssw.stddev_duration IS NULL OR ssw.stddev_duration = 0 THEN NULL
            ELSE ROUND((t.avg_duration_seconds - ssw.avg_duration) / ssw.stddev_duration, 2)
        END AS z_score_30d,
        CASE 
            WHEN ssw.avg_duration IS NULL THEN NULL
            ELSE ROUND(t.avg_duration_seconds - ssw.avg_duration, 1)
        END AS seconds_change_30d
        
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
        
        -- Tipo de anomalía (consistente entre los 3)
        CASE 
            WHEN COALESCE(z_score_dod, 0) + COALESCE(z_score_wow, 0) + COALESCE(z_score_30d, 0) > 0 
            THEN 'TOO_LONG'
            ELSE 'TOO_SHORT'
        END AS anomaly_type,
        
        -- Severidad Sub-alert 5.1 (DoD) - BIDIRECCIONAL
        CASE
            WHEN current_completed_calls < 30 THEN 'INSUFFICIENT_DATA'
            WHEN baseline_dod_duration IS NULL OR baseline_dod_completed < 30 THEN 'INSUFFICIENT_DATA'
            WHEN stddev_all_days IS NULL OR stddev_all_days = 0 THEN 'INSUFFICIENT_DATA'
            WHEN sample_size_all_days < 10 THEN 'INSUFFICIENT_DATA'
            WHEN ABS(z_score_dod) > 2.5 THEN 'CRITICAL'
            WHEN ABS(z_score_dod) > 2.0 THEN 'WARNING'
            ELSE 'FINE'
        END AS severity_dod,
        
        -- Severidad Sub-alert 5.2 (WoW) - BIDIRECCIONAL
        CASE
            WHEN current_completed_calls < 30 THEN 'INSUFFICIENT_DATA'
            WHEN baseline_wow_duration IS NULL OR baseline_wow_completed < 30 THEN 'INSUFFICIENT_DATA'
            WHEN stddev_same_weekday IS NULL OR stddev_same_weekday = 0 THEN 'INSUFFICIENT_DATA'
            WHEN sample_size_weekday < 3 THEN 'INSUFFICIENT_DATA'
            WHEN ABS(z_score_wow) > 2.5 THEN 'CRITICAL'
            WHEN ABS(z_score_wow) > 2.0 THEN 'WARNING'
            ELSE 'FINE'
        END AS severity_wow,
        
        -- Severidad Sub-alert 5.3 (30d Avg) - BIDIRECCIONAL
        CASE
            WHEN current_completed_calls < 30 THEN 'INSUFFICIENT_DATA'
            WHEN baseline_30d_duration IS NULL THEN 'INSUFFICIENT_DATA'
            WHEN stddev_same_weekday IS NULL OR stddev_same_weekday = 0 THEN 'INSUFFICIENT_DATA'
            WHEN sample_size_weekday < 3 THEN 'INSUFFICIENT_DATA'
            WHEN ABS(z_score_30d) > 2.5 THEN 'CRITICAL'
            WHEN ABS(z_score_30d) > 2.0 THEN 'WARNING'
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
        WHEN main_severity = 'CRITICAL' AND anomaly_type = 'TOO_SHORT' THEN
            CONCAT(
                '🔴 CRITICAL: ', organization_name, ' (', country, ') - DURACIÓN ANORMALMENTE CORTA CONFIRMADA. ',
                'Duración actual: ', CAST(current_avg_duration AS VARCHAR), 's promedio. ',
                '▼ vs Ayer: ', CAST(baseline_dod_duration AS VARCHAR), 's → ', 
                CAST(seconds_change_dod AS VARCHAR), 's. ',
                '▼ vs Semana pasada: ', CAST(baseline_wow_duration AS VARCHAR), 's → ', 
                CAST(seconds_change_wow AS VARCHAR), 's. ',
                '▼ vs Promedio 30d: ', CAST(baseline_30d_duration AS VARCHAR), 's → ', 
                CAST(seconds_change_30d AS VARCHAR), 's. ',
                'ACCIÓN REQUERIDA: Revisar calidad de audio, comportamiento inicial del agente, y tasas de hang-up.'
            )
        
        WHEN main_severity = 'CRITICAL' AND anomaly_type = 'TOO_LONG' THEN
            CONCAT(
                '🔴 CRITICAL: ', organization_name, ' (', country, ') - DURACIÓN ANORMALMENTE LARGA CONFIRMADA. ',
                'Duración actual: ', CAST(current_avg_duration AS VARCHAR), 's promedio. ',
                '▲ vs Ayer: ', CAST(baseline_dod_duration AS VARCHAR), 's → +', 
                CAST(seconds_change_dod AS VARCHAR), 's. ',
                '▲ vs Semana pasada: ', CAST(baseline_wow_duration AS VARCHAR), 's → +', 
                CAST(seconds_change_wow AS VARCHAR), 's. ',
                '▲ vs Promedio 30d: ', CAST(baseline_30d_duration AS VARCHAR), 's → +', 
                CAST(seconds_change_30d AS VARCHAR), 's. ',
                'ACCIÓN REQUERIDA: Revisar posibles loops en el agente, conversaciones sin cierre, o bugs en el flujo.'
            )
        
        WHEN main_severity = 'WARNING' AND anomaly_type = 'TOO_SHORT' THEN
            CONCAT(
                '🟠 WARNING: ', organization_name, ' (', country, ') - Duración más corta en todas las comparaciones. ',
                'Duración actual: ', CAST(current_avg_duration AS VARCHAR), 's. ',
                'Comparaciones: Ayer ', CAST(baseline_dod_duration AS VARCHAR), 's (', CAST(seconds_change_dod AS VARCHAR), 's) | ',
                'Semana pasada ', CAST(baseline_wow_duration AS VARCHAR), 's (', CAST(seconds_change_wow AS VARCHAR), 's) | ',
                'Promedio 30d ', CAST(baseline_30d_duration AS VARCHAR), 's (', CAST(seconds_change_30d AS VARCHAR), 's). ',
                'Monitorear de cerca.'
            )
        
        WHEN main_severity = 'WARNING' AND anomaly_type = 'TOO_LONG' THEN
            CONCAT(
                '🟠 WARNING: ', organization_name, ' (', country, ') - Duración más larga en todas las comparaciones. ',
                'Duración actual: ', CAST(current_avg_duration AS VARCHAR), 's. ',
                'Comparaciones: Ayer ', CAST(baseline_dod_duration AS VARCHAR), 's (+', CAST(seconds_change_dod AS VARCHAR), 's) | ',
                'Semana pasada ', CAST(baseline_wow_duration AS VARCHAR), 's (+', CAST(seconds_change_wow AS VARCHAR), 's) | ',
                'Promedio 30d ', CAST(baseline_30d_duration AS VARCHAR), 's (+', CAST(seconds_change_30d AS VARCHAR), 's). ',
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
    GREATEST(ABS(COALESCE(z_score_dod, 0)), ABS(COALESCE(z_score_wow, 0)), ABS(COALESCE(z_score_30d, 0))) DESC
-- ==============================================================================
-- Alert 4: Short Call Rate Spike - MAIN ALERT
-- ==============================================================================
-- Este es el ALERT PRINCIPAL que solo se dispara cuando los 3 sub-alerts
-- están en WARNING o CRITICAL simultáneamente.
-- 
-- Métrica: short_call_rate = short_calls / completed_calls
-- (De las llamadas completadas, ¿cuántas fueron demasiado cortas?)
--
-- Dirección: HIGHER is bad (más llamadas cortas = problema)
--
-- Sub-alerts:
--   4.1: vs DoD (ayer mismo momento) - usa stddev_all_days
--   4.2: vs WoW (semana pasada mismo día/momento) - usa stddev_same_weekday
--   4.3: vs 30d Avg (promedio 30 días mismo weekday) - usa stddev_same_weekday
--
-- Esta alerta detecta SPIKES EN LLAMADAS CORTAS.
-- Posibles causas: problemas técnicos, cambios en script, issues de audio.
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
        SUM(CASE WHEN call_classification = 'good_calls' THEN 1 ELSE 0 END) AS good_calls,
        SUM(CASE WHEN call_classification = 'short_calls' THEN 1 ELSE 0 END) AS short_calls,
        
        ROUND(
            CAST(SUM(CASE WHEN call_classification = 'short_calls' THEN 1 ELSE 0 END) AS FLOAT) / 
            NULLIF(SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') 
                            THEN 1 ELSE 0 END), 0),
            4
        ) AS short_call_rate
        
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
                 THEN 1 ELSE 0 END) AS completed_calls,
        SUM(CASE WHEN call_classification = 'short_calls' THEN 1 ELSE 0 END) AS short_calls,
        ROUND(
            CAST(SUM(CASE WHEN call_classification = 'short_calls' THEN 1 ELSE 0 END) AS FLOAT) / 
            NULLIF(SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') 
                            THEN 1 ELSE 0 END), 0),
            4
        ) AS short_call_rate
        
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
                 THEN 1 ELSE 0 END) AS completed_calls,
        SUM(CASE WHEN call_classification = 'short_calls' THEN 1 ELSE 0 END) AS short_calls,
        ROUND(
            CAST(SUM(CASE WHEN call_classification = 'short_calls' THEN 1 ELSE 0 END) AS FLOAT) / 
            NULLIF(SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') 
                            THEN 1 ELSE 0 END), 0),
            4
        ) AS short_call_rate
        
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
        ROUND(STDDEV(daily_short_call_rate), 4) AS stddev_short_call_rate
    FROM (
        SELECT
            d.organization_code,
            d.country,
            d.created_date,
            ROUND(
                CAST(SUM(CASE WHEN d.call_classification = 'short_calls' THEN 1 ELSE 0 END) AS FLOAT) / 
                NULLIF(SUM(CASE WHEN d.call_classification IN ('good_calls', 'short_calls', 'completed') 
                                THEN 1 ELSE 0 END), 0),
                4
            ) AS daily_short_call_rate
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
        HAVING SUM(CASE WHEN d.call_classification IN ('good_calls', 'short_calls', 'completed') 
                        THEN 1 ELSE 0 END) >= 30
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
        ROUND(AVG(daily_short_calls), 0) AS avg_short_calls,
        ROUND(AVG(daily_short_call_rate), 4) AS avg_short_call_rate,
        ROUND(STDDEV(daily_short_call_rate), 4) AS stddev_short_call_rate
    FROM (
        SELECT
            d.organization_code,
            d.country,
            d.created_date,
            COUNT(*) AS daily_total_calls,
            SUM(CASE WHEN d.call_classification IN ('good_calls', 'short_calls', 'completed') 
                     THEN 1 ELSE 0 END) AS daily_completed_calls,
            SUM(CASE WHEN d.call_classification = 'short_calls' THEN 1 ELSE 0 END) AS daily_short_calls,
            ROUND(
                CAST(SUM(CASE WHEN d.call_classification = 'short_calls' THEN 1 ELSE 0 END) AS FLOAT) / 
                NULLIF(SUM(CASE WHEN d.call_classification IN ('good_calls', 'short_calls', 'completed') 
                                THEN 1 ELSE 0 END), 0),
                4
            ) AS daily_short_call_rate
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
        HAVING SUM(CASE WHEN d.call_classification IN ('good_calls', 'short_calls', 'completed') 
                        THEN 1 ELSE 0 END) >= 30
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
        t.good_calls AS current_good_calls,
        t.short_calls AS current_short_calls,
        t.short_call_rate AS current_short_call_rate,
        
        -- Baseline 1: DoD (ayer)
        y.total_calls AS baseline_dod_total,
        y.completed_calls AS baseline_dod_completed,
        y.short_calls AS baseline_dod_short,
        y.short_call_rate AS baseline_dod_rate,
        sad.stddev_short_call_rate AS stddev_all_days,
        sad.sample_size AS sample_size_all_days,
        CASE 
            WHEN sad.stddev_short_call_rate IS NULL OR sad.stddev_short_call_rate = 0 THEN NULL
            ELSE ROUND((t.short_call_rate - y.short_call_rate) / sad.stddev_short_call_rate, 2)
        END AS z_score_dod,
        CASE 
            WHEN y.short_call_rate IS NULL THEN NULL
            ELSE ROUND((t.short_call_rate - y.short_call_rate) * 100, 1)
        END AS pp_change_dod,
        
        -- Baseline 2: WoW (semana pasada)
        lw.total_calls AS baseline_wow_total,
        lw.completed_calls AS baseline_wow_completed,
        lw.short_calls AS baseline_wow_short,
        lw.short_call_rate AS baseline_wow_rate,
        ssw.stddev_short_call_rate AS stddev_same_weekday,
        ssw.sample_size AS sample_size_weekday,
        CASE 
            WHEN ssw.stddev_short_call_rate IS NULL OR ssw.stddev_short_call_rate = 0 THEN NULL
            ELSE ROUND((t.short_call_rate - lw.short_call_rate) / ssw.stddev_short_call_rate, 2)
        END AS z_score_wow,
        CASE 
            WHEN lw.short_call_rate IS NULL THEN NULL
            ELSE ROUND((t.short_call_rate - lw.short_call_rate) * 100, 1)
        END AS pp_change_wow,
        
        -- Baseline 3: 30d Avg (mismo día de semana)
        ssw.avg_total_calls AS baseline_30d_total,
        ssw.avg_completed_calls AS baseline_30d_completed,
        ssw.avg_short_calls AS baseline_30d_short,
        ssw.avg_short_call_rate AS baseline_30d_rate,
        CASE 
            WHEN ssw.stddev_short_call_rate IS NULL OR ssw.stddev_short_call_rate = 0 THEN NULL
            ELSE ROUND((t.short_call_rate - ssw.avg_short_call_rate) / ssw.stddev_short_call_rate, 2)
        END AS z_score_30d,
        CASE 
            WHEN ssw.avg_short_call_rate IS NULL THEN NULL
            ELSE ROUND((t.short_call_rate - ssw.avg_short_call_rate) * 100, 1)
        END AS pp_change_30d
        
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
        
        -- Severidad Sub-alert 4.1 (DoD) - HIGHER is bad
        CASE
            WHEN current_completed_calls < 30 THEN 'INSUFFICIENT_DATA'
            WHEN baseline_dod_rate IS NULL OR baseline_dod_completed < 30 THEN 'INSUFFICIENT_DATA'
            WHEN stddev_all_days IS NULL OR stddev_all_days = 0 THEN 'INSUFFICIENT_DATA'
            WHEN sample_size_all_days < 10 THEN 'INSUFFICIENT_DATA'
            WHEN z_score_dod > 2.5 THEN 'CRITICAL'
            WHEN z_score_dod > 2.0 THEN 'WARNING'
            ELSE 'FINE'
        END AS severity_dod,
        
        -- Severidad Sub-alert 4.2 (WoW) - HIGHER is bad
        CASE
            WHEN current_completed_calls < 30 THEN 'INSUFFICIENT_DATA'
            WHEN baseline_wow_rate IS NULL OR baseline_wow_completed < 30 THEN 'INSUFFICIENT_DATA'
            WHEN stddev_same_weekday IS NULL OR stddev_same_weekday = 0 THEN 'INSUFFICIENT_DATA'
            WHEN sample_size_weekday < 3 THEN 'INSUFFICIENT_DATA'
            WHEN z_score_wow > 2.5 THEN 'CRITICAL'
            WHEN z_score_wow > 2.0 THEN 'WARNING'
            ELSE 'FINE'
        END AS severity_wow,
        
        -- Severidad Sub-alert 4.3 (30d Avg) - HIGHER is bad
        CASE
            WHEN current_completed_calls < 30 THEN 'INSUFFICIENT_DATA'
            WHEN baseline_30d_rate IS NULL THEN 'INSUFFICIENT_DATA'
            WHEN stddev_same_weekday IS NULL OR stddev_same_weekday = 0 THEN 'INSUFFICIENT_DATA'
            WHEN sample_size_weekday < 3 THEN 'INSUFFICIENT_DATA'
            WHEN z_score_30d > 2.5 THEN 'CRITICAL'
            WHEN z_score_30d > 2.0 THEN 'WARNING'
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
                '🔴 CRITICAL: ', organization_name, ' (', country, ') - SPIKE DE LLAMADAS CORTAS CONFIRMADO. ',
                'Short call rate actual: ', CAST(ROUND(current_short_call_rate * 100, 1) AS VARCHAR), '% (',
                CAST(current_short_calls AS VARCHAR), '/', CAST(current_completed_calls AS VARCHAR), ' short/completed). ',
                '▲ vs Ayer: ', CAST(ROUND(baseline_dod_rate * 100, 1) AS VARCHAR), '% (',
                CAST(baseline_dod_short AS VARCHAR), '/', CAST(baseline_dod_completed AS VARCHAR), ') → +', 
                CAST(pp_change_dod AS VARCHAR), ' pp. ',
                '▲ vs Semana pasada: ', CAST(ROUND(baseline_wow_rate * 100, 1) AS VARCHAR), '% (',
                CAST(baseline_wow_short AS VARCHAR), '/', CAST(baseline_wow_completed AS VARCHAR), ') → +', 
                CAST(pp_change_wow AS VARCHAR), ' pp. ',
                '▲ vs Promedio 30d: ', CAST(ROUND(baseline_30d_rate * 100, 1) AS VARCHAR), '% (~',
                CAST(baseline_30d_short AS VARCHAR), '/', CAST(baseline_30d_completed AS VARCHAR), ') → +', 
                CAST(pp_change_30d AS VARCHAR), ' pp. ',
                'ACCIÓN REQUERIDA: Revisar calidad de audio, script inicial, y comportamiento del agente.'
            )
        
        WHEN main_severity = 'WARNING' THEN
            CONCAT(
                '🟠 WARNING: ', organization_name, ' (', country, ') - Short call rate elevado en todas las comparaciones. ',
                'Rate actual: ', CAST(ROUND(current_short_call_rate * 100, 1) AS VARCHAR), '% (',
                CAST(current_short_calls AS VARCHAR), '/', CAST(current_completed_calls AS VARCHAR), '). ',
                'Comparaciones: Ayer ', CAST(ROUND(baseline_dod_rate * 100, 1) AS VARCHAR), '% (+', CAST(pp_change_dod AS VARCHAR), ' pp) | ',
                'Semana pasada ', CAST(ROUND(baseline_wow_rate * 100, 1) AS VARCHAR), '% (+', CAST(pp_change_wow AS VARCHAR), ' pp) | ',
                'Promedio 30d ', CAST(ROUND(baseline_30d_rate * 100, 1) AS VARCHAR), '% (+', CAST(pp_change_30d AS VARCHAR), ' pp). ',
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
    GREATEST(COALESCE(z_score_dod, 0), COALESCE(z_score_wow, 0), COALESCE(z_score_30d, 0)) DESC
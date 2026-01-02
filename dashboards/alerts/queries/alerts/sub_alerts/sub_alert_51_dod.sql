-- ==============================================================================
-- Alert 5.1: Call Duration Anomaly - vs Yesterday (Same Moment)
-- ==============================================================================
-- Compara la duración promedio de llamadas de HOY hasta el momento actual vs 
-- AYER hasta el mismo momento.
-- 
-- Métrica: avg_call_duration_seconds (promedio de segundos por llamada completada)
--
-- Granularidad: Diaria acumulada (hasta timestamp actual)
-- Dirección: BIDIRECCIONAL (|Z| > 2.0 WARNING, |Z| > 2.5 CRITICAL)
--            - Duración muy CORTA puede indicar: problemas de audio, hang-ups
--            - Duración muy LARGA puede indicar: loops, bugs en el agente
--
-- Z-Score usa stddev de TODOS los días (últimos 30d) porque DoD compara
-- días consecutivos sin importar el día de semana.
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
        
        COUNT(*) AS total_calls,
        SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') 
                 THEN 1 ELSE 0 END) AS completed_calls,
        SUM(call_duration_seconds) AS total_duration_seconds,
        
        -- Average duration
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

-- Stddev de duración de TODOS los días (últimos 30d) - para comparación DoD
stddev_all_days AS (
    SELECT
        organization_code,
        country,
        COUNT(DISTINCT created_date) AS sample_size,
        ROUND(AVG(daily_avg_duration), 2) AS avg_duration,
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

alert_calculation AS (
    SELECT
        t.organization_code,
        t.organization_name,
        t.country,
        
        -- Métricas actuales
        t.total_calls AS current_total_calls,
        t.completed_calls AS current_completed_calls,
        t.avg_duration_seconds AS current_avg_duration,
        
        -- Baseline (ayer)
        y.total_calls AS baseline_total_calls,
        y.completed_calls AS baseline_completed_calls,
        y.avg_duration_seconds AS baseline_avg_duration,
        
        -- Stddev de todos los días
        s.stddev_duration AS stddev_all_days,
        s.sample_size AS sample_size_30d,
        
        -- Diferencia en segundos
        CASE 
            WHEN y.avg_duration_seconds IS NULL THEN NULL
            ELSE ROUND(t.avg_duration_seconds - y.avg_duration_seconds, 1)
        END AS seconds_change,
        
        -- Cambio porcentual
        CASE 
            WHEN y.avg_duration_seconds IS NULL OR y.avg_duration_seconds = 0 THEN NULL
            ELSE ROUND((t.avg_duration_seconds - y.avg_duration_seconds) / y.avg_duration_seconds * 100, 1)
        END AS pct_change,
        
        -- Z-Score usando stddev de TODOS los días
        CASE 
            WHEN s.stddev_duration IS NULL OR s.stddev_duration = 0 THEN NULL
            ELSE ROUND((t.avg_duration_seconds - y.avg_duration_seconds) / s.stddev_duration, 2)
        END AS z_score
        
    FROM today_metrics t
    LEFT JOIN yesterday_metrics y
        ON t.organization_code = y.organization_code
        AND t.country = y.country
    LEFT JOIN stddev_all_days s
        ON t.organization_code = s.organization_code
        AND t.country = s.country
),

severity_calculation AS (
    SELECT
        *,
        
        -- Tipo de anomalía
        CASE 
            WHEN z_score > 0 THEN 'TOO_LONG'
            WHEN z_score < 0 THEN 'TOO_SHORT'
            ELSE 'NORMAL'
        END AS anomaly_type,
        
        CASE
            -- Datos insuficientes
            WHEN current_completed_calls < 30 THEN 'INSUFFICIENT_DATA'
            WHEN baseline_avg_duration IS NULL THEN 'INSUFFICIENT_DATA'
            WHEN baseline_completed_calls < 30 THEN 'INSUFFICIENT_DATA'
            WHEN stddev_all_days IS NULL OR stddev_all_days = 0 THEN 'INSUFFICIENT_DATA'
            WHEN sample_size_30d < 10 THEN 'INSUFFICIENT_DATA'
            
            -- CRITICAL: |Z| > 2.5 (bidireccional)
            WHEN ABS(z_score) > 2.5 THEN 'CRITICAL'
            
            -- WARNING: |Z| > 2.0 (bidireccional)
            WHEN ABS(z_score) > 2.0 THEN 'WARNING'
            
            ELSE 'FINE'
        END AS alert_severity,
        
        CASE
            WHEN current_completed_calls < 30 THEN 'FEW_COMPLETED_TODAY'
            WHEN baseline_avg_duration IS NULL THEN 'NO_BASELINE'
            WHEN baseline_completed_calls < 30 THEN 'FEW_COMPLETED_BASELINE'
            WHEN stddev_all_days IS NULL OR stddev_all_days = 0 THEN 'NO_VARIANCE'
            WHEN sample_size_30d < 10 THEN 'FEW_SAMPLES'
            ELSE 'OK'
        END AS insufficient_reason
        
    FROM alert_calculation
)

SELECT
    CASE
        WHEN alert_severity = 'CRITICAL' AND anomaly_type = 'TOO_SHORT' THEN
            CONCAT(
                '🔴 CRITICAL [vs Ayer]: ', organization_name, ' (', country, '). ',
                'Duración ANORMALMENTE CORTA. Hoy: ', CAST(current_avg_duration AS VARCHAR), 's promedio. ',
                'Ayer a esta hora: ', CAST(baseline_avg_duration AS VARCHAR), 's. ',
                'Diferencia: ', CAST(seconds_change AS VARCHAR), 's (', CAST(pct_change AS VARCHAR), '%). ',
                'Posibles causas: problemas de audio, usuarios colgando rápidamente.'
            )
        WHEN alert_severity = 'CRITICAL' AND anomaly_type = 'TOO_LONG' THEN
            CONCAT(
                '🔴 CRITICAL [vs Ayer]: ', organization_name, ' (', country, '). ',
                'Duración ANORMALMENTE LARGA. Hoy: ', CAST(current_avg_duration AS VARCHAR), 's promedio. ',
                'Ayer a esta hora: ', CAST(baseline_avg_duration AS VARCHAR), 's. ',
                'Diferencia: +', CAST(seconds_change AS VARCHAR), 's (+', CAST(pct_change AS VARCHAR), '%). ',
                'Posibles causas: loops en el agente, conversaciones sin cierre.'
            )
        WHEN alert_severity = 'WARNING' AND anomaly_type = 'TOO_SHORT' THEN
            CONCAT(
                '🟠 WARNING [vs Ayer]: ', organization_name, ' (', country, '). ',
                'Duración más corta de lo normal. Hoy: ', CAST(current_avg_duration AS VARCHAR), 's promedio. ',
                'Ayer a esta hora: ', CAST(baseline_avg_duration AS VARCHAR), 's. ',
                'Diferencia: ', CAST(seconds_change AS VARCHAR), 's (', CAST(pct_change AS VARCHAR), '%).'
            )
        WHEN alert_severity = 'WARNING' AND anomaly_type = 'TOO_LONG' THEN
            CONCAT(
                '🟠 WARNING [vs Ayer]: ', organization_name, ' (', country, '). ',
                'Duración más larga de lo normal. Hoy: ', CAST(current_avg_duration AS VARCHAR), 's promedio. ',
                'Ayer a esta hora: ', CAST(baseline_avg_duration AS VARCHAR), 's. ',
                'Diferencia: +', CAST(seconds_change AS VARCHAR), 's (+', CAST(pct_change AS VARCHAR), '%).'
            )
        WHEN alert_severity = 'INSUFFICIENT_DATA' THEN
            CONCAT(
                '⚪ DATOS INSUFICIENTES [vs Ayer]: ', organization_name, ' (', country, '). ',
                CASE insufficient_reason
                    WHEN 'FEW_COMPLETED_TODAY' THEN 
                        CONCAT('Hoy solo hay ', CAST(current_completed_calls AS VARCHAR), 
                               ' llamadas completadas. Se requieren mínimo 30.')
                    WHEN 'NO_BASELINE' THEN 
                        'No hay datos de ayer para comparar.'
                    WHEN 'FEW_COMPLETED_BASELINE' THEN 
                        CONCAT('Ayer solo hubo ', CAST(COALESCE(baseline_completed_calls, 0) AS VARCHAR), 
                               ' llamadas completadas. Se requieren mínimo 30.')
                    WHEN 'NO_VARIANCE' THEN 
                        'No hay suficiente variabilidad histórica para calcular z-score.'
                    WHEN 'FEW_SAMPLES' THEN 
                        CONCAT('Solo hay ', CAST(sample_size_30d AS VARCHAR), 
                               ' días en el historial. Se requieren mínimo 10.')
                    ELSE 'Datos insuficientes para generar alerta confiable.'
                END
            )
        WHEN alert_severity = 'FINE' THEN
            CONCAT(
                '🟢 FINE [vs Ayer]: ', organization_name, ' (', country, '). ',
                'Duración normal. Hoy: ', CAST(current_avg_duration AS VARCHAR), 's promedio. ',
                'Ayer a esta hora: ', CAST(baseline_avg_duration AS VARCHAR), 's. ',
                CASE 
                    WHEN ABS(pct_change) < 5 THEN 'En línea con el comportamiento histórico.'
                    ELSE CONCAT('Variación de ', CAST(pct_change AS VARCHAR), '%, dentro de rangos aceptables.')
                END
            )
        ELSE NULL
    END AS alert_message

FROM severity_calculation
ORDER BY 
    CASE alert_severity 
        WHEN 'CRITICAL' THEN 1 
        WHEN 'WARNING' THEN 2 
        WHEN 'INSUFFICIENT_DATA' THEN 3
        WHEN 'FINE' THEN 4
        ELSE 5 
    END,
    ABS(z_score) DESC
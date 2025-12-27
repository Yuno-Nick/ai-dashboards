-- ==============================================================================
-- Alert 1.1: Volume Drop - vs Yesterday (Same Moment)
-- ==============================================================================
-- Compara el volumen de llamadas de HOY hasta el momento actual vs 
-- AYER hasta el mismo momento.
-- 
-- Métrica: total_calls (volumen de llamadas)
-- Granularidad: Diaria acumulada (hasta timestamp actual)
-- Dirección: Lower is bad (Z < -2.0 WARNING, Z < -2.5 CRITICAL)
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
                 THEN 1 ELSE 0 END) AS completed_calls,
        SUM(CASE WHEN call_classification = 'failed' THEN 1 ELSE 0 END) AS failed_calls
        
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

-- Stddev de TODOS los días (últimos 30d) - para comparación DoD
stddev_all_days AS (
    SELECT
        organization_code,
        country,
        COUNT(DISTINCT created_date) AS sample_size,
        ROUND(AVG(daily_total_calls), 0) AS avg_total_calls,
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

alert_calculation AS (
    SELECT
        t.organization_code,
        t.organization_name,
        t.country,
        
        -- Métricas actuales
        t.total_calls AS current_total_calls,
        t.completed_calls AS current_completed_calls,
        t.failed_calls AS current_failed_calls,
        
        -- Baseline (ayer)
        y.total_calls AS baseline_total_calls,
        y.completed_calls AS baseline_completed_calls,
        y.failed_calls AS baseline_failed_calls,
        
        -- Stddev de todos los días
        s.stddev_total_calls AS stddev_all_days,
        s.sample_size AS sample_size_30d,
        
        -- Diferencia absoluta
        t.total_calls - COALESCE(y.total_calls, 0) AS absolute_change,
        
        -- Cambio porcentual
        CASE 
            WHEN y.total_calls IS NULL OR y.total_calls = 0 THEN NULL
            ELSE ROUND((CAST(t.total_calls AS FLOAT) - y.total_calls) / y.total_calls * 100, 1)
        END AS pct_change,
        
        -- Z-Score usando stddev de TODOS los días
        CASE 
            WHEN s.stddev_total_calls IS NULL OR s.stddev_total_calls = 0 THEN NULL
            ELSE ROUND((CAST(t.total_calls AS FLOAT) - y.total_calls) / s.stddev_total_calls, 2)
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
        
        CASE
            -- Datos insuficientes
            WHEN baseline_total_calls IS NULL THEN 'INSUFFICIENT_DATA'
            WHEN stddev_all_days IS NULL OR stddev_all_days = 0 THEN 'INSUFFICIENT_DATA'
            WHEN sample_size_30d < 10 THEN 'INSUFFICIENT_DATA'
            
            -- CRITICAL: Z < -2.5
            WHEN z_score < -2.5 THEN 'CRITICAL'
            
            -- WARNING: Z < -2.0
            WHEN z_score < -2.0 THEN 'WARNING'
            
            ELSE 'FINE'
        END AS alert_severity,
        
        -- Razón de datos insuficientes
        CASE
            WHEN baseline_total_calls IS NULL THEN 'NO_BASELINE'
            WHEN stddev_all_days IS NULL OR stddev_all_days = 0 THEN 'NO_VARIANCE'
            WHEN sample_size_30d < 10 THEN 'FEW_SAMPLES'
            ELSE 'OK'
        END AS insufficient_reason
        
    FROM alert_calculation
)

SELECT
    CASE
        WHEN alert_severity = 'CRITICAL' THEN
            CONCAT(
                '🔴 CRITICAL [vs Ayer]: ', organization_name, ' (', country, '). ',
                'Volumen hoy: ', CAST(current_total_calls AS VARCHAR), ' llamadas. ',
                'Ayer a esta hora: ', CAST(baseline_total_calls AS VARCHAR), ' llamadas. ',
                'Caída de ', CAST(ABS(absolute_change) AS VARCHAR), ' llamadas (',
                CAST(ABS(pct_change) AS VARCHAR), '%). ',
                'Variabilidad histórica: ±', CAST(ROUND(stddev_all_days, 0) AS VARCHAR), ' llamadas/día.'
            )
        WHEN alert_severity = 'WARNING' THEN
            CONCAT(
                '🟠 WARNING [vs Ayer]: ', organization_name, ' (', country, '). ',
                'Volumen hoy: ', CAST(current_total_calls AS VARCHAR), ' llamadas. ',
                'Ayer a esta hora: ', CAST(baseline_total_calls AS VARCHAR), ' llamadas. ',
                'Caída de ', CAST(ABS(absolute_change) AS VARCHAR), ' llamadas (',
                CAST(ABS(pct_change) AS VARCHAR), '%).'
            )
        WHEN alert_severity = 'INSUFFICIENT_DATA' THEN
            CONCAT(
                '⚪ DATOS INSUFICIENTES [vs Ayer]: ', organization_name, ' (', country, '). ',
                CASE insufficient_reason
                    WHEN 'NO_BASELINE' THEN 
                        'No hay datos de ayer para comparar.'
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
                'Volumen normal. Hoy: ', CAST(current_total_calls AS VARCHAR), ' llamadas. ',
                'Ayer a esta hora: ', CAST(baseline_total_calls AS VARCHAR), ' llamadas. ',
                CASE 
                    WHEN pct_change > 10 THEN CONCAT('Aumento de ', CAST(absolute_change AS VARCHAR), ' llamadas (+', CAST(pct_change AS VARCHAR), '%).')
                    WHEN pct_change < -10 THEN CONCAT('Disminución de ', CAST(ABS(absolute_change) AS VARCHAR), ' llamadas (', CAST(pct_change AS VARCHAR), '%), dentro de la variación normal.')
                    ELSE 'Estable respecto a ayer.'
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
    z_score ASC
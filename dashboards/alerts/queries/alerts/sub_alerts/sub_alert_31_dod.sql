-- ==============================================================================
-- Alert 3.1: Quality Rate Drop - vs Yesterday (Same Moment)
-- ==============================================================================
-- Compara el quality_rate de HOY hasta el momento actual vs 
-- AYER hasta el mismo momento.
-- 
-- Métrica: quality_rate = good_calls / completed_calls
-- (De las llamadas completadas, ¿cuántas fueron conversaciones efectivas?)
--
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
        SUM(CASE WHEN call_classification = 'good_calls' THEN 1 ELSE 0 END) AS good_calls,
        SUM(CASE WHEN call_classification = 'short_calls' THEN 1 ELSE 0 END) AS short_calls,
        
        -- Quality rate: good_calls / completed_calls
        ROUND(
            CAST(SUM(CASE WHEN call_classification = 'good_calls' THEN 1 ELSE 0 END) AS FLOAT) / 
            NULLIF(SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') 
                            THEN 1 ELSE 0 END), 0),
            4
        ) AS quality_rate
        
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
        SUM(CASE WHEN call_classification = 'good_calls' THEN 1 ELSE 0 END) AS good_calls,
        
        ROUND(
            CAST(SUM(CASE WHEN call_classification = 'good_calls' THEN 1 ELSE 0 END) AS FLOAT) / 
            NULLIF(SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') 
                            THEN 1 ELSE 0 END), 0),
            4
        ) AS quality_rate
        
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

-- Stddev de quality_rate de TODOS los días (últimos 30d) - para comparación DoD
stddev_all_days AS (
    SELECT
        organization_code,
        country,
        COUNT(DISTINCT created_date) AS sample_size,
        ROUND(AVG(daily_quality_rate), 4) AS avg_quality_rate,
        ROUND(STDDEV(daily_quality_rate), 4) AS stddev_quality_rate
    FROM (
        SELECT
            d.organization_code,
            d.country,
            d.created_date,
            ROUND(
                CAST(SUM(CASE WHEN d.call_classification = 'good_calls' THEN 1 ELSE 0 END) AS FLOAT) / 
                NULLIF(SUM(CASE WHEN d.call_classification IN ('good_calls', 'short_calls', 'completed') 
                                THEN 1 ELSE 0 END), 0),
                4
            ) AS daily_quality_rate
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
                        THEN 1 ELSE 0 END) >= 30  -- Mínimo 30 completed para rate confiable
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
        t.good_calls AS current_good_calls,
        t.quality_rate AS current_quality_rate,
        
        -- Baseline (ayer)
        y.total_calls AS baseline_total_calls,
        y.completed_calls AS baseline_completed_calls,
        y.good_calls AS baseline_good_calls,
        y.quality_rate AS baseline_quality_rate,
        
        -- Stddev de todos los días
        s.stddev_quality_rate AS stddev_all_days,
        s.sample_size AS sample_size_30d,
        
        -- Diferencia en puntos porcentuales
        CASE 
            WHEN y.quality_rate IS NULL THEN NULL
            ELSE ROUND((t.quality_rate - y.quality_rate) * 100, 1)
        END AS pp_change,
        
        -- Z-Score usando stddev de TODOS los días
        CASE 
            WHEN s.stddev_quality_rate IS NULL OR s.stddev_quality_rate = 0 THEN NULL
            ELSE ROUND((t.quality_rate - y.quality_rate) / s.stddev_quality_rate, 2)
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
            WHEN current_completed_calls < 30 THEN 'INSUFFICIENT_DATA'
            WHEN baseline_quality_rate IS NULL THEN 'INSUFFICIENT_DATA'
            WHEN baseline_completed_calls < 30 THEN 'INSUFFICIENT_DATA'
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
            WHEN current_completed_calls < 30 THEN 'FEW_COMPLETED_TODAY'
            WHEN baseline_quality_rate IS NULL THEN 'NO_BASELINE'
            WHEN baseline_completed_calls < 30 THEN 'FEW_COMPLETED_BASELINE'
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
                'Quality rate hoy: ', CAST(ROUND(current_quality_rate * 100, 1) AS VARCHAR), '% (',
                CAST(current_good_calls AS VARCHAR), '/', CAST(current_completed_calls AS VARCHAR), ' good/completed). ',
                'Ayer a esta hora: ', CAST(ROUND(baseline_quality_rate * 100, 1) AS VARCHAR), '% (',
                CAST(baseline_good_calls AS VARCHAR), '/', CAST(baseline_completed_calls AS VARCHAR), ' good/completed). ',
                'Caída de ', CAST(ABS(pp_change) AS VARCHAR), ' pp.'
            )
        WHEN alert_severity = 'WARNING' THEN
            CONCAT(
                '🟠 WARNING [vs Ayer]: ', organization_name, ' (', country, '). ',
                'Quality rate hoy: ', CAST(ROUND(current_quality_rate * 100, 1) AS VARCHAR), '% (',
                CAST(current_good_calls AS VARCHAR), '/', CAST(current_completed_calls AS VARCHAR), ' good/completed). ',
                'Ayer a esta hora: ', CAST(ROUND(baseline_quality_rate * 100, 1) AS VARCHAR), '% (',
                CAST(baseline_good_calls AS VARCHAR), '/', CAST(baseline_completed_calls AS VARCHAR), ' good/completed). ',
                'Caída de ', CAST(ABS(pp_change) AS VARCHAR), ' pp.'
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
                'Quality rate normal. Hoy: ', CAST(ROUND(current_quality_rate * 100, 1) AS VARCHAR), '% (',
                CAST(current_good_calls AS VARCHAR), '/', CAST(current_completed_calls AS VARCHAR), ' good/completed). ',
                'Ayer a esta hora: ', CAST(ROUND(baseline_quality_rate * 100, 1) AS VARCHAR), '% (',
                CAST(baseline_good_calls AS VARCHAR), '/', CAST(baseline_completed_calls AS VARCHAR), ' good/completed). ',
                CASE 
                    WHEN pp_change >= 2 THEN CONCAT('Rendimiento superior (+', CAST(pp_change AS VARCHAR), ' pp).')
                    WHEN pp_change <= -2 THEN CONCAT('Ligeramente por debajo (', CAST(pp_change AS VARCHAR), ' pp), dentro de rangos aceptables.')
                    ELSE 'En línea con el comportamiento histórico.'
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
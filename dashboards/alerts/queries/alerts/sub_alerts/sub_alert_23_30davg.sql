-- ==============================================================================
-- Alert 2.3: Volume Drop - vs 30d Same Weekday Average (SAME MOMENT)
-- ==============================================================================
-- Compara el volumen de llamadas de HOY hasta el momento actual vs 
-- EL PROMEDIO DE LOS ÚLTIMOS 30 DÍAS DEL MISMO DÍA DE SEMANA HASTA LA MISMA HORA/MINUTO
-- 
-- Métrica: total_calls (volumen de llamadas)
-- Granularidad: Diaria acumulada (hasta timestamp actual)
-- Dirección: Lower is bad (Z < -2.0 WARNING, Z < -2.5 CRITICAL)
--
-- Z-Score usa stddev del MISMO DÍA DE SEMANA porque comparamos
-- contra el promedio de Viernes históricos, Lunes históricos, etc.
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
    GROUP BY 
        organization_code, 
        organization_name, 
        country
),

-- Baseline 30d: Promedio y Stddev del MISMO DÍA DE SEMANA hasta la MISMA HORA/MINUTO
baseline_30d_same_weekday AS (
    SELECT
        organization_code,
        country,
        
        COUNT(DISTINCT created_date) AS sample_size,
        ROUND(AVG(total_calls), 0) AS avg_total_calls,
        ROUND(STDDEV(total_calls), 2) AS stddev_total_calls,
        ROUND(AVG(completed_calls), 0) AS avg_completed_calls
        
    FROM (
        SELECT
            d.organization_code,
            d.country,
            d.created_date,
            
            COUNT(*) AS total_calls,
            SUM(CASE WHEN d.call_classification IN ('good_calls', 'short_calls', 'completed') 
                     THEN 1 ELSE 0 END) AS completed_calls
            
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
        GROUP BY 
            d.organization_code, 
            d.country, 
            d.created_date
    ) daily_stats
    GROUP BY 
        organization_code, 
        country
),

alert_calculation AS (
    SELECT
        t.organization_code,
        t.organization_name,
        t.country,
        t.day_of_week,
        
        -- Métricas actuales
        t.total_calls AS current_total_calls,
        t.completed_calls AS current_completed_calls,
        t.failed_calls AS current_failed_calls,
        
        -- Baseline de 30 días (mismo día de semana)
        b.avg_total_calls AS baseline_avg_total_calls,
        b.stddev_total_calls AS baseline_stddev,
        b.sample_size AS baseline_sample_size,
        b.avg_completed_calls AS baseline_avg_completed_calls,
        
        -- Diferencia absoluta
        t.total_calls - COALESCE(b.avg_total_calls, 0) AS absolute_change,
        
        -- Cambio porcentual
        CASE 
            WHEN b.avg_total_calls IS NULL OR b.avg_total_calls = 0 THEN NULL
            ELSE ROUND((CAST(t.total_calls AS FLOAT) - b.avg_total_calls) / b.avg_total_calls * 100, 1)
        END AS pct_change,
        
        -- Z-Score usando stddev del MISMO DÍA DE SEMANA
        CASE 
            WHEN b.stddev_total_calls IS NULL OR b.stddev_total_calls = 0 THEN NULL
            ELSE ROUND((CAST(t.total_calls AS FLOAT) - b.avg_total_calls) / b.stddev_total_calls, 2)
        END AS z_score
        
    FROM today_metrics t
    LEFT JOIN baseline_30d_same_weekday b
        ON t.organization_code = b.organization_code
        AND t.country = b.country
),

severity_calculation AS (
    SELECT
        *,
        
        -- Nombre del día para contexto
        CASE day_of_week
            WHEN 1 THEN 'Domingo'
            WHEN 2 THEN 'Lunes'
            WHEN 3 THEN 'Martes'
            WHEN 4 THEN 'Miércoles'
            WHEN 5 THEN 'Jueves'
            WHEN 6 THEN 'Viernes'
            WHEN 7 THEN 'Sábado'
        END AS day_name,
        
        -- Razón específica de datos insuficientes
        CASE
            WHEN baseline_avg_total_calls IS NULL THEN 'NO_BASELINE'
            WHEN baseline_sample_size < 3 THEN 'FEW_SAMPLES'
            WHEN baseline_stddev IS NULL OR baseline_stddev = 0 THEN 'NO_VARIANCE'
            ELSE 'OK'
        END AS insufficient_reason,
        
        CASE
            -- No hay baseline histórico
            WHEN baseline_avg_total_calls IS NULL 
                THEN 'INSUFFICIENT_DATA'
            -- Pocos días del mismo weekday (< 3)
            WHEN baseline_sample_size < 3
                THEN 'INSUFFICIENT_DATA'
            -- No hay varianza histórica
            WHEN baseline_stddev IS NULL OR baseline_stddev = 0 
                THEN 'INSUFFICIENT_DATA'
            
            -- CRITICAL: Z < -2.5
            WHEN z_score < -2.5 
                THEN 'CRITICAL'
            
            -- WARNING: Z < -2.0
            WHEN z_score < -2.0 
                THEN 'WARNING'
            
            ELSE 'FINE'
        END AS alert_severity
        
    FROM alert_calculation
)

SELECT
    CASE
        WHEN alert_severity = 'CRITICAL' THEN
            CONCAT(
                '🔴 CRITICAL [vs Promedio 30d]: ', organization_name, ' (', country, '). ',
                'Volumen hoy: ', CAST(current_total_calls AS VARCHAR), ' llamadas. ',
                'Promedio histórico (', day_name, ' hasta esta hora): ', CAST(baseline_avg_total_calls AS VARCHAR), 
                ' ± ', CAST(ROUND(baseline_stddev, 0) AS VARCHAR), ' llamadas. ',
                'Caída de ', CAST(ABS(absolute_change) AS VARCHAR), ' llamadas (',
                CAST(ABS(pct_change) AS VARCHAR), '%). ',
                'Basado en ', CAST(baseline_sample_size AS VARCHAR), ' ', day_name, ' históricos.'
            )
        WHEN alert_severity = 'WARNING' THEN
            CONCAT(
                '🟠 WARNING [vs Promedio 30d]: ', organization_name, ' (', country, '). ',
                'Volumen hoy: ', CAST(current_total_calls AS VARCHAR), ' llamadas. ',
                'Promedio histórico (', day_name, ' hasta esta hora): ', CAST(baseline_avg_total_calls AS VARCHAR), 
                ' ± ', CAST(ROUND(baseline_stddev, 0) AS VARCHAR), ' llamadas. ',
                'Caída de ', CAST(ABS(absolute_change) AS VARCHAR), ' llamadas (',
                CAST(ABS(pct_change) AS VARCHAR), '%).'
            )
        WHEN alert_severity = 'INSUFFICIENT_DATA' THEN
            CONCAT(
                '⚪ DATOS INSUFICIENTES [vs Promedio 30d]: ', organization_name, ' (', country, '). ',
                CASE insufficient_reason
                    WHEN 'NO_BASELINE' THEN 
                        CONCAT('No existe baseline histórico para ', day_name, ' en esta organización.')
                    WHEN 'FEW_SAMPLES' THEN 
                        CONCAT('Solo hay ', CAST(baseline_sample_size AS VARCHAR), 
                               ' ', day_name, ' en el historial. Se requieren mínimo 3.')
                    WHEN 'NO_VARIANCE' THEN 
                        'La variabilidad histórica es cero, no se puede calcular z-score.'
                    ELSE 'Datos insuficientes para generar alerta confiable.'
                END
            )
        WHEN alert_severity = 'FINE' THEN
            CONCAT(
                '🟢 FINE [vs Promedio 30d]: ', organization_name, ' (', country, '). ',
                'Volumen normal. Hoy: ', CAST(current_total_calls AS VARCHAR), ' llamadas. ',
                'Promedio histórico para ', day_name, ': ', CAST(baseline_avg_total_calls AS VARCHAR), 
                ' ± ', CAST(ROUND(baseline_stddev, 0) AS VARCHAR), ' llamadas. ',
                CASE 
                    WHEN pct_change > 10 THEN CONCAT('Volumen superior al promedio (+', CAST(pct_change AS VARCHAR), '%).')
                    WHEN pct_change < -10 THEN CONCAT('Ligeramente por debajo del promedio (', CAST(pct_change AS VARCHAR), '%), dentro de la variación normal.')
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
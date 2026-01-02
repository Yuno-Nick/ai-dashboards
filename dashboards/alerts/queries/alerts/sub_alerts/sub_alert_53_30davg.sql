-- ==============================================================================
-- Alert 5.3: Call Duration Anomaly - vs 30d Same Weekday Average (SAME MOMENT)
-- ==============================================================================
-- Compara la duración promedio de llamadas de HOY hasta el momento actual vs 
-- EL PROMEDIO DE LOS ÚLTIMOS 30 DÍAS DEL MISMO DÍA DE SEMANA HASTA LA MISMA HORA/MINUTO
-- 
-- Métrica: avg_call_duration_seconds
-- Granularidad: Diaria acumulada (hasta timestamp actual)
-- Dirección: BIDIRECCIONAL (|Z| > 2.0 WARNING, |Z| > 2.5 CRITICAL)
--
-- Z-Score usa stddev del MISMO DÍA DE SEMANA.
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

-- Baseline 30d: Promedio y Stddev del MISMO DÍA DE SEMANA hasta la MISMA HORA/MINUTO
baseline_30d_same_weekday AS (
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

alert_calculation AS (
    SELECT
        t.organization_code,
        t.organization_name,
        t.country,
        t.day_of_week,
        
        t.total_calls AS current_total_calls,
        t.completed_calls AS current_completed_calls,
        t.avg_duration_seconds AS current_avg_duration,
        
        b.avg_total_calls AS baseline_avg_total_calls,
        b.avg_completed_calls AS baseline_avg_completed_calls,
        b.avg_duration AS baseline_mean,
        b.stddev_duration AS baseline_stddev,
        b.sample_size AS baseline_sample_size,
        
        CASE 
            WHEN b.avg_duration IS NULL THEN NULL
            ELSE ROUND(t.avg_duration_seconds - b.avg_duration, 1)
        END AS seconds_change,
        
        CASE 
            WHEN b.avg_duration IS NULL OR b.avg_duration = 0 THEN NULL
            ELSE ROUND((t.avg_duration_seconds - b.avg_duration) / b.avg_duration * 100, 1)
        END AS pct_change,
        
        CASE 
            WHEN b.stddev_duration IS NULL OR b.stddev_duration = 0 THEN NULL
            ELSE ROUND((t.avg_duration_seconds - b.avg_duration) / b.stddev_duration, 2)
        END AS z_score
        
    FROM today_metrics t
    LEFT JOIN baseline_30d_same_weekday b
        ON t.organization_code = b.organization_code
        AND t.country = b.country
),

severity_calculation AS (
    SELECT
        *,
        
        CASE day_of_week
            WHEN 1 THEN 'Domingo'
            WHEN 2 THEN 'Lunes'
            WHEN 3 THEN 'Martes'
            WHEN 4 THEN 'Miércoles'
            WHEN 5 THEN 'Jueves'
            WHEN 6 THEN 'Viernes'
            WHEN 7 THEN 'Sábado'
        END AS day_name,
        
        CASE 
            WHEN z_score > 0 THEN 'TOO_LONG'
            WHEN z_score < 0 THEN 'TOO_SHORT'
            ELSE 'NORMAL'
        END AS anomaly_type,
        
        CASE
            WHEN current_completed_calls < 30 THEN 'FEW_COMPLETED_TODAY'
            WHEN baseline_mean IS NULL THEN 'NO_BASELINE'
            WHEN baseline_sample_size < 3 THEN 'FEW_SAMPLES'
            WHEN baseline_stddev IS NULL OR baseline_stddev = 0 THEN 'NO_VARIANCE'
            ELSE 'OK'
        END AS insufficient_reason,
        
        CASE
            WHEN current_completed_calls < 30 THEN 'INSUFFICIENT_DATA'
            WHEN baseline_mean IS NULL THEN 'INSUFFICIENT_DATA'
            WHEN baseline_sample_size < 3 THEN 'INSUFFICIENT_DATA'
            WHEN baseline_stddev IS NULL OR baseline_stddev = 0 THEN 'INSUFFICIENT_DATA'
            
            WHEN ABS(z_score) > 2.5 THEN 'CRITICAL'
            WHEN ABS(z_score) > 2.0 THEN 'WARNING'
            
            ELSE 'FINE'
        END AS alert_severity
        
    FROM alert_calculation
)

SELECT
    CASE
        WHEN alert_severity = 'CRITICAL' AND anomaly_type = 'TOO_SHORT' THEN
            CONCAT(
                '🔴 CRITICAL [vs Promedio 30d]: ', organization_name, ' (', country, '). ',
                'Duración ANORMALMENTE CORTA. Hoy: ', CAST(current_avg_duration AS VARCHAR), 's promedio. ',
                'Promedio histórico (', day_name, ' hasta esta hora): ', CAST(baseline_mean AS VARCHAR), 's. ',
                'Diferencia: ', CAST(seconds_change AS VARCHAR), 's (', CAST(pct_change AS VARCHAR), '%). ',
                'Basado en ', CAST(baseline_sample_size AS VARCHAR), ' ', day_name, ' históricos.'
            )
        WHEN alert_severity = 'CRITICAL' AND anomaly_type = 'TOO_LONG' THEN
            CONCAT(
                '🔴 CRITICAL [vs Promedio 30d]: ', organization_name, ' (', country, '). ',
                'Duración ANORMALMENTE LARGA. Hoy: ', CAST(current_avg_duration AS VARCHAR), 's promedio. ',
                'Promedio histórico (', day_name, ' hasta esta hora): ', CAST(baseline_mean AS VARCHAR), 's. ',
                'Diferencia: +', CAST(seconds_change AS VARCHAR), 's (+', CAST(pct_change AS VARCHAR), '%). ',
                'Basado en ', CAST(baseline_sample_size AS VARCHAR), ' ', day_name, ' históricos.'
            )
        WHEN alert_severity = 'WARNING' AND anomaly_type = 'TOO_SHORT' THEN
            CONCAT(
                '🟠 WARNING [vs Promedio 30d]: ', organization_name, ' (', country, '). ',
                'Duración más corta de lo normal. Hoy: ', CAST(current_avg_duration AS VARCHAR), 's promedio. ',
                'Promedio histórico (', day_name, ' hasta esta hora): ', CAST(baseline_mean AS VARCHAR), 's. ',
                'Diferencia: ', CAST(seconds_change AS VARCHAR), 's (', CAST(pct_change AS VARCHAR), '%).'
            )
        WHEN alert_severity = 'WARNING' AND anomaly_type = 'TOO_LONG' THEN
            CONCAT(
                '🟠 WARNING [vs Promedio 30d]: ', organization_name, ' (', country, '). ',
                'Duración más larga de lo normal. Hoy: ', CAST(current_avg_duration AS VARCHAR), 's promedio. ',
                'Promedio histórico (', day_name, ' hasta esta hora): ', CAST(baseline_mean AS VARCHAR), 's. ',
                'Diferencia: +', CAST(seconds_change AS VARCHAR), 's (+', CAST(pct_change AS VARCHAR), '%).'
            )
        WHEN alert_severity = 'INSUFFICIENT_DATA' THEN
            CONCAT(
                '⚪ DATOS INSUFICIENTES [vs Promedio 30d]: ', organization_name, ' (', country, '). ',
                CASE insufficient_reason
                    WHEN 'FEW_COMPLETED_TODAY' THEN 
                        CONCAT('Hoy solo hay ', CAST(current_completed_calls AS VARCHAR), 
                               ' llamadas completadas. Se requieren mínimo 30.')
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
                'Duración normal. Hoy: ', CAST(current_avg_duration AS VARCHAR), 's promedio. ',
                'Promedio histórico para ', day_name, ': ', CAST(baseline_mean AS VARCHAR), 's. ',
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
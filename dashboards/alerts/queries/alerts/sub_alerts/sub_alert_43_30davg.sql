-- ==============================================================================
-- Alert 4.3: Short Call Rate Spike - vs 30d Same Weekday Average (SAME MOMENT)
-- ==============================================================================
-- Compara el short_call_rate de HOY hasta el momento actual vs 
-- EL PROMEDIO DE LOS ÚLTIMOS 30 DÍAS DEL MISMO DÍA DE SEMANA HASTA LA MISMA HORA/MINUTO
-- 
-- Métrica: short_call_rate = short_calls / completed_calls
-- Granularidad: Diaria acumulada (hasta timestamp actual)
-- Dirección: HIGHER is bad (Z > +2.0 WARNING, Z > +2.5 CRITICAL)
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

-- Baseline 30d: Promedio y Stddev del MISMO DÍA DE SEMANA hasta la MISMA HORA/MINUTO
baseline_30d_same_weekday AS (
    SELECT
        organization_code,
        country,
        
        COUNT(DISTINCT created_date) AS sample_size,
        ROUND(AVG(total_calls), 0) AS avg_total_calls,
        ROUND(AVG(completed_calls), 0) AS avg_completed_calls,
        ROUND(AVG(short_calls), 0) AS avg_short_calls,
        ROUND(AVG(daily_short_call_rate), 4) AS avg_short_call_rate,
        ROUND(STDDEV(daily_short_call_rate), 4) AS stddev_short_call_rate
        
    FROM (
        SELECT
            d.organization_code,
            d.country,
            d.created_date,
            
            COUNT(*) AS total_calls,
            SUM(CASE WHEN d.call_classification IN ('good_calls', 'short_calls', 'completed') 
                     THEN 1 ELSE 0 END) AS completed_calls,
            SUM(CASE WHEN d.call_classification = 'short_calls' THEN 1 ELSE 0 END) AS short_calls,
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

alert_calculation AS (
    SELECT
        t.organization_code,
        t.organization_name,
        t.country,
        t.day_of_week,
        
        -- Métricas actuales
        t.total_calls AS current_total_calls,
        t.completed_calls AS current_completed_calls,
        t.short_calls AS current_short_calls,
        t.short_call_rate AS current_short_call_rate,
        
        -- Baseline de 30 días (mismo día de semana)
        b.avg_total_calls AS baseline_avg_total_calls,
        b.avg_completed_calls AS baseline_avg_completed_calls,
        b.avg_short_calls AS baseline_avg_short_calls,
        b.avg_short_call_rate AS baseline_mean,
        b.stddev_short_call_rate AS baseline_stddev,
        b.sample_size AS baseline_sample_size,
        
        -- Diferencia en puntos porcentuales
        CASE 
            WHEN b.avg_short_call_rate IS NULL THEN NULL
            ELSE ROUND((t.short_call_rate - b.avg_short_call_rate) * 100, 1)
        END AS pp_change,
        
        -- Z-Score usando stddev del MISMO DÍA DE SEMANA
        CASE 
            WHEN b.stddev_short_call_rate IS NULL OR b.stddev_short_call_rate = 0 THEN NULL
            ELSE ROUND((t.short_call_rate - b.avg_short_call_rate) / b.stddev_short_call_rate, 2)
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
            
            WHEN z_score > 2.5 THEN 'CRITICAL'
            WHEN z_score > 2.0 THEN 'WARNING'
            
            ELSE 'FINE'
        END AS alert_severity
        
    FROM alert_calculation
)

SELECT
    CASE
        WHEN alert_severity = 'CRITICAL' THEN
            CONCAT(
                '🔴 CRITICAL [vs Promedio 30d]: ', organization_name, ' (', country, '). ',
                'Short call rate hoy: ', CAST(ROUND(current_short_call_rate * 100, 1) AS VARCHAR), '% (',
                CAST(current_short_calls AS VARCHAR), '/', CAST(current_completed_calls AS VARCHAR), ' short/completed). ',
                'Promedio histórico (', day_name, ' hasta esta hora): ', CAST(ROUND(baseline_mean * 100, 1) AS VARCHAR), '% (~',
                CAST(baseline_avg_short_calls AS VARCHAR), '/', CAST(baseline_avg_completed_calls AS VARCHAR), ' short/completed). ',
                'Aumento de ', CAST(pp_change AS VARCHAR), ' pp. ',
                'Basado en ', CAST(baseline_sample_size AS VARCHAR), ' ', day_name, ' históricos.'
            )
        WHEN alert_severity = 'WARNING' THEN
            CONCAT(
                '🟠 WARNING [vs Promedio 30d]: ', organization_name, ' (', country, '). ',
                'Short call rate hoy: ', CAST(ROUND(current_short_call_rate * 100, 1) AS VARCHAR), '% (',
                CAST(current_short_calls AS VARCHAR), '/', CAST(current_completed_calls AS VARCHAR), ' short/completed). ',
                'Promedio histórico (', day_name, ' hasta esta hora): ', CAST(ROUND(baseline_mean * 100, 1) AS VARCHAR), '% (~',
                CAST(baseline_avg_short_calls AS VARCHAR), '/', CAST(baseline_avg_completed_calls AS VARCHAR), ' short/completed). ',
                'Aumento de ', CAST(pp_change AS VARCHAR), ' pp.'
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
                'Short call rate normal. Hoy: ', CAST(ROUND(current_short_call_rate * 100, 1) AS VARCHAR), '% (',
                CAST(current_short_calls AS VARCHAR), '/', CAST(current_completed_calls AS VARCHAR), ' short/completed). ',
                'Promedio histórico para ', day_name, ': ', CAST(ROUND(baseline_mean * 100, 1) AS VARCHAR), '% (~',
                CAST(baseline_avg_short_calls AS VARCHAR), '/', CAST(baseline_avg_completed_calls AS VARCHAR), ' short/completed). ',
                CASE 
                    WHEN pp_change <= -2 THEN CONCAT('Mejora de ', CAST(ABS(pp_change) AS VARCHAR), ' pp.')
                    WHEN pp_change >= 2 THEN CONCAT('Ligero aumento de ', CAST(pp_change AS VARCHAR), ' pp, dentro de rangos aceptables.')
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
    z_score DESC
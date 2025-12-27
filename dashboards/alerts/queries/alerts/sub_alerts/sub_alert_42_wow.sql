-- ==============================================================================
-- Alert 4.2: Short Call Rate Spike - vs Last Week Same Day (Same Moment)
-- ==============================================================================
-- Compara el short_call_rate de HOY hasta el momento actual vs 
-- HACE 7 DÍAS (mismo día de semana) hasta el mismo momento.
-- 
-- Métrica: short_call_rate = short_calls / completed_calls
-- Granularidad: Diaria acumulada (hasta timestamp actual)
-- Dirección: HIGHER is bad (Z > +2.0 WARNING, Z > +2.5 CRITICAL)
--
-- Z-Score usa stddev del MISMO DÍA DE SEMANA (últimos 30d) porque WoW
-- compara Viernes con Viernes, Lunes con Lunes, etc.
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

-- Stddev del MISMO DÍA DE SEMANA (últimos 30d)
stddev_same_weekday AS (
    SELECT
        organization_code,
        country,
        COUNT(DISTINCT created_date) AS sample_size,
        ROUND(AVG(daily_short_call_rate), 4) AS avg_short_call_rate,
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
        
        -- Baseline (semana pasada)
        lw.total_calls AS baseline_total_calls,
        lw.completed_calls AS baseline_completed_calls,
        lw.short_calls AS baseline_short_calls,
        lw.short_call_rate AS baseline_short_call_rate,
        
        -- Stddev del mismo día de semana
        s.stddev_short_call_rate AS stddev_same_weekday,
        s.sample_size AS sample_size_weekday,
        
        -- Diferencia en puntos porcentuales
        CASE 
            WHEN lw.short_call_rate IS NULL THEN NULL
            ELSE ROUND((t.short_call_rate - lw.short_call_rate) * 100, 1)
        END AS pp_change,
        
        -- Z-Score usando stddev del MISMO DÍA DE SEMANA
        CASE 
            WHEN s.stddev_short_call_rate IS NULL OR s.stddev_short_call_rate = 0 THEN NULL
            ELSE ROUND((t.short_call_rate - lw.short_call_rate) / s.stddev_short_call_rate, 2)
        END AS z_score
        
    FROM today_metrics t
    LEFT JOIN lastweek_metrics lw
        ON t.organization_code = lw.organization_code
        AND t.country = lw.country
    LEFT JOIN stddev_same_weekday s
        ON t.organization_code = s.organization_code
        AND t.country = s.country
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
            WHEN current_completed_calls < 30 THEN 'INSUFFICIENT_DATA'
            WHEN baseline_short_call_rate IS NULL THEN 'INSUFFICIENT_DATA'
            WHEN baseline_completed_calls < 30 THEN 'INSUFFICIENT_DATA'
            WHEN stddev_same_weekday IS NULL OR stddev_same_weekday = 0 THEN 'INSUFFICIENT_DATA'
            WHEN sample_size_weekday < 3 THEN 'INSUFFICIENT_DATA'
            
            WHEN z_score > 2.5 THEN 'CRITICAL'
            WHEN z_score > 2.0 THEN 'WARNING'
            
            ELSE 'FINE'
        END AS alert_severity,
        
        CASE
            WHEN current_completed_calls < 30 THEN 'FEW_COMPLETED_TODAY'
            WHEN baseline_short_call_rate IS NULL THEN 'NO_BASELINE'
            WHEN baseline_completed_calls < 30 THEN 'FEW_COMPLETED_BASELINE'
            WHEN stddev_same_weekday IS NULL OR stddev_same_weekday = 0 THEN 'NO_VARIANCE'
            WHEN sample_size_weekday < 3 THEN 'FEW_SAMPLES'
            ELSE 'OK'
        END AS insufficient_reason
        
    FROM alert_calculation
)

SELECT
    CASE
        WHEN alert_severity = 'CRITICAL' THEN
            CONCAT(
                '🔴 CRITICAL [vs Semana Pasada]: ', organization_name, ' (', country, '). ',
                'Short call rate hoy: ', CAST(ROUND(current_short_call_rate * 100, 1) AS VARCHAR), '% (',
                CAST(current_short_calls AS VARCHAR), '/', CAST(current_completed_calls AS VARCHAR), ' short/completed). ',
                day_name, ' pasado a esta hora: ', CAST(ROUND(baseline_short_call_rate * 100, 1) AS VARCHAR), '% (',
                CAST(baseline_short_calls AS VARCHAR), '/', CAST(baseline_completed_calls AS VARCHAR), ' short/completed). ',
                'Aumento de ', CAST(pp_change AS VARCHAR), ' pp.'
            )
        WHEN alert_severity = 'WARNING' THEN
            CONCAT(
                '🟠 WARNING [vs Semana Pasada]: ', organization_name, ' (', country, '). ',
                'Short call rate hoy: ', CAST(ROUND(current_short_call_rate * 100, 1) AS VARCHAR), '% (',
                CAST(current_short_calls AS VARCHAR), '/', CAST(current_completed_calls AS VARCHAR), ' short/completed). ',
                day_name, ' pasado a esta hora: ', CAST(ROUND(baseline_short_call_rate * 100, 1) AS VARCHAR), '% (',
                CAST(baseline_short_calls AS VARCHAR), '/', CAST(baseline_completed_calls AS VARCHAR), ' short/completed). ',
                'Aumento de ', CAST(pp_change AS VARCHAR), ' pp.'
            )
        WHEN alert_severity = 'INSUFFICIENT_DATA' THEN
            CONCAT(
                '⚪ DATOS INSUFICIENTES [vs Semana Pasada]: ', organization_name, ' (', country, '). ',
                CASE insufficient_reason
                    WHEN 'FEW_COMPLETED_TODAY' THEN 
                        CONCAT('Hoy solo hay ', CAST(current_completed_calls AS VARCHAR), 
                               ' llamadas completadas. Se requieren mínimo 30.')
                    WHEN 'NO_BASELINE' THEN 
                        CONCAT('No hay datos del ', day_name, ' pasado para comparar.')
                    WHEN 'FEW_COMPLETED_BASELINE' THEN 
                        CONCAT('El ', day_name, ' pasado solo hubo ', CAST(COALESCE(baseline_completed_calls, 0) AS VARCHAR), 
                               ' llamadas completadas. Se requieren mínimo 30.')
                    WHEN 'NO_VARIANCE' THEN 
                        CONCAT('No hay suficiente variabilidad histórica para ', day_name, '.')
                    WHEN 'FEW_SAMPLES' THEN 
                        CONCAT('Solo hay ', CAST(sample_size_weekday AS VARCHAR), 
                               ' ', day_name, ' en el historial. Se requieren mínimo 3.')
                    ELSE 'Datos insuficientes para generar alerta confiable.'
                END
            )
        WHEN alert_severity = 'FINE' THEN
            CONCAT(
                '🟢 FINE [vs Semana Pasada]: ', organization_name, ' (', country, '). ',
                'Short call rate normal. Hoy: ', CAST(ROUND(current_short_call_rate * 100, 1) AS VARCHAR), '% (',
                CAST(current_short_calls AS VARCHAR), '/', CAST(current_completed_calls AS VARCHAR), ' short/completed). ',
                day_name, ' pasado a esta hora: ', CAST(ROUND(baseline_short_call_rate * 100, 1) AS VARCHAR), '%. ',
                CASE 
                    WHEN pp_change <= -2 THEN CONCAT('Mejora de ', CAST(ABS(pp_change) AS VARCHAR), ' pp.')
                    WHEN pp_change >= 2 THEN CONCAT('Ligero aumento de ', CAST(pp_change AS VARCHAR), ' pp, dentro de rangos aceptables.')
                    ELSE CONCAT('En línea con el comportamiento histórico del ', day_name, '.')
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
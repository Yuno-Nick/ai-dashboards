-- ==============================================================================
-- Alert 2.2: Completion Rate Drop - vs Last Week Same Day (Same Moment)
-- ==============================================================================
-- Compara el completion_rate de HOY hasta el momento actual vs 
-- HACE 7 DÍAS (mismo día de semana) hasta el mismo momento.
-- 
-- Métrica: completion_rate = completed_calls / total_calls
-- Granularidad: Diaria acumulada (hasta timestamp actual)
-- Dirección: Lower is bad (Z < -2.0 WARNING, Z < -2.5 CRITICAL)
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
        
        ROUND(
            CAST(SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') 
                          THEN 1 ELSE 0 END) AS FLOAT) / 
            NULLIF(COUNT(*), 0),
            4
        ) AS completion_rate
        
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
        
        ROUND(
            CAST(SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') 
                          THEN 1 ELSE 0 END) AS FLOAT) / 
            NULLIF(COUNT(*), 0),
            4
        ) AS completion_rate
        
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

-- Stddev de completion_rate del MISMO DÍA DE SEMANA (últimos 30d) - para comparación WoW
stddev_same_weekday AS (
    SELECT
        organization_code,
        country,
        COUNT(DISTINCT created_date) AS sample_size,
        ROUND(AVG(daily_completion_rate), 4) AS avg_completion_rate,
        ROUND(STDDEV(daily_completion_rate), 4) AS stddev_completion_rate
    FROM (
        SELECT
            d.organization_code,
            d.country,
            d.created_date,
            ROUND(
                CAST(SUM(CASE WHEN d.call_classification IN ('good_calls', 'short_calls', 'completed') 
                              THEN 1 ELSE 0 END) AS FLOAT) / 
                NULLIF(COUNT(*), 0),
                4
            ) AS daily_completion_rate
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
        HAVING COUNT(*) >= 50  -- Mínimo 50 llamadas para rate confiable
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
        t.completion_rate AS current_completion_rate,
        
        -- Baseline (semana pasada)
        lw.total_calls AS baseline_total_calls,
        lw.completed_calls AS baseline_completed_calls,
        lw.completion_rate AS baseline_completion_rate,
        
        -- Stddev del mismo día de semana
        s.stddev_completion_rate AS stddev_same_weekday,
        s.sample_size AS sample_size_weekday,
        
        -- Diferencia en puntos porcentuales
        CASE 
            WHEN lw.completion_rate IS NULL THEN NULL
            ELSE ROUND((t.completion_rate - lw.completion_rate) * 100, 1)
        END AS pp_change,
        
        -- Z-Score usando stddev del MISMO DÍA DE SEMANA
        CASE 
            WHEN s.stddev_completion_rate IS NULL OR s.stddev_completion_rate = 0 THEN NULL
            ELSE ROUND((t.completion_rate - lw.completion_rate) / s.stddev_completion_rate, 2)
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
        
        CASE
            -- Datos insuficientes
            WHEN current_total_calls < 50 THEN 'INSUFFICIENT_DATA'
            WHEN baseline_completion_rate IS NULL THEN 'INSUFFICIENT_DATA'
            WHEN baseline_total_calls < 50 THEN 'INSUFFICIENT_DATA'
            WHEN stddev_same_weekday IS NULL OR stddev_same_weekday = 0 THEN 'INSUFFICIENT_DATA'
            WHEN sample_size_weekday < 3 THEN 'INSUFFICIENT_DATA'
            
            -- CRITICAL: Z < -2.5
            WHEN z_score < -2.5 THEN 'CRITICAL'
            
            -- WARNING: Z < -2.0
            WHEN z_score < -2.0 THEN 'WARNING'
            
            ELSE 'FINE'
        END AS alert_severity,
        
        -- Razón de datos insuficientes
        CASE
            WHEN current_total_calls < 50 THEN 'FEW_CALLS_TODAY'
            WHEN baseline_completion_rate IS NULL THEN 'NO_BASELINE'
            WHEN baseline_total_calls < 50 THEN 'FEW_CALLS_BASELINE'
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
                'Completion rate hoy: ', CAST(ROUND(current_completion_rate * 100, 1) AS VARCHAR), '% (',
                CAST(current_completed_calls AS VARCHAR), '/', CAST(current_total_calls AS VARCHAR), ' llamadas). ',
                day_name, ' pasado a esta hora: ', CAST(ROUND(baseline_completion_rate * 100, 1) AS VARCHAR), '% (',
                CAST(baseline_completed_calls AS VARCHAR), '/', CAST(baseline_total_calls AS VARCHAR), ' llamadas). ',
                'Caída de ', CAST(ABS(pp_change) AS VARCHAR), ' pp.'
            )
        WHEN alert_severity = 'WARNING' THEN
            CONCAT(
                '🟠 WARNING [vs Semana Pasada]: ', organization_name, ' (', country, '). ',
                'Completion rate hoy: ', CAST(ROUND(current_completion_rate * 100, 1) AS VARCHAR), '% (',
                CAST(current_completed_calls AS VARCHAR), '/', CAST(current_total_calls AS VARCHAR), ' llamadas). ',
                day_name, ' pasado a esta hora: ', CAST(ROUND(baseline_completion_rate * 100, 1) AS VARCHAR), '% (',
                CAST(baseline_completed_calls AS VARCHAR), '/', CAST(baseline_total_calls AS VARCHAR), ' llamadas). ',
                'Caída de ', CAST(ABS(pp_change) AS VARCHAR), ' pp.'
            )
        WHEN alert_severity = 'INSUFFICIENT_DATA' THEN
            CONCAT(
                '⚪ DATOS INSUFICIENTES [vs Semana Pasada]: ', organization_name, ' (', country, '). ',
                CASE insufficient_reason
                    WHEN 'FEW_CALLS_TODAY' THEN 
                        CONCAT('Hoy solo hay ', CAST(current_total_calls AS VARCHAR), 
                               ' llamadas. Se requieren mínimo 50.')
                    WHEN 'NO_BASELINE' THEN 
                        CONCAT('No hay datos del ', day_name, ' pasado para comparar.')
                    WHEN 'FEW_CALLS_BASELINE' THEN 
                        CONCAT('El ', day_name, ' pasado solo hubo ', CAST(COALESCE(baseline_total_calls, 0) AS VARCHAR), 
                               ' llamadas. Se requieren mínimo 50.')
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
                'Completion rate normal. Hoy: ', CAST(ROUND(current_completion_rate * 100, 1) AS VARCHAR), '% (',
                CAST(current_completed_calls AS VARCHAR), '/', CAST(current_total_calls AS VARCHAR), ' llamadas). ',
                day_name, ' pasado a esta hora: ', CAST(ROUND(baseline_completion_rate * 100, 1) AS VARCHAR), '% (',
                CAST(baseline_completed_calls AS VARCHAR), '/', CAST(baseline_total_calls AS VARCHAR), ' llamadas). ',
                CASE 
                    WHEN pp_change >= 2 THEN CONCAT('Rendimiento superior al promedio (+', CAST(pp_change AS VARCHAR), ' pp).')
                    WHEN pp_change <= -2 THEN CONCAT('Ligeramente por debajo del promedio (', CAST(pp_change AS VARCHAR), ' pp), dentro de rangos aceptables.')
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
    z_score ASC
-- ==============================================================================
-- Alert 2: Daily Call Quality Degradation (DUAL BASELINE: ayer + promedio 30 días)
-- ==============================================================================
-- Detecta degradación de calidad usando DOBLE VALIDACIÓN:
-- 
-- BASELINES:
-- 1. Ayer mismo momento: Comparación DoD (Day over Day)
-- 2. Promedio de los últimos 30 días hasta misma hora
--    Ej: Si hoy es 14:00, promedia quality_rate de TODOS los días hasta las 14:00
-- 
-- CRITERIO DE ALERTA (requiere AMBAS condiciones):
-- - WARNING: today < 90% de yesterday AND today < 90% de avg_30d
-- - CRITICAL: today < 80% de yesterday AND today < 80% de avg_30d
--
-- Esto reduce falsos positivos causados por volatilidad diaria o anomalías puntuales
-- ==============================================================================

WITH today_stats AS (
  SELECT
    organization_code,
    organization_name,
    country,
    
    COUNT(*) AS total_calls,
    SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END) AS completed_calls,
    SUM(CASE WHEN call_classification = 'good_calls' THEN 1 ELSE 0 END) AS good_calls,
    SUM(CASE WHEN call_classification = 'short_calls' THEN 1 ELSE 0 END) AS short_calls,
    SUM(call_duration_minutes) AS total_minutes,
    
    ROUND(
      CAST(SUM(CASE WHEN call_classification = 'good_calls' THEN 1 ELSE 0 END) AS FLOAT) / 
      NULLIF(SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END), 0),
      4
    ) AS quality_rate
    
  FROM ai_calls_detail
  WHERE 
    created_date = CURRENT_DATE()
    AND created_at < CURRENT_TIMESTAMP()
    -- [[AND {{organization_name}}]]
    -- [[AND {{countries}}]]
  GROUP BY organization_code, organization_name, country
),

yesterday_stats AS (
  SELECT
    organization_code,
    organization_name,
    country,
    
    COUNT(*) AS total_calls,
    SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END) AS completed_calls,
    SUM(CASE WHEN call_classification = 'good_calls' THEN 1 ELSE 0 END) AS good_calls,
    SUM(CASE WHEN call_classification = 'short_calls' THEN 1 ELSE 0 END) AS short_calls,
    SUM(call_duration_minutes) AS total_minutes,
    
    ROUND(
      CAST(SUM(CASE WHEN call_classification = 'good_calls' THEN 1 ELSE 0 END) AS FLOAT) / 
      NULLIF(SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END), 0),
      4
    ) AS quality_rate
    
  FROM ai_calls_detail
  WHERE 
    created_date = CURRENT_DATE() - INTERVAL 1 DAY
    AND created_at < CURRENT_TIMESTAMP() - INTERVAL 1 DAY
    -- [[AND {{organization_name}}]]
    -- [[AND {{countries}}]]
  GROUP BY organization_code, organization_name, country
),

-- NEW: Promedio de quality_rate de TODOS los días hasta la hora actual (últimos 30 días)
baseline_30d_avg AS (
  SELECT
    organization_code,
    organization_name,
    country,
    
    -- Promedio de quality_rate de todos los días hasta la hora actual
    ROUND(AVG(daily_quality_rate), 4) AS avg_quality_rate_30d,
    
    -- Número de días con data
    COUNT(DISTINCT created_date) AS days_with_data
    
  FROM (
    SELECT
      organization_code,
      organization_name,
      country,
      created_date,
      -- Calcular quality_rate por día hasta la hora actual
      ROUND(
        CAST(SUM(CASE WHEN call_classification = 'good_calls' THEN 1 ELSE 0 END) AS FLOAT) / 
        NULLIF(SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END), 0),
        4
      ) AS daily_quality_rate
    FROM ai_calls_detail
    WHERE 
      created_date >= CURRENT_DATE() - INTERVAL 30 DAY
      AND created_date < CURRENT_DATE()
      -- Solo llamadas hasta la misma hora del día (sin filtrar por día de semana)
      AND (
        EXTRACT(HOUR FROM created_at) < EXTRACT(HOUR FROM CURRENT_TIMESTAMP())
        OR (
          EXTRACT(HOUR FROM created_at) = EXTRACT(HOUR FROM CURRENT_TIMESTAMP())
          AND EXTRACT(MINUTE FROM created_at) <= EXTRACT(MINUTE FROM CURRENT_TIMESTAMP())
        )
      )
      -- [[AND {{organization_name}}]]
      -- [[AND {{countries}}]]
    GROUP BY organization_code, organization_name, country, created_date
    HAVING SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END) >= 10  -- Mínimo 10 completed calls por día
  ) daily_stats
  GROUP BY organization_code, organization_name, country
),

daily_comparison AS (
  SELECT
    COALESCE(t.organization_code, y.organization_code, b.organization_code) AS organization_code,
    COALESCE(t.organization_name, y.organization_name, b.organization_name) AS organization_name,
    COALESCE(t.country, y.country, b.country) AS country,
    
    CURRENT_TIMESTAMP() AS alert_timestamp,
    
    -- Today's metrics
    COALESCE(t.total_calls, 0) AS today_total_calls,
    COALESCE(t.completed_calls, 0) AS today_completed_calls,
    COALESCE(t.good_calls, 0) AS today_good_calls,
    COALESCE(t.short_calls, 0) AS today_short_calls,
    COALESCE(t.total_minutes, 0) AS today_total_minutes,
    COALESCE(t.quality_rate, 0) AS today_quality_rate,
    
    -- Yesterday's metrics
    COALESCE(y.total_calls, 0) AS yesterday_total_calls,
    COALESCE(y.completed_calls, 0) AS yesterday_completed_calls,
    COALESCE(y.good_calls, 0) AS yesterday_good_calls,
    COALESCE(y.short_calls, 0) AS yesterday_short_calls,
    COALESCE(y.total_minutes, 0) AS yesterday_total_minutes,
    COALESCE(y.quality_rate, 0) AS yesterday_quality_rate,
    
    -- Baseline 30 días (todos los días)
    COALESCE(b.avg_quality_rate_30d, 0) AS baseline_30d_avg_quality,
    COALESCE(b.days_with_data, 0) AS baseline_days_count,
    
    -- Ratio vs yesterday
    ROUND(
      COALESCE(t.quality_rate, 0) / NULLIF(y.quality_rate, 0),
      4
    ) AS quality_ratio_vs_yesterday,
    
    -- NEW: Ratio vs 30d baseline (mismo día de semana)
    ROUND(
      COALESCE(t.quality_rate, 0) / NULLIF(b.avg_quality_rate_30d, 0),
      4
    ) AS quality_ratio_vs_30d_avg,
    
    -- Severity determination (DUAL BASELINE: requiere AMBOS criterios)
    CASE
      -- Insufficient data
      WHEN COALESCE(t.completed_calls, 0) < 50 
        OR COALESCE(y.completed_calls, 0) < 50
        OR COALESCE(b.days_with_data, 0) < 20
        THEN 'INSUFFICIENT_DATA'
      
      -- Critical: Drop > 20% vs AMBOS baselines
      WHEN COALESCE(t.quality_rate, 0) / NULLIF(y.quality_rate, 0) < 0.70
        AND COALESCE(t.quality_rate, 0) / NULLIF(b.avg_quality_rate_30d, 0) < 0.70
        THEN 'CRITICAL'
      
      -- Warning: Drop 10-20% vs AMBOS baselines
      WHEN COALESCE(t.quality_rate, 0) / NULLIF(y.quality_rate, 0) < 0.90
        AND COALESCE(t.quality_rate, 0) / NULLIF(b.avg_quality_rate_30d, 0) < 0.90
        THEN 'WARNING'
      
      ELSE 'FINE'
    END AS alert_severity
    
  FROM today_stats t
  FULL OUTER JOIN yesterday_stats y
    ON t.organization_code = y.organization_code
    AND t.country = y.country
  FULL OUTER JOIN baseline_30d_avg b
    ON COALESCE(t.organization_code, y.organization_code) = b.organization_code
    AND COALESCE(t.country, y.country) = b.country
)

SELECT
  datetime,
  T_rate,
  Y_rate,
  30D_AVG_rate,
  T_v_Y_ratio,
  T_v_30D_ratio,
  alert_message
FROM (
  SELECT
    alert_timestamp AS datetime,
    organization_name,
    country,
    today_quality_rate AS T_rate,
    yesterday_quality_rate AS Y_rate,
    ROUND(baseline_30d_avg_quality, 4) AS 30D_AVG_rate,
    quality_ratio_vs_yesterday AS T_v_Y_ratio,
    quality_ratio_vs_30d_avg AS T_v_30D_ratio,
    today_good_calls,
    today_completed_calls,
    yesterday_good_calls,
    yesterday_completed_calls,
    alert_severity,
    
    -- Alert message (menciona ambos baselines: ayer + promedio 30 días)
    CASE
      WHEN alert_severity = 'INSUFFICIENT_DATA'
        THEN 'Alert suppressed: Insufficient baseline data (min 50 calls today/yesterday and 20 days with data)'
      
      WHEN alert_severity = 'CRITICAL'
        THEN CONCAT('CRITICAL: ', organization_name, ' (', country, ') - Quality dropped by ',
             CAST(ROUND((1 - quality_ratio_vs_yesterday) * 100, 1) AS VARCHAR),
             '% vs yesterday AND ',
             CAST(ROUND((1 - quality_ratio_vs_30d_avg) * 100, 1) AS VARCHAR),
             '% below 30-day avg. Today: ', CAST(today_good_calls AS VARCHAR), '/', CAST(today_completed_calls AS VARCHAR),
             ' (', CAST(ROUND(today_quality_rate * 100, 1) AS VARCHAR),
             '%) vs Yesterday: ', CAST(yesterday_good_calls AS VARCHAR), '/', CAST(yesterday_completed_calls AS VARCHAR),
             ' (', CAST(ROUND(yesterday_quality_rate * 100, 1) AS VARCHAR), 
             '%) (30d Avg: ', CAST(ROUND(baseline_30d_avg_quality * 100, 1) AS VARCHAR), '%)')
      
      WHEN alert_severity = 'WARNING'
        THEN CONCAT('WARNING: ', organization_name, ' (', country, ') - Quality dropped by ',
             CAST(ROUND((1 - quality_ratio_vs_yesterday) * 100, 1) AS VARCHAR),
             '% vs yesterday AND ',
             CAST(ROUND((1 - quality_ratio_vs_30d_avg) * 100, 1) AS VARCHAR),
             '% below 30-day avg. Today: ', CAST(ROUND(today_quality_rate * 100, 1) AS VARCHAR),
             '% vs Yesterday: ', CAST(ROUND(yesterday_quality_rate * 100, 1) AS VARCHAR), '%')
      
      ELSE 'FINE: Quality within acceptable range'
    END AS alert_message
  
  FROM daily_comparison
  WHERE
    alert_severity IN ('CRITICAL', 'WARNING')
    AND today_completed_calls >= 50      -- Minimum sample size
    AND yesterday_completed_calls >= 50  -- Minimum baseline
    AND baseline_days_count >= 20        -- Minimum 20 días con data
) subquery
ORDER BY
  alert_message DESC




-- ==============================================================================
-- Alert 2 - METRICS VIEW: Daily Quality Metrics (Informativa sin filtros)
-- ==============================================================================
-- Muestra métricas de calidad comparando:
-- 1. Hoy vs ayer (hasta hora actual)
-- 2. Hoy vs promedio de TODOS los últimos 30 días (sin filtrar por día de semana)
-- 
-- Esta es la vista informativa completa, sin filtros de alerta.
-- Útil para monitoreo y análisis de tendencias.
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
    [[AND {{organization_name}}]]
    [[AND {{countries}}]]
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
    [[AND {{organization_name}}]]
    [[AND {{countries}}]]
  GROUP BY organization_code, organization_name, country
),

-- Promedio de quality_rate de TODOS los días hasta la hora actual (últimos 30 días)
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
      [[AND {{organization_name}}]]
      [[AND {{countries}}]]
    GROUP BY organization_code, organization_name, country, created_date
    HAVING SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END) >= 10
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
    
    -- Ratio vs 30d baseline (mismo día de semana)
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
      WHEN COALESCE(t.quality_rate, 0) / NULLIF(y.quality_rate, 0) < 0.80
        AND COALESCE(t.quality_rate, 0) / NULLIF(b.avg_quality_rate_30d, 0) < 0.80
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

-- ==============================================================================
-- METRICS VIEW: Vista Informativa Completa (Sin filtros de alerta)
-- ==============================================================================
-- Muestra todas las organizaciones con sus métricas de calidad comparando:
-- - Today vs Yesterday
-- - Today vs 30-Day Average (all days)
-- 
-- Útil para monitoreo general, análisis de tendencias y detección temprana
-- ==============================================================================

SELECT
  alert_timestamp AS datetime,
  organization_name,
  country,
  today_total_calls AS T_Calls,
  yesterday_total_calls AS Y_Calls,
  today_quality_rate AS T_rate,
  yesterday_quality_rate AS Y_rate,
  ROUND(baseline_30d_avg_quality, 4) AS 30D_AVG_rate,
  quality_ratio_vs_yesterday AS T_v_Y_ratio,
  quality_ratio_vs_30d_avg AS T_v_30D_ratio,
  today_good_calls AS T_good_calls,
  today_completed_calls AS T_completed_calls,
  yesterday_good_calls AS Y_good_calls,
  yesterday_completed_calls AS Y_completed_calls,
  baseline_days_count AS 30D_days_count,
  alert_severity
FROM daily_comparison
ORDER BY
  alert_severity,
  T_v_30D_ratio ASC,
  organization_name;

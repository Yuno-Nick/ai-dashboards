-- ==============================================================================
-- Alert 3 - METRICS VIEW: Daily Volume Metrics (Informativa sin filtros)
-- ==============================================================================
-- Muestra métricas de volumen comparando:
-- 1. Hoy vs mismo día semana pasada (hasta hora actual)
-- 2. Hoy vs promedio del mismo día de semana últimos 30 días
-- 
-- Esta es la vista informativa completa, sin filtros de alerta.
-- Útil para monitoreo y análisis de tendencias.
-- ==============================================================================

WITH today_volume AS (
  SELECT
    organization_code,
    organization_name,
    country,
	created_date,
    
    COUNT(*) AS total_calls,
    SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END) AS completed_calls,
    SUM(call_duration_minutes) AS total_minutes
    
  FROM ai_calls_detail
  WHERE 
    created_date = CURRENT_DATE()
    AND created_at < CURRENT_TIMESTAMP()
    [[AND {{organization_name}}]]
    [[AND {{countries}}]]
  GROUP BY organization_code, organization_name, country, created_date
),

lastweek_volume AS (
  SELECT
    organization_code,
    organization_name,
    country,
	created_date,
    
    COUNT(*) AS total_calls,
    SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END) AS completed_calls,
    SUM(call_duration_minutes) AS total_minutes
    
  FROM ai_calls_detail
  WHERE 
    created_date = CURRENT_DATE() - INTERVAL 7 DAY
    AND created_at < CURRENT_TIMESTAMP() - INTERVAL 7 DAY
    [[AND {{organization_name}}]]
    [[AND {{countries}}]]
  GROUP BY organization_code, organization_name, country, created_date
),

-- Promedio del mismo día de semana hasta la misma hora (últimos 30 días)
baseline_30d_avg AS (
  SELECT
    organization_code,
    organization_name,
    country,
    
    -- Promedio de llamadas acumuladas hasta la hora actual (mismo día de semana)
    ROUND(AVG(daily_calls_until_now), 2) AS avg_daily_calls_30d,
    
    -- Número de días del mismo día de semana con data
    COUNT(DISTINCT created_date) AS days_with_data
    
  FROM (
    SELECT
      organization_code,
      organization_name,
      country,
      created_date,
      COUNT(*) AS daily_calls_until_now
    FROM ai_calls_detail
    WHERE 
      created_date >= CURRENT_DATE() - INTERVAL 30 DAY
      AND created_date < CURRENT_DATE()
      -- Solo días del mismo día de semana
      AND DAYOFWEEK(created_date) = DAYOFWEEK(CURRENT_DATE())
      -- Solo llamadas hasta la misma hora del día
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
  ) daily_stats
  GROUP BY organization_code, organization_name, country
),

volume_comparison AS (
  SELECT
    COALESCE(t.organization_code, l.organization_code, b.organization_code) AS organization_code,
    COALESCE(t.organization_name, l.organization_name, b.organization_name) AS organization_name,
    COALESCE(t.country, l.country, b.country) AS country,
    
    CURRENT_TIMESTAMP() AS alert_timestamp,
    EXTRACT(HOUR FROM CURRENT_TIMESTAMP()) AS current_hour,
    
    -- Today's volume
    COALESCE(t.total_calls, 0) AS today_calls,
    COALESCE(t.completed_calls, 0) AS today_completed_calls,
    COALESCE(t.total_minutes, 0) AS today_minutes,
    
    -- Last week same day volume
    COALESCE(l.total_calls, 0) AS lastweek_calls,
    COALESCE(l.completed_calls, 0) AS lastweek_completed_calls,
    COALESCE(l.total_minutes, 0) AS lastweek_minutes,
    
    -- Baseline 30 días (mismo día de semana)
    COALESCE(b.avg_daily_calls_30d, 0) AS baseline_30d_avg_calls,
    COALESCE(b.days_with_data, 0) AS baseline_days_count,
    
    -- Ratio vs last week
    ROUND(
      CAST(COALESCE(t.total_calls, 0) AS FLOAT) / NULLIF(l.total_calls, 0),
      4
    ) AS volume_ratio_vs_lastweek,
    
    -- Ratio vs 30d baseline (mismo día de semana)
    ROUND(
      CAST(COALESCE(t.total_calls, 0) AS FLOAT) / NULLIF(b.avg_daily_calls_30d, 0),
      4
    ) AS volume_ratio_vs_30d_avg,
    
    -- Absolute changes
    (COALESCE(t.total_calls, 0) - COALESCE(l.total_calls, 0)) AS absolute_volume_change_vs_lastweek,
    (COALESCE(t.total_calls, 0) - COALESCE(b.avg_daily_calls_30d, 0)) AS absolute_volume_change_vs_30d,
    
    -- Severity determination (DUAL BASELINE: requiere AMBOS criterios)
    CASE
      -- Insufficient data
      WHEN COALESCE(b.days_with_data, 0) < 3
        OR COALESCE(b.avg_daily_calls_30d, 0) < 30
        OR COALESCE(l.total_calls, 0) < 50
        THEN 'INSUFFICIENT_DATA'
      
      -- Critical: Drop > 30% vs AMBOS baselines
      WHEN CAST(COALESCE(t.total_calls, 0) AS FLOAT) / NULLIF(l.total_calls, 0) < 0.70
        AND CAST(COALESCE(t.total_calls, 0) AS FLOAT) / NULLIF(b.avg_daily_calls_30d, 0) < 0.70
        THEN 'CRITICAL'
      
      -- Warning: Drop 10-30% vs AMBOS baselines
      WHEN CAST(COALESCE(t.total_calls, 0) AS FLOAT) / NULLIF(l.total_calls, 0) < 0.90
        AND CAST(COALESCE(t.total_calls, 0) AS FLOAT) / NULLIF(b.avg_daily_calls_30d, 0) < 0.90
        THEN 'WARNING'
      
      ELSE 'FINE'
    END AS alert_severity
    
  FROM today_volume t
  FULL OUTER JOIN lastweek_volume l
    ON t.organization_code = l.organization_code
    AND t.country = l.country
  FULL OUTER JOIN baseline_30d_avg b
    ON COALESCE(t.organization_code, l.organization_code) = b.organization_code
    AND COALESCE(t.country, l.country) = b.country
)

-- ==============================================================================
-- METRICS VIEW: Vista Informativa Completa (Sin filtros de alerta)
-- ==============================================================================
-- Muestra todas las organizaciones con sus métricas de volumen comparando:
-- - Today vs Last Week Same Day
-- - Today vs Same-Weekday Average (last 30 days)
-- 
-- Útil para monitoreo general, análisis de tendencias y detección temprana
-- ==============================================================================

SELECT
  alert_timestamp AS datetime,
  organization_name,
  country,
  today_calls AS T_Calls,
  lastweek_calls AS LW_Calls,
  ROUND(baseline_30d_avg_calls, 0) AS 30D_AVG_Calls,
  volume_ratio_vs_lastweek AS T_v_LW_ratio,
  volume_ratio_vs_30d_avg AS T_v_30D_ratio,
  today_completed_calls AS T_completed_calls,
  lastweek_completed_calls AS LW_completed_calls,
  baseline_days_count AS 30D_weekday_count,
  current_hour,
  alert_severity
FROM volume_comparison
-- WHERE
  -- current_hour >= 13  -- Optional: Only show after 13h to have sufficient data
ORDER BY
  alert_severity,
  T_v_30D_ratio ASC,
  organization_name;
-- ==============================================================================
-- Alert 4 - METRICS VIEW: Short Call Rate Metrics (Informativa sin filtros)
-- ==============================================================================
-- Muestra métricas de short call rate con detección estadística de anomalías
-- basada en los últimos 30 días.
-- 
-- PERIODO: Últimos 7 días desde CURRENT_DATE()
-- Esta es la vista informativa completa, sin filtros de alerta.
-- Útil para monitoreo general y análisis de tendencias.
-- ==============================================================================

WITH current_hour_metrics AS (
  SELECT
  created_hour,
    organization_code,
    organization_name,
    country,
    
    -- Contar directamente de detail
    COUNT(*) AS total_calls,
    SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END) AS completed_calls,
    SUM(CASE WHEN call_classification = 'good_calls' THEN 1 ELSE 0 END) AS good_calls,
    SUM(CASE WHEN call_classification = 'short_calls' THEN 1 ELSE 0 END) AS short_calls,
    
    -- Short call rate calculado
    ROUND(
      CAST(SUM(CASE WHEN call_classification = 'short_calls' THEN 1 ELSE 0 END) AS FLOAT) / 
      NULLIF(SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END), 0),
      4
    ) AS short_call_rate,
    
    -- Average duration
    ROUND(AVG(call_duration_seconds), 2) AS avg_call_duration_seconds
        
  FROM ai_calls_detail
  WHERE 
    created_date >= CURRENT_DATE() - INTERVAL 7 DAY  -- Últimos 7 días
    [[AND {{organization_name}}]]
    [[AND {{countries}}]]
  GROUP BY created_hour, organization_code, organization_name, country
),

anomaly_detection AS (
  SELECT
    curr.organization_code,
    curr.organization_name,
    curr.country,
    
    curr.created_hour AS alert_timestamp,
    EXTRACT(HOUR FROM curr.created_hour) AS current_hour,
    
    -- Current metrics
    curr.total_calls AS current_total_calls,
    curr.completed_calls AS current_completed_calls,
    curr.good_calls AS current_good_calls,
    curr.short_calls AS current_short_calls,
    curr.short_call_rate AS current_short_call_rate,
    curr.avg_call_duration_seconds AS current_avg_duration,
    
    -- Baseline statistics (from last 30 days)
    base.avg_short_call_rate_30d AS baseline_short_call_rate,
    base.stddev_short_call_rate_30d AS baseline_stddev,
    base.p50_short_call_rate_30d AS baseline_median,
    base.p95_short_call_rate_30d AS baseline_p95,
    base.short_call_rate_upper_threshold,
    base.sample_size_30d AS baseline_sample_size,
    
    -- Deviation from baseline (in standard deviations)
    CASE 
      WHEN base.stddev_short_call_rate_30d > 0 
      THEN ROUND(
        (curr.short_call_rate - base.avg_short_call_rate_30d) / base.stddev_short_call_rate_30d,
        2
      )
      ELSE 0
    END AS sigma_deviation,
    
    -- Severity determination
    CASE
      -- Insufficient data
      WHEN curr.completed_calls < 10 
        OR base.sample_size_30d < 10
        -- OR base.has_sufficient_baseline_data = FALSE
        THEN 'INSUFFICIENT_DATA'
      
      -- Critical: > 3 standard deviations or > P95 by large margin
      WHEN curr.short_call_rate > base.avg_short_call_rate_30d + 3 * base.stddev_short_call_rate_30d
        OR (curr.short_call_rate > base.p95_short_call_rate_30d * 1.2 AND curr.short_calls >= 10)
        THEN 'CRITICAL'
      
      -- Warning: > 2 standard deviations
      WHEN curr.short_call_rate > base.avg_short_call_rate_30d + 2 * base.stddev_short_call_rate_30d
        AND curr.short_calls >= 5
        THEN 'WARNING'
      
      ELSE 'FINE'
    END AS alert_severity
    
  FROM current_hour_metrics curr
  INNER JOIN alerts_baseline_stats base
    ON curr.organization_code = base.organization_code
    AND curr.country = base.country
    AND EXTRACT(HOUR FROM curr.created_hour) = base.hour_of_day
)

-- ==============================================================================
-- METRICS VIEW: Vista Informativa Completa (Sin filtros de alerta)
-- ==============================================================================
-- Muestra todas las organizaciones con sus métricas de short call rate
-- Útil para monitoreo general, análisis de tendencias y detección temprana
-- ==============================================================================

SELECT
  alert_timestamp AS datetime,
  organization_name,
  country,
  current_total_calls AS T_Calls,
  current_completed_calls AS T_completed_calls,
  current_short_calls AS T_short_calls,
  current_good_calls AS T_good_calls,
  current_short_call_rate AS T_rate,
  baseline_short_call_rate AS 30D_AVG_rate,
  sigma_deviation,
  baseline_sample_size AS 30D_sample_size,
  current_hour,
  alert_severity
FROM anomaly_detection
-- WHERE
  -- current_hour BETWEEN 6 AND 23  -- Operational hours only (6AM-11PM)
ORDER BY
  alert_severity,
  sigma_deviation DESC,
  organization_name;


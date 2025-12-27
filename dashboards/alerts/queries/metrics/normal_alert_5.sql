-- ==============================================================================
-- Alert 5 - METRICS VIEW: Call Duration Metrics (Informativa sin filtros)
-- ==============================================================================
-- Muestra métricas de duración de llamadas con detección estadística de anomalías
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
    SUM(call_duration_seconds) AS total_call_seconds,
    SUM(call_duration_minutes) AS total_call_minutes,
    
    -- Average duration calculado
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
    curr.total_call_seconds AS current_total_seconds,
    curr.total_call_minutes AS current_total_minutes,
    curr.avg_call_duration_seconds AS current_avg_duration,
    
    -- Baseline statistics (from last 30 days)
    base.avg_call_duration_30d AS baseline_avg_duration,
    base.stddev_call_duration_30d AS baseline_stddev,
    base.p25_call_duration_30d AS baseline_p25,
    base.p50_call_duration_30d AS baseline_median,
    base.p75_call_duration_30d AS baseline_p75,
    base.call_duration_lower_threshold,
    base.call_duration_upper_threshold,
    base.sample_size_30d AS baseline_sample_size,
    
    -- Deviation from baseline (in standard deviations)
    CASE 
      WHEN base.stddev_call_duration_30d > 0 
      THEN ROUND(
        (curr.avg_call_duration_seconds - base.avg_call_duration_30d) / base.stddev_call_duration_30d,
        2
      )
      ELSE 0
    END AS sigma_deviation,
    
    -- Anomaly type
    CASE 
      WHEN curr.avg_call_duration_seconds < base.call_duration_lower_threshold
        THEN 'TOO_SHORT'
      WHEN curr.avg_call_duration_seconds > base.call_duration_upper_threshold
        THEN 'TOO_LONG'
      ELSE 'NORMAL'
    END AS anomaly_type,
    
    -- Severity determination
    CASE
      -- Insufficient data
      WHEN curr.completed_calls < 10 
        OR base.sample_size_30d < 10
        -- OR base.has_sufficient_baseline_data = FALSE
        THEN 'INSUFFICIENT_DATA'
      
      -- Critical: > 3 standard deviations
      WHEN ABS(curr.avg_call_duration_seconds - base.avg_call_duration_30d) > 3 * base.stddev_call_duration_30d
        THEN 'CRITICAL'
      
      -- Warning: > 2 standard deviations
      WHEN ABS(curr.avg_call_duration_seconds - base.avg_call_duration_30d) > 2 * base.stddev_call_duration_30d
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
-- Muestra todas las organizaciones con sus métricas de duración de llamadas
-- Útil para monitoreo general, análisis de tendencias y detección temprana
-- ==============================================================================

SELECT
  alert_timestamp AS datetime,
  organization_name,
  country,
  current_total_calls AS T_Calls,
  current_completed_calls AS T_completed_calls,
  anomaly_type,
  current_avg_duration AS T_avg_duration_seconds,
  baseline_avg_duration AS 30D_AVG_duration_seconds,
  sigma_deviation,
  ROUND(call_duration_lower_threshold, 1) AS 30D_lower_threshold_seconds,
  ROUND(call_duration_upper_threshold, 1) AS 30D_upper_threshold_seconds,
  baseline_sample_size AS 30D_sample_size,
  current_hour,
  alert_severity
FROM anomaly_detection
-- WHERE
  -- current_hour BETWEEN 6 AND 23  -- Operational hours only (6AM-11PM)
ORDER BY
  alert_severity,
  ABS(sigma_deviation) DESC,
  organization_name;


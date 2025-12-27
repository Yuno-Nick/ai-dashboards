-- ==============================================================================
-- Alert 5: Call Duration Anomaly - ALERT VIEW (Solo alertas CRITICAL y WARNING)
-- ==============================================================================
-- Detecta anomalías en la duración promedio de llamadas usando estadísticas
-- basadas en los últimos 30 días. Alerta cuando duración está fuera de media ± 2σ
-- Usa ai_calls_detail + alerts_baseline_stats
--
-- Esta es la vista de alertas TIEMPO REAL, solo muestra CRITICAL y WARNING con mensaje.
-- Para la vista completa sin filtros, ver: normal_alert_5.sql
-- ==============================================================================

WITH current_hour_realtime AS (
  SELECT
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
    created_hour = date_trunc('hour', CURRENT_TIMESTAMP())
    [[AND {{organization_name}}]]
    [[AND {{countries}}]]
  GROUP BY organization_code, organization_name, country
),

anomaly_detection_realtime AS (
  SELECT
    curr.organization_code,
    curr.organization_name,
    curr.country,
    
    CURRENT_TIMESTAMP() AS alert_timestamp,
    EXTRACT(HOUR FROM CURRENT_TIMESTAMP()) AS current_hour,
    
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
    
  FROM current_hour_realtime curr
  INNER JOIN alerts_baseline_stats base
    ON curr.organization_code = base.organization_code
    AND curr.country = base.country
    AND EXTRACT(HOUR FROM CURRENT_TIMESTAMP()) = base.hour_of_day
)

SELECT
  datetime,
  T_avg_duration_seconds,
  30D_AVG_duration_seconds,
  sigma_deviation,
  alert_message
FROM (
  SELECT
    alert_timestamp AS datetime,
    organization_name,
    country,
    current_avg_duration AS T_avg_duration_seconds,
    baseline_avg_duration AS 30D_AVG_duration_seconds,
    sigma_deviation,
    anomaly_type,
    alert_severity,
    
    -- Alert message
    CASE
      WHEN alert_severity = 'INSUFFICIENT_DATA'
        THEN 'Alert suppressed: Insufficient data (min 20 completed calls and 10 day baseline required)'
      
      WHEN alert_severity = 'CRITICAL' AND anomaly_type = 'TOO_SHORT'
        THEN CONCAT('CRITICAL: ', organization_name, ' (', country, ') - Call duration ANOMALY: Unusually SHORT! ',
             'Current avg: ', CAST(ROUND(current_avg_duration, 0) AS VARCHAR), 's ',
             'vs Baseline: ', CAST(ROUND(baseline_avg_duration, 0) AS VARCHAR), 's ',
             '(', CAST(sigma_deviation AS VARCHAR), 'σ below normal)')
      
      WHEN alert_severity = 'CRITICAL' AND anomaly_type = 'TOO_LONG'
        THEN CONCAT('CRITICAL: ', organization_name, ' (', country, ') - Call duration ANOMALY: Unusually LONG! ',
             'Current avg: ', CAST(ROUND(current_avg_duration, 0) AS VARCHAR), 's ',
             'vs Baseline: ', CAST(ROUND(baseline_avg_duration, 0) AS VARCHAR), 's ',
             '(+', CAST(sigma_deviation AS VARCHAR), 'σ above normal)')
      
      WHEN alert_severity = 'WARNING' AND anomaly_type = 'TOO_SHORT'
        THEN CONCAT('WARNING: ', organization_name, ' (', country, ') - Shorter than usual call duration. ',
             'Current: ', CAST(ROUND(current_avg_duration, 0) AS VARCHAR), 's ',
             'vs Baseline: ', CAST(ROUND(baseline_avg_duration, 0) AS VARCHAR), 's')
      
      WHEN alert_severity = 'WARNING' AND anomaly_type = 'TOO_LONG'
        THEN CONCAT('WARNING: ', organization_name, ' (', country, ') - Longer than usual call duration. ',
             'Current: ', CAST(ROUND(current_avg_duration, 0) AS VARCHAR), 's ',
             'vs Baseline: ', CAST(ROUND(baseline_avg_duration, 0) AS VARCHAR), 's')
      
      ELSE 'FINE: Call duration within normal range'
    END AS alert_message
  
  FROM anomaly_detection_realtime
  WHERE
    alert_severity IN ('CRITICAL', 'WARNING')
    AND current_hour BETWEEN 6 AND 23  -- Operational hours only
    AND current_completed_calls >= 20   -- Minimum sample size
) subquery
ORDER BY
  alert_message DESC;




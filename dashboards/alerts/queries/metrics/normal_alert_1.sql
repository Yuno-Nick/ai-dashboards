-- ==============================================================================
-- Alert 1: Hourly Call Quality Degradation (vs semana pasada)
-- ==============================================================================
-- Detecta degradación de calidad comparando la hora actual con la misma hora
-- de la semana pasada. Alerta cuando quality_rate < 85% del baseline.
-- Usa directamente ai_calls_detail con GROUP BY (optimizado para 2k calls/día)
-- ==============================================================================

WITH current_hour_stats AS (
  SELECT
    organization_code,
    organization_name,
    country,
	created_hour,
    
    -- Contar directamente de detail
    COUNT(*) AS total_calls,
    SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END) AS completed_calls,
    SUM(CASE WHEN call_classification = 'good_calls' THEN 1 ELSE 0 END) AS good_calls,
    SUM(CASE WHEN call_classification = 'short_calls' THEN 1 ELSE 0 END) AS short_calls,
    SUM(call_duration_minutes) AS total_minutes,
    
    -- Quality rate
    ROUND(
      CAST(SUM(CASE WHEN call_classification = 'good_calls' THEN 1 ELSE 0 END) AS FLOAT) / 
      NULLIF(SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END), 0),
      4
    ) AS quality_rate
    
  FROM ai_calls_detail
  WHERE
  TRUE
	AND created_hour = date_trunc('hour', CURRENT_TIMESTAMP())
   [[AND {{organization_name}}]]
   [[AND {{countries}}]]
  GROUP BY organization_code, organization_name, country, created_hour
),

lastweek_hour_stats AS (
  SELECT
    organization_code,
    organization_name,
    country,
	created_hour,
    
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
  TRUE
    AND created_hour = date_trunc('hour', CURRENT_TIMESTAMP() - INTERVAL 1 WEEK)
    [[AND {{organization_name}}]]
    [[AND {{countries}}]]
  GROUP BY organization_code, organization_name, country, created_hour
),

hourly_comparison AS (
  SELECT
    COALESCE(c.organization_code, l.organization_code) AS organization_code,
    COALESCE(c.organization_name, l.organization_name) AS organization_name,
    COALESCE(c.country, l.country) AS country,
    
    CURRENT_TIMESTAMP() AS alert_timestamp,
    EXTRACT(HOUR FROM CURRENT_TIMESTAMP()) AS current_hour,
    
    -- Current period metrics
    COALESCE(c.total_calls, 0) AS current_total_calls,
    COALESCE(c.completed_calls, 0) AS current_completed_calls,
    COALESCE(c.good_calls, 0) AS current_good_calls,
    COALESCE(c.short_calls, 0) AS current_short_calls,
    COALESCE(c.total_minutes, 0) AS current_total_minutes,
    COALESCE(c.quality_rate, 0) AS current_quality_rate,
    
    -- Last week same hour metrics
    COALESCE(l.total_calls, 0) AS lastweek_total_calls,
    COALESCE(l.completed_calls, 0) AS lastweek_completed_calls,
    COALESCE(l.good_calls, 0) AS lastweek_good_calls,
    COALESCE(l.short_calls, 0) AS lastweek_short_calls,
    COALESCE(l.total_minutes, 0) AS lastweek_total_minutes,
    COALESCE(l.quality_rate, 0) AS lastweek_quality_rate,
    
    -- Comparison metrics
    ROUND(
      COALESCE(c.quality_rate, 0) / NULLIF(l.quality_rate, 0),
      4
    ) AS quality_ratio_vs_lastweek,
    
    (COALESCE(c.good_calls, 0) - COALESCE(l.good_calls, 0)) AS absolute_good_calls_change,
    
    -- Severity determination (Umbrales estandarizados)
    CASE
      -- Insufficient data
      WHEN COALESCE(c.completed_calls, 0) < 20 OR COALESCE(l.completed_calls, 0) < 20 
        THEN 'INSUFFICIENT_DATA'
      
      -- Critical: Drop > 30% (quality < 70% of baseline)
      WHEN COALESCE(c.quality_rate, 0) / NULLIF(l.quality_rate, 0) < 0.70
        THEN 'CRITICAL'
      
      -- Warning: Drop 10-30% (quality 70-90% of baseline)
      WHEN COALESCE(c.quality_rate, 0) / NULLIF(l.quality_rate, 0) < 0.90
        THEN 'WARNING'
      
      ELSE 'FINE'
    END AS alert_severity
    
  FROM current_hour_stats c
  FULL OUTER JOIN lastweek_hour_stats l
    ON c.organization_code = l.organization_code
    AND c.country = l.country
)

-- ==============================================================================
-- VIEW 1: METRICS VIEW (Informativa - Sin filtros)
-- ==============================================================================
-- Muestra todas las organizaciones con sus métricas de calidad horaria
-- Útil para monitoreo general y análisis de tendencias
-- ==============================================================================

SELECT
  alert_timestamp AS datetime,
  organization_name,
  country,
  current_total_calls AS T_Calls,
  lastweek_total_calls AS LW_Calls,
  current_quality_rate AS T_rate,
  lastweek_quality_rate AS LW_rate,
  quality_ratio_vs_lastweek AS T_v_LW_ratio,
  current_good_calls AS T_good_calls,
  current_completed_calls AS T_completed_calls,
  lastweek_good_calls AS LW_good_calls,
  lastweek_completed_calls AS LW_completed_calls,
  current_hour,
  alert_severity
FROM hourly_comparison
WHERE
  current_hour BETWEEN 6 AND 23  -- Operational hours only (6AM-11PM)
ORDER BY
  alert_severity,
  T_v_LW_ratio ASC,
  organization_name;
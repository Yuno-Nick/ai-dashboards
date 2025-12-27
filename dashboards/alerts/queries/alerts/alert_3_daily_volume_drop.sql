-- ==============================================================================
-- Alert 3: Daily Volume Drop (DUAL BASELINE: semana pasada + promedio mismo día)
-- ==============================================================================
-- Detecta caídas de volumen significativas usando DOBLE VALIDACIÓN:
-- 
-- BASELINES:
-- 1. Semana pasada mismo día/hora: Comparación WoW (Week over Week)
-- 2. Promedio de los últimos 30 días del MISMO DÍA DE SEMANA hasta misma hora
--    Ej: Si hoy es Lunes 14:00, promedia todos los Lunes hasta las 14:00
-- 
-- CRITERIO DE ALERTA (requiere AMBAS condiciones):
-- - WARNING: today < 90% de last_week_same_day AND today < 90% de avg_same_weekday_30d
-- - CRITICAL: today < 70% de last_week_same_day AND today < 70% de avg_same_weekday_30d
--
-- Esto reduce falsos positivos causados por volatilidad semanal o anomalías puntuales
-- ==============================================================================

WITH today_volume AS (
  SELECT
    organization_code,
    organization_name,
    country,
	created_date,
	-- created_at,
    
    COUNT(*) AS total_calls,
    SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END) AS completed_calls,
    SUM(call_duration_minutes) AS total_minutes
    
  FROM ai_calls_detail
  WHERE 
    created_date = CURRENT_DATE()
    AND created_at < CURRENT_TIMESTAMP()
    -- [[AND {{organization_name}}]]
    -- [[AND {{countries}}]]
  GROUP BY organization_code, organization_name, country, created_date
),

lastweek_volume AS (
  SELECT
    organization_code,
    organization_name,
    country,
	created_date,
	-- created_at,
    
    COUNT(*) AS total_calls,
    SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END) AS completed_calls,
    SUM(call_duration_minutes) AS total_minutes
    
  FROM ai_calls_detail
  WHERE 
    created_date = CURRENT_DATE() - INTERVAL 7 DAY
    AND created_at < CURRENT_TIMESTAMP() - INTERVAL 7 DAY
    -- [[AND {{organization_name}}]]
    -- [[AND {{countries}}]]
  GROUP BY organization_code, organization_name, country, created_date
),

-- NEW: Promedio de llamadas acumuladas hasta la hora actual (mismo día de semana, últimos 30 días)
-- Ej: Si hoy es Lunes, promedia solo los Lunes de los últimos 30 días hasta esta misma hora
baseline_30d_avg AS (
  SELECT
    organization_code,
    organization_name,
    country,
    
    -- Promedio de llamadas acumuladas hasta la hora actual (mismo día de semana)
    ROUND(AVG(daily_calls_until_now), 2) AS avg_daily_calls_30d,
    
    -- Número de días del mismo día de semana con data (ej: cuántos Lunes)
    COUNT(DISTINCT created_date) AS days_with_data
    
  FROM (
    SELECT
      organization_code,
      organization_name,
      country,
      created_date,
      -- Contar solo llamadas hasta la misma hora del día actual
      COUNT(*) AS daily_calls_until_now,
      SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END) AS daily_completed_calls_until_now,
      SUM(call_duration_minutes) AS daily_minutes_until_now
    FROM ai_calls_detail
    WHERE 
      created_date >= CURRENT_DATE() - INTERVAL 30 DAY
      AND created_date < CURRENT_DATE()  -- Excluye el día de hoy
      -- NUEVO: Solo días del mismo día de semana (Lunes con Lunes, etc.)
      AND DAYOFWEEK(created_date) = DAYOFWEEK(CURRENT_DATE())
      -- Solo llamadas hasta la misma hora del día (comparación por hora:minuto)
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
    
    -- Baseline 30 días (promedio simple)
    COALESCE(b.avg_daily_calls_30d, 0) AS baseline_30d_avg_calls,
    COALESCE(b.days_with_data, 0) AS baseline_days_count,
    
    -- Volume ratio vs last week
    ROUND(
      CAST(COALESCE(t.total_calls, 0) AS FLOAT) / NULLIF(l.total_calls, 0),
      4
    ) AS volume_ratio_vs_lastweek,
    
    -- NEW: Volume ratio vs 30d baseline
    ROUND(
      CAST(COALESCE(t.total_calls, 0) AS FLOAT) / NULLIF(b.avg_daily_calls_30d, 0),
      4
    ) AS volume_ratio_vs_30d_avg,
    
    -- Absolute changes
    (COALESCE(t.total_calls, 0) - COALESCE(l.total_calls, 0)) AS absolute_volume_change_vs_lastweek,
    (COALESCE(t.total_calls, 0) - COALESCE(b.avg_daily_calls_30d, 0)) AS absolute_volume_change_vs_30d,
    
    -- Severity determination (requiere AMBOS criterios: lastweek AND 30d avg)
    CASE
      -- Insufficient data (requiere al menos 3 días del mismo día de semana)
      WHEN COALESCE(b.days_with_data, 0) < 3  -- Mínimo 3 días (ej: 3 Lunes en últimos 30 días)
        OR COALESCE(b.avg_daily_calls_30d, 0) < 30
        OR COALESCE(l.total_calls, 0) < 50
        THEN 'INSUFFICIENT_DATA'
      
      -- Critical: Drop > 30% vs AMBOS baselines (lastweek AND 30d avg)
      WHEN CAST(COALESCE(t.total_calls, 0) AS FLOAT) / NULLIF(l.total_calls, 0) < 0.70
        AND CAST(COALESCE(t.total_calls, 0) AS FLOAT) / NULLIF(b.avg_daily_calls_30d, 0) < 0.70
        THEN 'CRITICAL'
      
      -- Warning: Drop 10-30% vs AMBOS baselines (lastweek AND 30d avg)
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

SELECT
  datetime,
  T_Calls,
  LW_Calls,
  30D_AVG_Calls,
  T_v_LW_ratio,
  T_v_30D_ratio,
  alert_message
FROM (
  SELECT
    alert_timestamp AS datetime,
    organization_name,
    country,
    today_calls AS T_Calls,
    lastweek_calls AS LW_Calls,
    ROUND(baseline_30d_avg_calls, 0) AS 30D_AVG_Calls,
    volume_ratio_vs_lastweek AS T_v_LW_ratio,
    volume_ratio_vs_30d_avg AS T_v_30D_ratio,
    alert_severity,
    
    -- Alert message (menciona ambos baselines: semana pasada + promedio mismo día)
    CASE
      WHEN alert_severity = 'INSUFFICIENT_DATA'
        THEN 'Alert suppressed: Insufficient baseline data (min 3 same-weekdays with 30+ calls/day and 50 calls last week)'
      
      WHEN alert_severity = 'CRITICAL'
        THEN CONCAT('CRITICAL: ', organization_name, ' (', country, ') - Call volume dropped by ',
             CAST(ROUND((1 - volume_ratio_vs_lastweek) * 100, 1) AS VARCHAR),
             '% vs last week AND ',
             CAST(ROUND((1 - volume_ratio_vs_30d_avg) * 100, 1) AS VARCHAR),
             '% below same-weekday avg (last 30d). Today: ', CAST(today_calls AS VARCHAR), 
             ' calls vs Last Week: ', CAST(lastweek_calls AS VARCHAR), 
             ' calls (Same-Weekday Avg: ', CAST(ROUND(baseline_30d_avg_calls, 0) AS VARCHAR), ')')
      
      WHEN alert_severity = 'WARNING'
        THEN CONCAT('WARNING: ', organization_name, ' (', country, ') - Call volume dropped by ',
             CAST(ROUND((1 - volume_ratio_vs_lastweek) * 100, 1) AS VARCHAR),
             '% vs last week AND ',
             CAST(ROUND((1 - volume_ratio_vs_30d_avg) * 100, 1) AS VARCHAR),
             '% below same-weekday avg. Today: ', CAST(today_calls AS VARCHAR), 
             ' calls vs Last Week: ', CAST(lastweek_calls AS VARCHAR))
      
      ELSE 'FINE: Volume within acceptable range'
    END AS alert_message
  
  FROM volume_comparison
  WHERE
    alert_severity IN ('CRITICAL', 'WARNING')
    AND current_hour >= 13  -- Only alert after 13h to have sufficient data
    AND baseline_days_count >= 3  -- Minimum 3 días del mismo día de semana
    AND lastweek_calls >= 50  -- Minimum baseline volume
) subquery
ORDER BY
  alert_message DESC

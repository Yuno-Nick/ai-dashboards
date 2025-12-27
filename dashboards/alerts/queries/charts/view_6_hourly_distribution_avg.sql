-- ==============================================================================
-- View 6: Hourly Distribution Average (Using ai_calls_detail)
-- ==============================================================================
-- Muestra el promedio de llamadas por hora del día
-- Útil para identificar patrones de volumen de llamadas a lo largo del día
-- ==============================================================================

WITH counted AS (
  SELECT
    created_hour AS hour,
    hour_of_day,
    COUNT(*) AS total_calls
  FROM ai_calls_detail
  WHERE
    TRUE
    [[AND {{time}}]]
    [[AND {{organization_name}}]]
    [[AND {{countries}}]]
  GROUP BY created_hour, hour_of_day
)
SELECT
  hour_of_day,
  AVG(total_calls) AS average,
  MIN(total_calls) AS minimum,
  MAX(total_calls) AS maximum,
  SUM(total_calls) AS total_calls,
  COUNT(*) AS counted_days
FROM counted
GROUP BY hour_of_day
ORDER BY hour_of_day
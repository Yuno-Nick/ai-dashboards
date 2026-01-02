SELECT 
  organization_name,
  country,
  SUM(revenue) AS revenue,
  COUNT(*) AS comunicaciones,
  SUM(CASE WHEN is_billable THEN 1 ELSE 0 END) AS billables,
  ROUND(SUM(CASE WHEN is_billable THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS tasa_facturable_pct
FROM `abstract-prod`.ai_revenue_mart
WHERE revenue_month = DATE_TRUNC('month', CURRENT_DATE())
--   [[ AND organization_name = {{organization_name}} ]]
--   [[ AND country = {{country}} ]]
--   [[ AND product = {{product}} ]]
GROUP BY organization_name, country
ORDER BY revenue DESC
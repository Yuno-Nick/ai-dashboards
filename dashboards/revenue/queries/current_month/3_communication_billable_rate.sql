SELECT ROUND(SUM(CASE WHEN is_billable THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 1) AS tasa_facturable_pct
FROM `abstract-prod`.ai_revenue_mart
WHERE revenue_month = DATE_TRUNC('month', CURRENT_DATE())
  [[ AND {{organization_name}} ]]
  [[ AND {{country}} ]]
  [[ AND {{product}} ]]
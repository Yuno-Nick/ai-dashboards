SELECT 
  day_of_month,
  SUM(CASE WHEN revenue_month = DATE_TRUNC('month', CURRENT_DATE()) THEN revenue ELSE 0 END) AS revenue_mes_actual,
  SUM(CASE WHEN revenue_month = DATE_TRUNC('month', DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH)) THEN revenue ELSE 0 END) AS revenue_mes_anterior
FROM `abstract-prod`.ai_revenue_mart
WHERE revenue_month IN (
    DATE_TRUNC('month', CURRENT_DATE()),
    DATE_TRUNC('month', DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH))
  )
  AND day_of_month <= EXTRACT(DAY FROM CURRENT_DATE())
  [[ AND {{organization_name}} ]]
  [[ AND {{country}} ]]
  [[ AND {{product}} ]]
GROUP BY day_of_month
ORDER BY day_of_month
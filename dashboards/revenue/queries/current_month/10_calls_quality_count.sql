SELECT 
  call_classification,
  COUNT(*) AS cantidad,
  SUM(revenue) AS revenue
FROM `abstract-prod`.ai_revenue_mart
WHERE revenue_month = DATE_TRUNC('month', CURRENT_DATE())
  AND product = 'PHONE_CALL'
  [[ AND {{organization_name}} ]]
  [[ AND {{country}} ]]
GROUP BY call_classification
ORDER BY cantidad DESC
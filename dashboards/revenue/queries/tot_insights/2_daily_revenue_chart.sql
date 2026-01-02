SELECT 
  revenue_date,
  SUM(revenue) AS revenue,
  COUNT(*) AS comunicaciones
FROM `abstract-prod`.ai_revenue_mart
WHERE
TRUE
[[ AND {{revenue_date}}]]
  [[ AND {{organization_name}} ]]
  [[ AND {{country}} ]]
  [[ AND {{product}} ]]
GROUP BY revenue_date
ORDER BY revenue_date
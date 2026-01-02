SELECT SUM(revenue) AS revenue_mtd
FROM `abstract-prod`.ai_revenue_mart
WHERE revenue_month = DATE_TRUNC('month', CURRENT_DATE())
  [[ AND {{organization_name}} ]]
  [[ AND {{country}} ]]
  [[ AND {{product}} ]]

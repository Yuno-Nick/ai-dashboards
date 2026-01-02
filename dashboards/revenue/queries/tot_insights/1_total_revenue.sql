SELECT SUM(revenue) AS revenue
FROM `abstract-prod`.ai_revenue_mart
WHERE 
TRUE
	[[AND {{revenue_date}}]]
  [[ AND {{organization_name}} ]]
  [[ AND {{country}} ]]
  [[ AND {{product}} ]]
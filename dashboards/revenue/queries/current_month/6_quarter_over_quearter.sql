WITH actual AS (
  SELECT SUM(revenue) AS revenue
  FROM `abstract-prod`.ai_revenue_mart
  WHERE revenue_quarter = DATE_TRUNC('quarter', CURRENT_DATE())
    AND revenue_date <= CURRENT_DATE()
    [[ AND {{organization_name}} ]]
    [[ AND {{country}} ]]
    [[ AND {{product}} ]]
),
anterior AS (
  SELECT SUM(revenue) AS revenue
  FROM `abstract-prod`.ai_revenue_mart
  WHERE revenue_quarter = DATE_TRUNC('quarter', DATE_SUB(CURRENT_DATE(), INTERVAL 3 MONTH))
    AND DATEDIFF(revenue_date, revenue_quarter) <= DATEDIFF(CURRENT_DATE(), DATE_TRUNC('quarter', CURRENT_DATE()))
    [[ AND {{organization_name}} ]]
    [[ AND {{country}} ]]
    [[ AND {{product}} ]]
)
SELECT ROUND((a.revenue - b.revenue) * 100.0 / NULLIF(b.revenue, 0), 1) AS qoq_pct
FROM actual a, anterior b
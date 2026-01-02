WITH actual AS (
  SELECT SUM(revenue) AS revenue
  FROM `abstract-prod`.ai_revenue_mart
  WHERE revenue_month = DATE_TRUNC('month', CURRENT_DATE())
    [[ AND {{organization_name}} ]]
    [[ AND {{country}} ]]
    [[ AND {{product}} ]]
),
anterior AS (
  SELECT SUM(revenue) AS revenue
  FROM `abstract-prod`.ai_revenue_mart
  WHERE revenue_month = DATE_TRUNC('month', DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH))
    [[ AND {{organization_name}} ]]
    [[ AND {{country}} ]]
    [[ AND {{product}} ]]
)
SELECT ROUND((a.revenue - b.revenue) * 100.0 / NULLIF(b.revenue, 0), 1) AS yoy_pct
FROM actual a, anterior b
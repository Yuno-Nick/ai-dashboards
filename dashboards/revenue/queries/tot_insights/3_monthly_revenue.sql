WITH monthly AS (
  SELECT 
    revenue_month,
    SUM(revenue) AS revenue
  FROM `abstract-prod`.ai_revenue_mart
  WHERE
  TRUE
  [[AND {{revenue_date}}]]
    [[ AND {{organization_name}} ]]
    [[ AND {{country}} ]]
    [[ AND {{product}} ]]
  GROUP BY revenue_month
)
SELECT 
  revenue_month,
  revenue,
  LAG(revenue) OVER (ORDER BY revenue_month) AS revenue_anterior,
  ROUND((revenue - LAG(revenue) OVER (ORDER BY revenue_month)) * 100.0 / 
    NULLIF(LAG(revenue) OVER (ORDER BY revenue_month), 0), 1) AS mom_pct
FROM monthly
ORDER BY revenue_month DESC
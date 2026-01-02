WITH quarterly AS (
  SELECT 
    revenue_quarter,
    SUM(revenue) AS revenue
  FROM `abstract-prod`.ai_revenue_mart
  WHERE 
  TRUE
  [[AND {{date}}]]
    [[ AND {{organization_name}} ]]
    [[ AND {{country}} ]]
    [[ AND {{product}} ]]
  GROUP BY revenue_quarter
)
SELECT 
  revenue_quarter,
  revenue,
  LAG(revenue) OVER (ORDER BY revenue_quarter) AS revenue_anterior,
  ROUND((revenue - LAG(revenue) OVER (ORDER BY revenue_quarter)) * 100.0 / 
    NULLIF(LAG(revenue) OVER (ORDER BY revenue_quarter), 0), 1) AS qoq_pct
FROM quarterly
ORDER BY revenue_quarter DESC
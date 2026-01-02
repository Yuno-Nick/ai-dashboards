WITH daily_revenue AS (
  SELECT 
    revenue_date,
    revenue_quarter,
    DATEDIFF(revenue_date, revenue_quarter) + 1 AS day_of_quarter,
    SUM(revenue) AS revenue
  FROM `abstract-prod`.ai_revenue_mart
  WHERE revenue_quarter IN (
      DATE_TRUNC('quarter', CURRENT_DATE()),
      DATE_TRUNC('quarter', DATE_SUB(CURRENT_DATE(), INTERVAL 3 MONTH))
    )
    [[ AND {{organization_name}} ]]
    [[ AND {{country}} ]]
    [[ AND {{product}} ]]
  GROUP BY revenue_date, revenue_quarter
)
SELECT 
  day_of_quarter,
  SUM(CASE WHEN revenue_quarter = DATE_TRUNC('quarter', CURRENT_DATE()) THEN revenue ELSE 0 END) AS revenue_q_actual,
  SUM(CASE WHEN revenue_quarter = DATE_TRUNC('quarter', DATE_SUB(CURRENT_DATE(), INTERVAL 3 MONTH)) THEN revenue ELSE 0 END) AS revenue_q_anterior
FROM daily_revenue
WHERE day_of_quarter <= DATEDIFF(CURRENT_DATE(), DATE_TRUNC('quarter', CURRENT_DATE())) + 1
GROUP BY day_of_quarter
ORDER BY day_of_quarter
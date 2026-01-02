SELECT 
  revenue_month,
  DATE_FORMAT(revenue_month, '%Y-%m') AS mes,
  organization_name,
  country,
  SUM(CASE WHEN product = 'PHONE_CALL' THEN units ELSE 0 END) AS minutos_billables,
  SUM(CASE WHEN product = 'WHATSAPP_MESSAGE' THEN units ELSE 0 END) AS mensajes_billables,
  COUNT(CASE WHEN product = 'PHONE_CALL' THEN 1 END) AS total_llamadas,
  COUNT(CASE WHEN product = 'WHATSAPP_MESSAGE' THEN 1 END) AS total_whatsapp,
  SUM(revenue) AS revenue_total,
  SUM(CASE WHEN product = 'PHONE_CALL' THEN revenue ELSE 0 END) AS revenue_llamadas,
  SUM(CASE WHEN product = 'WHATSAPP_MESSAGE' THEN revenue ELSE 0 END) AS revenue_whatsapp
FROM `abstract-prod`.ai_revenue_mart
WHERE is_billable = TRUE
[[AND {{organization_name}}]]
  [[ AND {{call_classification}} ]]
  [[ AND {{organization_name}} ]]
  [[ AND {{country}} ]]
GROUP BY revenue_month, organization_name, country
ORDER BY revenue_month DESC
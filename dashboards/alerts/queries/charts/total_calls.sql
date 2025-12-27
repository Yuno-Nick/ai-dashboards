WITH hourly_data AS (
  SELECT
    created_date,
	country,
  	organization_name,
    hour_of_day,
    COUNT(*) AS total_calls,
    
    -- Indicador si es la hora actual (para destacar visualmente)
    CASE 
      WHEN created_date = CURRENT_DATE() 
        AND hour_of_day = EXTRACT(HOUR FROM CURRENT_TIMESTAMP())
        THEN 'CURRENT_HOUR'
      WHEN created_date = CURRENT_DATE()
        AND hour_of_day <= EXTRACT(HOUR FROM CURRENT_TIMESTAMP())
        THEN 'TODAY_COMPLETED'
      WHEN created_date = CURRENT_DATE()
        AND hour_of_day > EXTRACT(HOUR FROM CURRENT_TIMESTAMP())
        THEN 'TODAY_PENDING'
      ELSE 'PAST_DAY'
    END AS block_status,
    
    -- Etiqueta legible para tooltip
    CONCAT(
      CASE DAYOFWEEK(created_date)
        WHEN 1 THEN 'Dom'
        WHEN 2 THEN 'Lun'
        WHEN 3 THEN 'Mar'
        WHEN 4 THEN 'Mié'
        WHEN 5 THEN 'Jue'
        WHEN 6 THEN 'Vie'
        WHEN 7 THEN 'Sáb'
      END,
      ' ', CAST(created_date AS VARCHAR),
      ' - ', LPAD(CAST(hour_of_day AS VARCHAR), 2, '0'), ':00'
    ) AS block_label
    
  FROM ai_calls_detail
  WHERE
    TRUE
    [[AND {{time}}]]
	[[AND {{organization_name}}]]
    [[AND {{countries}}]]
  GROUP BY created_date, hour_of_day, country, organization_name
)

SELECT
  created_date,
  organization_name,
  country,
  hour_of_day,
  total_calls,
  block_status,
  block_label,
  
  -- Formato de fecha más legible (Día de la semana + fecha)
  CONCAT(
    CASE DAYOFWEEK(created_date)
      WHEN 1 THEN 'Domingo'
      WHEN 2 THEN 'Lunes'
      WHEN 3 THEN 'Martes'
      WHEN 4 THEN 'Miércoles'
      WHEN 5 THEN 'Jueves'
      WHEN 6 THEN 'Viernes'
      WHEN 7 THEN 'Sábado'
    END,
    ' ', DAY(created_date), '/', MONTH(created_date)
  ) AS day_label

FROM hourly_data
ORDER BY created_date, hour_of_day;
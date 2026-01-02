# 📊 Documentación Técnica - Revenue Dashboard

> **Versión:** 1.0  
> **Última actualización:** Enero 2026  
> **Audiencia:** Analistas técnicos y equipo de Data Engineering  
> **Propósito:** Documentación de continuidad del proyecto

---

# ÍNDICE

1. [Overview](#1-overview)
2. [Arquitectura de Datos](#2-arquitectura-de-datos)
3. [Modelo de Pricing](#3-modelo-de-pricing)
4. [Tab 1: Current Month](#4-tab-1-current-month)
5. [Tab 2: Tot Insights](#5-tab-2-tot-insights)
6. [Diccionario de Datos](#6-diccionario-de-datos)
7. [FAQ y Troubleshooting](#7-faq-y-troubleshooting)

---

# 1. OVERVIEW

## 1.1 Objetivo del Sistema

El Revenue Dashboard es la plataforma central para monitorear y analizar los ingresos generados por NOVA, el agente de IA para recuperación de pagos fallidos. Proporciona visibilidad sobre:

- Revenue total y por período
- Comparaciones temporales (MoM, QoQ, YoY, WoW)
- Breakdown por organización, país y producto
- Tendencias y proyecciones

### Problema que Resuelve

| Necesidad de Negocio | Cómo lo Resuelve |
|----------------------|------------------|
| ¿Cuánto facturamos este mes? | KPI de Revenue MTD actualizado cada 5 min |
| ¿Estamos mejor o peor que el mes pasado? | Comparación MoM "to-date" (día a día) |
| ¿Qué clientes generan más revenue? | Breakdown por organización |
| ¿Calls o WhatsApp es más rentable? | Comparativo de productos |
| ¿Cuál es la tendencia histórica? | Gráficos mensuales/trimestrales con % cambio |

### Principios de Diseño

1. **Comparaciones "To-Date":** Las comparaciones MoM y QoQ se hacen hasta el mismo día del período, no contra meses/trimestres completos. Esto permite comparaciones justas cuando el período actual no ha terminado.

2. **Modelo Atómico:** El `ai_revenue_mart` mantiene una fila por comunicación individual, permitiendo flexibilidad máxima en agregaciones.

3. **Pricing Dinámico:** Los precios se obtienen de una tabla seed (`nova_costs`) que permite actualizar tarifas sin modificar el modelo.

4. **Refresh Frecuente:** La materialized view se actualiza cada 5 minutos para datos near-real-time.

---

## 1.2 Arquitectura General

### Flujo de Datos

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           FUENTES DE DATOS                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             │
│  │ ai_calls_detail │  │ai_whatsapp_detail│  │   nova_costs    │             │
│  │   (llamadas)    │  │   (mensajes)     │  │   (precios)     │             │
│  └────────┬────────┘  └────────┬────────┘  └────────┬────────┘             │
│           │                    │                    │                       │
│           └────────────────────┼────────────────────┘                       │
│                                │                                            │
│                                ▼                                            │
│                    ┌─────────────────────┐                                  │
│                    │   ai_revenue_mart   │                                  │
│                    │  (Materialized View)│                                  │
│                    │  Refresh: 5 min     │                                  │
│                    └──────────┬──────────┘                                  │
│                               │                                             │
└───────────────────────────────┼─────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                          CAPA DE QUERIES                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────────────┐      ┌─────────────────────────┐              │
│  │     CURRENT MONTH       │      │      TOT INSIGHTS       │              │
│  │       (Tab 1)           │      │        (Tab 2)          │              │
│  ├─────────────────────────┤      ├─────────────────────────┤              │
│  │ • KPIs (1-3)            │      │ • Total Revenue (1)     │              │
│  │ • Comparisons (4-6)     │      │ • Daily Chart (2)       │              │
│  │ • Trends (7-8)          │      │ • Monthly (3)           │              │
│  │ • Breakdowns (9-12)     │      │ • Quarterly (4)         │              │
│  │                         │      │ • Weekly (5)            │              │
│  └─────────────────────────┘      └─────────────────────────┘              │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                │
                                ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         METABASE DASHBOARD                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  • Visualizaciones interactivas                                             │
│  • Filtros globales (organización, país, producto, fecha)                   │
│  • Auto-refresh configurable                                                │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

# 2. ARQUITECTURA DE DATOS

## 2.1 Tabla Principal: ai_revenue_mart

### Configuración dbt

```sql
{{ config(
    materialized='materialized_view',
    distributed_by=['organization_code', 'product'],
    refresh_method='ASYNC EVERY (INTERVAL 5 MINUTE)'
) }}
```

### Estructura de la Tabla

| Columna | Tipo | Descripción |
|---------|------|-------------|
| `communication_unique_id` | VARCHAR | ID único (call_id o whatsapp_id) |
| `communication_id` | VARCHAR | ID de comunicación |
| `revenue_timestamp` | DATETIME | Timestamp exacto |
| `revenue_date` | DATE | Fecha de la comunicación |
| `revenue_hour` | INTEGER | Hora (0-23) |
| `revenue_month` | DATE | Primer día del mes |
| `revenue_week` | DATE | Primer día de la semana |
| `revenue_quarter` | DATE | Primer día del trimestre |
| `organization_code` | VARCHAR | Código de organización |
| `organization_name` | VARCHAR | Nombre del merchant |
| `country` | VARCHAR(2) | Código ISO del país |
| `product` | VARCHAR | PHONE_CALL o WHATSAPP_MESSAGE |
| `call_classification` | VARCHAR | Clasificación de la comunicación |
| `items` | INTEGER | Siempre 1 (una comunicación) |
| `units` | DECIMAL | Minutos (calls) o mensajes (WhatsApp) |
| `is_billable` | BOOLEAN | Si genera revenue |
| `revenue` | DECIMAL | Revenue en USD |
| `unit_price` | DECIMAL | Precio unitario |
| `pricing_unit` | VARCHAR | 'minute' o 'conversation+message' |
| `currency` | VARCHAR | Siempre 'USD' |

### Dimensiones de Tiempo Precalculadas

El modelo incluye dimensiones de tiempo precalculadas para facilitar agregaciones:

```sql
DATE_TRUNC('month', revenue_date) AS revenue_month,
DATE_TRUNC('week', revenue_date) AS revenue_week,
DATE_TRUNC('quarter', revenue_date) AS revenue_quarter,
EXTRACT(YEAR FROM revenue_date) AS revenue_year,
EXTRACT(MONTH FROM revenue_date) AS month_number,
EXTRACT(DAY FROM revenue_date) AS day_of_month,
DAYOFWEEK(revenue_date) AS day_of_week
```

---

## 2.2 Tablas Upstream

### ai_calls_detail

Contiene el detalle de cada llamada realizada por NOVA.

| Campo Relevante | Uso en Revenue |
|-----------------|----------------|
| `call_id` | ID único de la comunicación |
| `communication_id` | Referencia a comunicación |
| `created_at` | Timestamp del revenue |
| `call_duration_minutes` | Units para cálculo de revenue |
| `call_classification` | Determina is_billable |
| `organization_code/name` | Dimensiones |
| `country` | Dimensión + lookup de precio |

### ai_whatsapp_detail

Contiene el detalle de cada comunicación WhatsApp.

| Campo Relevante | Uso en Revenue |
|-----------------|----------------|
| `whatsapp_id` | ID único de la comunicación |
| `communication_id` | Referencia a comunicación |
| `created_at` | Timestamp del revenue |
| `billing_messages` | Units para cálculo de revenue |
| `message_classification` | call_classification en el mart |
| `organization_code/name` | Dimensiones |
| `country` | Dimensión + lookup de precio |

### nova_costs (Seed Table)

Tabla de precios por organización, país y tipo de cobro.

```csv
organization_code,organization_name,country,type_revenue,cost
e4c03f29-...,Rappi,AR,minute,0.5
e4c03f29-...,Rappi,AR,initiated_conversation,0.1
e4c03f29-...,Rappi,AR,message,0.01
...
```

| type_revenue | Producto | Descripción |
|--------------|----------|-------------|
| `minute` | PHONE_CALL | Precio por minuto de llamada |
| `initiated_conversation` | WHATSAPP_MESSAGE | Precio por conversación iniciada |
| `message` | WHATSAPP_MESSAGE | Precio por mensaje dentro de la conversación |

---

# 3. MODELO DE PRICING

## 3.1 Pricing de Llamadas (PHONE_CALL)

### Fórmula

```
Revenue = call_duration_minutes × price_per_minute

Donde:
- call_duration_minutes: Duración en minutos (desde ai_calls_detail)
- price_per_minute: Obtenido de nova_costs WHERE type_revenue = 'minute'
```

### Condiciones de Billability

```sql
is_billable = CASE 
  WHEN call_classification IN ('good_calls', 'short_calls', 'completed') 
  THEN TRUE 
  ELSE FALSE 
END
```

| Clasificación | is_billable | Razón |
|---------------|-------------|-------|
| good_calls | TRUE | Llamada exitosa con engagement |
| short_calls | TRUE | Llamada completada pero corta |
| completed | TRUE | Llamada completada genérica |
| failed | FALSE | Llamada no conectada |
| voicemail | FALSE | Fue a buzón de voz |
| no_answer | FALSE | No contestaron |

### Ejemplo de Cálculo

```
Llamada de Rappi PE:
- Duración: 3.5 minutos
- Precio: $0.20/min
- Revenue: 3.5 × 0.20 = $0.70
```

---

## 3.2 Pricing de WhatsApp (WHATSAPP_MESSAGE)

### Fórmula

```
Revenue = conversation_price + (billing_messages × message_price)

Donde:
- conversation_price: Precio fijo por iniciar conversación
- billing_messages: Número de mensajes facturables
- message_price: Precio por mensaje adicional
```

### Condiciones de Billability

```sql
-- Todas las comunicaciones WhatsApp son billables
is_billable = TRUE
```

### Ejemplo de Cálculo

```
Conversación WhatsApp de Rappi PE:
- Conversación iniciada: $0.07
- Mensajes enviados: 5
- Precio por mensaje: $0.01
- Revenue: 0.07 + (5 × 0.01) = $0.12
```

---

## 3.3 Precios por Organización/País

| Organización | País | Minute | Conv | Message |
|--------------|------|--------|------|---------|
| Rappi | AR | $0.50 | $0.10 | $0.01 |
| Rappi | BR | $0.20 | $0.05 | $0.01 |
| Rappi | PE | $0.20 | $0.07 | $0.01 |
| Intcomex | MX | $0.20 | - | - |
| Viva Aerobus | CO | $1.50 | - | - |
| Zigfun | BR | - | - | $0.03 |

> **Nota:** Los precios se actualizan en la tabla seed `nova_costs`. Los cambios se reflejan automáticamente en el próximo refresh del mart.

---

# 4. TAB 1: CURRENT MONTH

## 4.1 Propósito

Proporciona una vista ejecutiva del rendimiento del mes en curso, incluyendo:
- KPIs principales (Revenue, Comunicaciones, Tasa Facturable)
- Comparaciones temporales (YoY, MoM, QoQ)
- Tendencias de progreso
- Breakdowns detallados

---

## 4.2 KPIs Principales (Queries 1-3)

### 1_month_to_date_revenue.sql

**Descripción:** Revenue total acumulado del mes actual.

```sql
SELECT SUM(revenue) AS revenue_mtd
FROM ai_revenue_mart
WHERE revenue_month = DATE_TRUNC('month', CURRENT_DATE())
```

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `revenue_mtd` | DECIMAL | Revenue acumulado del mes en USD |

**Visualización recomendada:** Big Number con formato currency

---

### 2_month_to_date_communication.sql

**Descripción:** Total de comunicaciones del mes actual.

```sql
SELECT COUNT(*) AS comunicaciones_mtd
FROM ai_revenue_mart
WHERE revenue_month = DATE_TRUNC('month', CURRENT_DATE())
```

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `comunicaciones_mtd` | INTEGER | Total de comunicaciones (calls + WhatsApp) |

**Visualización recomendada:** Big Number

---

### 3_communication_billable_rate.sql

**Descripción:** Porcentaje de comunicaciones que generaron revenue.

```sql
SELECT ROUND(
  SUM(CASE WHEN is_billable THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 
  1
) AS tasa_facturable_pct
FROM ai_revenue_mart
WHERE revenue_month = DATE_TRUNC('month', CURRENT_DATE())
```

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `tasa_facturable_pct` | DECIMAL | % de comunicaciones billables |

**Visualización recomendada:** Gauge o Big Number con suffix "%"

---

## 4.3 Comparaciones Temporales (Queries 4-6)

### Principio "To-Date"

Las comparaciones se hacen hasta el mismo día del período para ser justas:

```
Ejemplo: Si hoy es 15 de Enero
- MoM compara: Ene 1-15 vs Dic 1-15 (NO vs Dic completo)
- QoQ compara: Q1 días 1-15 vs Q4 días 1-15
```

### 4_year_over_year_rate.sql

**Descripción:** Variación porcentual vs mismo mes del año anterior.

```sql
WITH actual AS (
  SELECT SUM(revenue) AS revenue
  FROM ai_revenue_mart
  WHERE revenue_month = DATE_TRUNC('month', CURRENT_DATE())
),
anterior AS (
  SELECT SUM(revenue) AS revenue
  FROM ai_revenue_mart
  WHERE revenue_month = DATE_TRUNC('month', DATE_SUB(CURRENT_DATE(), INTERVAL 12 MONTH))
)
SELECT ROUND((a.revenue - b.revenue) * 100.0 / NULLIF(b.revenue, 0), 1) AS yoy_pct
FROM actual a, anterior b
```

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `yoy_pct` | DECIMAL | % de cambio año sobre año |

**Interpretación:**
- Positivo (+): Crecimiento vs año anterior
- Negativo (-): Decrecimiento vs año anterior
- NULL: Sin datos del año anterior

---

### 5_month_over_month_rate.sql

**Descripción:** Variación porcentual vs mes anterior (to-date).

```sql
WITH actual AS (
  SELECT SUM(revenue) AS revenue
  FROM ai_revenue_mart
  WHERE revenue_month = DATE_TRUNC('month', CURRENT_DATE())
    AND day_of_month <= EXTRACT(DAY FROM CURRENT_DATE())  -- To-date
),
anterior AS (
  SELECT SUM(revenue) AS revenue
  FROM ai_revenue_mart
  WHERE revenue_month = DATE_TRUNC('month', DATE_SUB(CURRENT_DATE(), INTERVAL 1 MONTH))
    AND day_of_month <= EXTRACT(DAY FROM CURRENT_DATE())  -- Same day cut-off
)
SELECT ROUND((a.revenue - b.revenue) * 100.0 / NULLIF(b.revenue, 0), 1) AS mom_pct
```

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `mom_pct` | DECIMAL | % de cambio mes sobre mes (to-date) |

---

### 6_quarter_over_quarter.sql

**Descripción:** Variación porcentual vs trimestre anterior (to-date).

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `qoq_pct` | DECIMAL | % de cambio trimestre sobre trimestre (to-date) |

---

## 4.4 Tendencias (Queries 7-8)

### 7_mom_trend_chart.sql

**Descripción:** Comparación día a día del mes actual vs mes anterior.

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `day_of_month` | INTEGER | Día del mes (1-31) |
| `revenue_mes_actual` | DECIMAL | Revenue acumulado del día - mes actual |
| `revenue_mes_anterior` | DECIMAL | Revenue acumulado del día - mes anterior |

**Visualización recomendada:** Line chart con dos series

---

### 8_qoq_trend_chart.sql

**Descripción:** Comparación día a día del trimestre actual vs anterior.

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `day_of_quarter` | INTEGER | Día del trimestre (1-~92) |
| `revenue_q_actual` | DECIMAL | Revenue del día - trimestre actual |
| `revenue_q_anterior` | DECIMAL | Revenue del día - trimestre anterior |

**Visualización recomendada:** Line chart con dos series

---

## 4.5 Breakdowns (Queries 9-12)

### 9_revenue_all_organization.sql

**Descripción:** Revenue desglosado por organización y país.

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `organization_name` | VARCHAR | Nombre del merchant |
| `country` | VARCHAR(2) | País |
| `revenue` | DECIMAL | Revenue total |
| `comunicaciones` | INTEGER | Total de comunicaciones |
| `billables` | INTEGER | Comunicaciones facturables |
| `tasa_facturable_pct` | DECIMAL | % de tasa facturable |

**Visualización recomendada:** Table ordenada por revenue DESC

---

### 10_calls_quality_count.sql

**Descripción:** Breakdown de llamadas por clasificación.

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `call_classification` | VARCHAR | good_calls, short_calls, failed, etc. |
| `cantidad` | INTEGER | Número de llamadas |
| `revenue` | DECIMAL | Revenue generado |

**Visualización recomendada:** Bar chart horizontal

---

### 11_calls_vs_whatsapp.sql

**Descripción:** Comparativo de revenue por producto.

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `product` | VARCHAR | PHONE_CALL o WHATSAPP_MESSAGE |
| `revenue` | DECIMAL | Revenue total |
| `comunicaciones` | INTEGER | Total de comunicaciones |

**Visualización recomendada:** Pie chart o Bar chart

---

### 12_general_product_chart.sql

**Descripción:** Resumen completo por mes, organización y producto.

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `revenue_month` | DATE | Mes |
| `mes` | VARCHAR | Mes formateado (YYYY-MM) |
| `organization_name` | VARCHAR | Organización |
| `country` | VARCHAR(2) | País |
| `minutos_billables` | DECIMAL | Total minutos (calls) |
| `mensajes_billables` | INTEGER | Total mensajes (WhatsApp) |
| `total_llamadas` | INTEGER | Conteo de llamadas |
| `total_whatsapp` | INTEGER | Conteo de WhatsApp |
| `revenue_total` | DECIMAL | Revenue total |
| `revenue_llamadas` | DECIMAL | Revenue de calls |
| `revenue_whatsapp` | DECIMAL | Revenue de WhatsApp |

**Visualización recomendada:** Pivot table o Stacked bar chart

---

# 5. TAB 2: TOT INSIGHTS

## 5.1 Propósito

Análisis histórico completo con filtros de fecha flexibles. Permite explorar tendencias a largo plazo y comparar períodos arbitrarios.

---

## 5.2 Queries

### 1_total_revenue.sql

**Descripción:** Revenue total agregado (respeta filtros de fecha).

```sql
SELECT SUM(revenue) AS revenue
FROM ai_revenue_mart
WHERE TRUE
  [[AND {{revenue_date}}]]
  [[ AND {{organization_name}} ]]
  [[ AND {{country}} ]]
  [[ AND {{product}} ]]
```

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `revenue` | DECIMAL | Revenue total en el período seleccionado |

---

### 2_daily_revenue_chart.sql

**Descripción:** Revenue y comunicaciones por día.

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `revenue_date` | DATE | Fecha |
| `revenue` | DECIMAL | Revenue del día |
| `comunicaciones` | INTEGER | Comunicaciones del día |

**Visualización recomendada:** Line chart (revenue) + Bar chart (comunicaciones)

---

### 3_monthly_revenue.sql

**Descripción:** Revenue mensual con variación MoM.

```sql
WITH monthly AS (
  SELECT revenue_month, SUM(revenue) AS revenue
  FROM ai_revenue_mart
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
```

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `revenue_month` | DATE | Primer día del mes |
| `revenue` | DECIMAL | Revenue del mes |
| `revenue_anterior` | DECIMAL | Revenue del mes anterior |
| `mom_pct` | DECIMAL | % de cambio MoM |

**Visualización recomendada:** Bar chart con trend line

---

### 4_quarterly_revenue.sql

**Descripción:** Revenue trimestral con variación QoQ.

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `revenue_quarter` | DATE | Primer día del trimestre |
| `revenue` | DECIMAL | Revenue del trimestre |
| `revenue_anterior` | DECIMAL | Revenue del trimestre anterior |
| `qoq_pct` | DECIMAL | % de cambio QoQ |

---

### 5_weekly_revenue.sql

**Descripción:** Revenue semanal con variación WoW.

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `revenue_week` | DATE | Primer día de la semana |
| `revenue` | DECIMAL | Revenue de la semana |
| `revenue_anterior` | DECIMAL | Revenue de la semana anterior |
| `wow_pct` | DECIMAL | % de cambio WoW |

---

# 6. DICCIONARIO DE DATOS

## 6.1 Dimensiones

| Atributo | Tipo | Valores Posibles | Descripción |
|----------|------|------------------|-------------|
| `organization_code` | VARCHAR(36) | UUID | Identificador único de organización |
| `organization_name` | VARCHAR | Rappi, Intcomex, Viva Aerobus, etc. | Nombre comercial |
| `country` | VARCHAR(2) | AR, BR, PE, MX, CO | Código ISO del país |
| `product` | VARCHAR | PHONE_CALL, WHATSAPP_MESSAGE | Tipo de comunicación |
| `call_classification` | VARCHAR | good_calls, short_calls, completed, failed, voicemail, no_answer | Clasificación de la comunicación |

## 6.2 Métricas

| Atributo | Tipo | Rango | Descripción |
|----------|------|-------|-------------|
| `revenue` | DECIMAL | 0 - ∞ | Ingreso en USD |
| `items` | INTEGER | 1 | Siempre 1 (una comunicación) |
| `units` | DECIMAL | 0 - ∞ | Minutos (calls) o mensajes (WhatsApp) |
| `is_billable` | BOOLEAN | TRUE/FALSE | Si genera revenue |

## 6.3 Comparaciones Temporales

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `mom_pct` | DECIMAL | Month over Month % |
| `qoq_pct` | DECIMAL | Quarter over Quarter % |
| `yoy_pct` | DECIMAL | Year over Year % |
| `wow_pct` | DECIMAL | Week over Week % |

---

# 7. FAQ Y TROUBLESHOOTING

## 7.1 Preguntas Frecuentes

### ¿Por qué el MoM % no coincide con mi cálculo manual?

El MoM % usa comparación **to-date**, no meses completos:
- Query: Compara Ene 1-15 vs Dic 1-15
- Manual típico: Compara Ene completo vs Dic completo

Esto es intencional para dar comparaciones justas durante el mes en curso.

### ¿Por qué algunas comunicaciones tienen revenue = 0?

Las comunicaciones con `is_billable = FALSE` tienen revenue = 0:
- Llamadas fallidas, voicemail, no contestadas
- Estas se cuentan en `comunicaciones` pero no generan revenue

### ¿Con qué frecuencia se actualizan los datos?

El `ai_revenue_mart` se refresca cada 5 minutos (ASYNC refresh).

### ¿Cómo agrego una nueva organización con precios?

1. Agregar filas en `nova_costs.csv` con los precios
2. Ejecutar `dbt seed` para actualizar la tabla
3. El mart tomará los nuevos precios en el siguiente refresh

### ¿Por qué no veo datos de WhatsApp para algunas organizaciones?

No todas las organizaciones tienen habilitado WhatsApp. Revisa:
1. Si la organización tiene registros en `ai_whatsapp_detail`
2. Si tiene precios configurados en `nova_costs` para `initiated_conversation` y `message`

---

## 7.2 Troubleshooting

### Revenue = NULL o vacío

**Posibles causas:**
1. No hay datos en el período seleccionado
2. Filtros muy restrictivos aplicados
3. La organización no tiene precios configurados

**Solución:**
```sql
-- Verificar si hay datos
SELECT COUNT(*), SUM(revenue) 
FROM ai_revenue_mart 
WHERE organization_name = 'X' AND revenue_date >= '2025-01-01';

-- Verificar precios
SELECT * FROM nova_costs WHERE organization_name = 'X';
```

### Datos no se actualizan

**Posibles causas:**
1. El async refresh está detenido
2. Problemas en las tablas upstream

**Solución:**
```sql
-- Verificar última actualización
SELECT MAX(revenue_timestamp) FROM ai_revenue_mart;

-- Forzar refresh manual si es necesario
REFRESH MATERIALIZED VIEW ai_revenue_mart;
```

### Discrepancia entre productos

**Si Calls muestra datos pero WhatsApp no (o viceversa):**
1. Verificar que ambas tablas upstream tienen datos
2. Verificar que ambos productos tienen precios en `nova_costs`

---

## 7.3 Changelog

| Versión | Fecha | Cambios |
|---------|-------|---------|
| 1.0 | Enero 2026 | Documentación técnica inicial. 17 queries en 2 tabs. |

---

## 7.4 Estructura de Archivos

```
dashboards/revenue/
│
├── README.md                              # Índice y guía rápida
├── REVENUE_TECHNICAL_DOCUMENTATION.md     # Esta documentación
│
└── queries/
    │
    ├── tot_insights/                      # Tab 2: Histórico
    │   ├── 1_total_revenue.sql
    │   ├── 2_daily_revenue_chart.sql
    │   ├── 3_monthly_revenue.sql
    │   ├── 4_quarterly_revenue.sql
    │   └── 5_weekly_revenue.sql
    │
    └── current_month/                     # Tab 1: Mes actual
        ├── 1_month_to_date_revenue.sql
        ├── 2_month_to_date_communication.sql
        ├── 3_communication_billable_rate.sql
        ├── 4_year_over_year_rate.sql
        ├── 5_month_over_month_rate.sql
        ├── 6_quarter_over_quarter.sql
        ├── 7_mom_trend_chart.sql
        ├── 8_qoq_trend_chart.sql
        ├── 9_revenue_all_organization.sql
        ├── 10_calls_quality_count.sql
        ├── 11_calls_vs_whatsapp.sql
        └── 12_general_product_chart.sql
```

---

*Fin de la documentación*

# 📊 Documentación Técnica - Revenue Dashboard

> **Versión:** 1.1  
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

4. **Billability Configurable:** Cada organización puede definir qué clasificaciones de llamadas son facturables mediante flags booleanos en `nova_costs`.

5. **Refresh Frecuente:** La materialized view se actualiza cada 5 minutos para datos near-real-time.

---

## 1.2 Arquitectura General

### Flujo de Datos

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           FUENTES DE DATOS                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             │
│  │ ai_calls_detail │  │ai_messages_detail│  │   nova_costs    │             │
│  │   (llamadas)    │  │   (WhatsApp)     │  │ (pricing+rules) │             │
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
| `organization_code` | VARCHAR(36) | Código de organización |
| `organization_name` | VARCHAR | Nombre del merchant |
| `country` | VARCHAR(2) | Código ISO del país |
| `product` | VARCHAR | PHONE_CALL o WHATSAPP_MESSAGE |
| `call_classification` | VARCHAR | Clasificación de la comunicación |
| `items` | INTEGER | Siempre 1 (una comunicación) |
| `units` | DECIMAL | Minutos (calls) o mensajes (WhatsApp) |
| `is_billable` | BOOLEAN | Si genera revenue (configurable) |
| `revenue` | DECIMAL | Revenue en USD |
| `unit_price` | DECIMAL | Precio unitario |
| `pricing_unit` | VARCHAR | 'minute' o 'conversation+message' |
| `currency` | VARCHAR | Siempre 'USD' |
| `call_status` | VARCHAR | Estado del provider |
| `duration` | INTEGER | Duración en segundos (solo calls) |

### Dimensiones de Tiempo Precalculadas

```sql
DATE_TRUNC('month', revenue_date) AS revenue_month,
DATE_TRUNC('week', revenue_date) AS revenue_week,
DATE_TRUNC('quarter', revenue_date) AS revenue_quarter,
EXTRACT(YEAR FROM revenue_date) AS revenue_year,
EXTRACT(MONTH FROM revenue_date) AS month_number,
EXTRACT(DAY FROM revenue_date) AS day_of_month,
DATE_FORMAT(revenue_date, '%W') AS day_name,
DAYOFWEEK(revenue_date) AS day_of_week
```

---

## 2.2 Tablas Upstream

### ai_calls_detail

Vista materializada con el detalle de cada llamada realizada por NOVA.

**Configuración:**
```sql
{{ config(
    materialized='materialized_view',
    distributed_by=['organization_code'],
    refresh_method='ASYNC EVERY (INTERVAL 5 MINUTE)'
) }}
```

**Campos Relevantes para Revenue:**

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `conversation_id` | VARCHAR | ID único de la llamada |
| `communication_id` | VARCHAR | Referencia a comunicación |
| `channel` | VARCHAR | Siempre 'PHONE_CALL' |
| `created_at` | DATETIME | Timestamp de la llamada |
| `call_duration_minutes` | DECIMAL | Duración en minutos (redondeado hacia arriba) |
| `call_classification` | VARCHAR | good_calls, short_calls, completed, failed, etc. |
| `organization_code` | VARCHAR(36) | Código del merchant |
| `organization_name` | VARCHAR | Nombre del merchant |
| `country` | VARCHAR(2) | País (ISO2) |
| `provider_call_status` | VARCHAR | Estado original del provider |
| `transcription_length` | INTEGER | Longitud de la transcripción |

**Lógica de Clasificación de Llamadas:**

```sql
CASE
  -- good_calls: completada + transcripción ≥1000 chars + sin keywords de voicemail
  WHEN provider_call_status = 'completed'
       AND transcription IS NOT NULL
       AND transcription_length >= 1000
       AND has_voicemail_keywords = FALSE
  THEN 'good_calls'
  
  -- short_calls: completada + transcripción <1000 chars
  WHEN provider_call_status = 'completed'
       AND transcription IS NOT NULL
       AND transcription_length < 1000
  THEN 'short_calls'
  
  -- completed: completada sin transcripción válida
  WHEN provider_call_status = 'completed'
  THEN 'completed'
  
  -- Los demás status se mapean directamente
  WHEN provider_call_status = 'voice_mail' THEN 'voicemail'
  WHEN provider_call_status = 'failed' THEN 'failed'
  WHEN provider_call_status = 'no-answer' THEN 'no-answer'
  WHEN provider_call_status = 'busy' THEN 'busy'
  ELSE COALESCE(provider_call_status, 'unknown')
END AS call_classification
```

---

### ai_messages_detail

Vista materializada con el detalle de cada comunicación WhatsApp.

**Configuración:**
```sql
{{ config(
    materialized='materialized_view',
    distributed_by=['organization_code'],
    refresh_method='ASYNC EVERY (INTERVAL 5 MINUTE)'
) }}
```

**Campos Relevantes para Revenue:**

| Campo | Tipo | Descripción |
|-------|------|-------------|
| `communication_id` | VARCHAR | ID único de la comunicación |
| `channel` | VARCHAR | Siempre 'WHATSAPP_MESSAGE' |
| `created_at` | DATETIME | Timestamp del mensaje |
| `billing_messages` | INTEGER | Número de mensajes facturables (mín. 1) |
| `direction` | VARCHAR | INBOUND o OUTBOUND |
| `organization_code` | VARCHAR(36) | Código del merchant |
| `organization_name` | VARCHAR | Nombre del merchant |
| `country` | VARCHAR(2) | País (ISO2) |
| `messages_raw` | VARCHAR | Valor original del campo messages |

**Lógica de billing_messages:**

```sql
-- Si messages es NULL, vacío, no numérico o ≤0, usar 1 como default
CASE 
  WHEN messages IS NOT NULL 
       AND TRIM(CAST(messages AS VARCHAR)) != '' 
       AND TRIM(CAST(messages AS VARCHAR)) REGEXP '^[0-9]+$'
       AND CAST(TRIM(CAST(messages AS VARCHAR)) AS INT) > 0
  THEN CAST(TRIM(CAST(messages AS VARCHAR)) AS INT)
  ELSE 1
END AS billing_messages
```

---

### nova_costs (Seed Table)

Tabla de configuración de precios y reglas de billability por organización.

**Schema (nova_costs.yml):**

```yaml
seeds:
  - name: nova_costs
    description: >
      Tabla de precios de NOVA por organización, país y producto.
      Incluye configuración de qué clasificaciones de llamadas son billables.
      Clave compuesta: organization_code + country + product
    columns:
      - name: organization_code
        description: UUID del merchant
      - name: organization_name
        description: Nombre del merchant
      - name: country
        description: Código ISO2 del país (AR, BR, MX, CO, PE, CL)
      - name: product
        description: PHONE_CALL o WHATSAPP_MESSAGE
      - name: unit_cost
        description: Precio por unidad (minuto o mensaje) en USD
      - name: conversation_cost
        description: Precio fijo por conversación iniciada (solo WhatsApp)
      - name: currency
        description: Código de moneda (USD)
      - name: pricing_unit
        description: 'minute' o 'conversation+message'
      - name: bill_good_calls
        description: Si se cobra por llamadas 'good_calls'
      - name: bill_short_calls
        description: Si se cobra por llamadas 'short_calls'
      - name: bill_completed
        description: Si se cobra por llamadas 'completed'
```

**Estructura CSV:**

```csv
organization_code,organization_name,country,product,unit_cost,conversation_cost,currency,pricing_unit,bill_good_calls,bill_short_calls,bill_completed
```

---

# 3. MODELO DE PRICING

## 3.1 Pricing de Llamadas (PHONE_CALL)

### Fórmula

```
Revenue = call_duration_minutes × unit_cost

Donde:
- call_duration_minutes: CEIL(call_duration_seconds / 60)
- unit_cost: Obtenido de nova_costs WHERE product = 'PHONE_CALL'
```

### Condiciones de Billability (Configurable por Organización)

```sql
is_billable = CASE 
  WHEN call_classification = 'good_calls' AND p.bill_good_calls = TRUE THEN TRUE
  WHEN call_classification = 'short_calls' AND p.bill_short_calls = TRUE THEN TRUE
  WHEN call_classification = 'completed' AND p.bill_completed = TRUE THEN TRUE
  ELSE FALSE 
END
```

### Cálculo de Revenue

```sql
revenue = CASE 
  WHEN call_classification = 'good_calls' AND p.bill_good_calls = TRUE 
    THEN call_duration_minutes * COALESCE(p.unit_cost, 0)
  WHEN call_classification = 'short_calls' AND p.bill_short_calls = TRUE 
    THEN call_duration_minutes * COALESCE(p.unit_cost, 0)
  WHEN call_classification = 'completed' AND p.bill_completed = TRUE 
    THEN call_duration_minutes * COALESCE(p.unit_cost, 0)
  ELSE 0 
END
```

### Configuración por Organización

| Organización | bill_good_calls | bill_short_calls | bill_completed | Resultado |
|--------------|-----------------|------------------|----------------|-----------|
| **Rappi** | ✅ TRUE | ❌ FALSE | ❌ FALSE | Solo cobra good_calls |
| **Intcomex** | ✅ TRUE | ✅ TRUE | ✅ TRUE | Cobra todas las completadas |
| **Viva Aerobus** | ✅ TRUE | ✅ TRUE | ❌ FALSE | Cobra good + short |

### Ejemplo de Cálculo - Rappi PE

```
Llamada good_calls de Rappi PE:
- Duración: 185 segundos → CEIL(185/60) = 4 minutos
- unit_cost: $0.20/min
- bill_good_calls: TRUE
- Revenue: 4 × 0.20 = $0.80

Llamada short_calls de Rappi PE:
- Duración: 45 segundos → CEIL(45/60) = 1 minuto
- unit_cost: $0.20/min
- bill_short_calls: FALSE
- Revenue: $0.00 (no billable)
```

### Ejemplo de Cálculo - Intcomex MX

```
Llamada short_calls de Intcomex MX:
- Duración: 45 segundos → CEIL(45/60) = 1 minuto
- unit_cost: $0.20/min
- bill_short_calls: TRUE
- Revenue: 1 × 0.20 = $0.20 (SÍ billable)
```

---

## 3.2 Pricing de WhatsApp (WHATSAPP_MESSAGE)

### Fórmula

```
Revenue = conversation_cost + (billing_messages × unit_cost)

Donde:
- conversation_cost: Precio fijo por iniciar conversación
- billing_messages: Número de mensajes (mín. 1)
- unit_cost: Precio por mensaje adicional
```

### Condiciones de Billability

```sql
-- Todas las comunicaciones WhatsApp son billables
is_billable = TRUE
```

### Cálculo de Revenue

```sql
revenue = COALESCE(p.conversation_cost, 0) + 
          (w.billing_messages * COALESCE(p.unit_cost, 0))
```

### Ejemplo de Cálculo - Rappi PE

```
Conversación WhatsApp de Rappi PE:
- conversation_cost: $0.07
- billing_messages: 5
- unit_cost: $0.01/msg
- Revenue: 0.07 + (5 × 0.01) = $0.12
```

### Ejemplo de Cálculo - Peru Rail

```
Conversación WhatsApp de Peru Rail:
- conversation_cost: $0.50
- billing_messages: 3
- unit_cost: $0.00/msg
- Revenue: 0.50 + (3 × 0.00) = $0.50 (solo cobra conversación)
```

### Ejemplo de Cálculo - ZigFun BR

```
Conversación WhatsApp de ZigFun BR:
- conversation_cost: $0.00
- billing_messages: 8
- unit_cost: $0.03/msg
- Revenue: 0.00 + (8 × 0.03) = $0.24 (solo cobra mensajes)
```

---

## 3.3 Tabla de Precios Completa

### PHONE_CALL

| Organización | País | unit_cost | bill_good | bill_short | bill_completed |
|--------------|------|-----------|-----------|------------|----------------|
| Rappi | AR | $0.50 | ✅ | ❌ | ❌ |
| Rappi | BR | $0.20 | ✅ | ❌ | ❌ |
| Rappi | PE | $0.20 | ✅ | ❌ | ❌ |
| Rappi | CL | $0.20 | ✅ | ❌ | ❌ |
| Rappi | CO | $0.20 | ✅ | ❌ | ❌ |
| Rappi | MX | $0.20 | ✅ | ❌ | ❌ |
| Intcomex | MX | $0.20 | ✅ | ✅ | ✅ |
| Viva Aerobus | CO | $1.50 | ✅ | ✅ | ❌ |

### WHATSAPP_MESSAGE

| Organización | País | conversation_cost | unit_cost | Modelo |
|--------------|------|-------------------|-----------|--------|
| Rappi | AR | $0.10 | $0.01 | Conversación + Mensaje |
| Rappi | BR | $0.05 | $0.01 | Conversación + Mensaje |
| Rappi | PE | $0.07 | $0.01 | Conversación + Mensaje |
| Rappi | CL | $0.07 | $0.01 | Conversación + Mensaje |
| Rappi | CO | $0.03 | $0.01 | Conversación + Mensaje |
| Rappi | MX | $0.07 | $0.01 | Conversación + Mensaje |
| ZigFun | BR | $0.00 | $0.03 | Solo Mensajes |
| Peru Rail | PE | $0.50 | $0.00 | Solo Conversación |

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
| `call_classification` | VARCHAR | good_calls, short_calls, completed, etc. |
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
| `organization_name` | VARCHAR | Organización |
| `country` | VARCHAR(2) | País |
| `minutos_billables` | DECIMAL | Total minutos (calls) |
| `mensajes_billables` | INTEGER | Total mensajes (WhatsApp) |
| `revenue_total` | DECIMAL | Revenue total |

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

---

### 2_daily_revenue_chart.sql

**Descripción:** Revenue y comunicaciones por día.

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `revenue_date` | DATE | Fecha |
| `revenue` | DECIMAL | Revenue del día |
| `comunicaciones` | INTEGER | Comunicaciones del día |

---

### 3_monthly_revenue.sql

**Descripción:** Revenue mensual con variación MoM.

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `revenue_month` | DATE | Primer día del mes |
| `revenue` | DECIMAL | Revenue del mes |
| `revenue_anterior` | DECIMAL | Revenue del mes anterior |
| `mom_pct` | DECIMAL | % de cambio MoM |

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
| `organization_name` | VARCHAR | Rappi, Intcomex, Viva Aerobus, ZigFun, Peru Rail | Nombre comercial |
| `country` | VARCHAR(2) | AR, BR, PE, MX, CO, CL | Código ISO del país |
| `product` | VARCHAR | PHONE_CALL, WHATSAPP_MESSAGE | Tipo de comunicación |
| `call_classification` | VARCHAR | Ver tabla abajo | Clasificación de la comunicación |

### Clasificaciones de Comunicación

| Clasificación | Producto | Descripción | Billable |
|---------------|----------|-------------|----------|
| `good_calls` | PHONE_CALL | Completada, transcripción ≥1000 chars, sin voicemail | Configurable |
| `short_calls` | PHONE_CALL | Completada, transcripción <1000 chars | Configurable |
| `completed` | PHONE_CALL | Completada sin transcripción válida | Configurable |
| `voicemail` | PHONE_CALL | Fue a buzón de voz | ❌ No |
| `failed` | PHONE_CALL | Llamada fallida | ❌ No |
| `no-answer` | PHONE_CALL | No contestaron | ❌ No |
| `busy` | PHONE_CALL | Línea ocupada | ❌ No |
| `INBOUND` | WHATSAPP_MESSAGE | Mensaje entrante | ✅ Sí |
| `OUTBOUND` | WHATSAPP_MESSAGE | Mensaje saliente | ✅ Sí |

## 6.2 Métricas

| Atributo | Tipo | Rango | Descripción |
|----------|------|-------|-------------|
| `revenue` | DECIMAL | 0 - ∞ | Ingreso en USD |
| `items` | INTEGER | 1 | Siempre 1 (una comunicación) |
| `units` | DECIMAL | 0 - ∞ | Minutos (calls) o mensajes (WhatsApp) |
| `is_billable` | BOOLEAN | TRUE/FALSE | Si genera revenue |

## 6.3 Configuración de Billability (nova_costs)

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `unit_cost` | DECIMAL | Precio por minuto (calls) o mensaje (WhatsApp) |
| `conversation_cost` | DECIMAL | Precio por conversación iniciada (solo WhatsApp) |
| `bill_good_calls` | BOOLEAN | Si cobra por good_calls |
| `bill_short_calls` | BOOLEAN | Si cobra por short_calls |
| `bill_completed` | BOOLEAN | Si cobra por completed |

---

# 7. FAQ Y TROUBLESHOOTING

## 7.1 Preguntas Frecuentes

### ¿Por qué el MoM % no coincide con mi cálculo manual?

El MoM % usa comparación **to-date**, no meses completos:
- Query: Compara Ene 1-15 vs Dic 1-15
- Manual típico: Compara Ene completo vs Dic completo

### ¿Por qué algunas comunicaciones tienen revenue = 0?

Dos posibles razones:
1. **Comunicaciones no billables:** Llamadas con `is_billable = FALSE` (ej: short_calls para Rappi)
2. **Sin precio configurado:** La organización/país/producto no tiene entrada en `nova_costs`

### ¿Por qué Rappi no cobra short_calls pero Intcomex sí?

Cada organización tiene configuración independiente de billability en `nova_costs`:
- Rappi: `bill_short_calls = FALSE`
- Intcomex: `bill_short_calls = TRUE`

### ¿Con qué frecuencia se actualizan los datos?

El `ai_revenue_mart` se refresca cada 5 minutos (ASYNC refresh).

### ¿Cómo agrego una nueva organización con precios?

1. Agregar filas en `nova_costs.csv` con los precios y flags de billability
2. Ejecutar `dbt seed` para actualizar la tabla
3. El mart tomará los nuevos precios en el siguiente refresh

### ¿Cómo cambio qué clasificaciones son billables para una organización?

1. Modificar los flags `bill_good_calls`, `bill_short_calls`, `bill_completed` en `nova_costs.csv`
2. Ejecutar `dbt seed`
3. Los cambios aplican solo a comunicaciones futuras

---

## 7.2 Troubleshooting

### Revenue = NULL o vacío

**Posibles causas:**
1. No hay datos en el período seleccionado
2. Filtros muy restrictivos aplicados
3. La organización no tiene precios configurados en `nova_costs`
4. Todos los flags de billability están en FALSE

**Solución:**
```sql
-- Verificar si hay datos
SELECT COUNT(*), SUM(revenue), SUM(CASE WHEN is_billable THEN 1 ELSE 0 END) as billables
FROM ai_revenue_mart 
WHERE organization_name = 'X' AND revenue_date >= '2025-01-01';

-- Verificar configuración de precios
SELECT * FROM nova_costs WHERE organization_name = 'X';
```

### Tasa facturable muy baja

**Posibles causas:**
1. Muchas llamadas clasificadas como short_calls o completed (y no son billables para esa org)
2. Alta tasa de llamadas failed/voicemail/no-answer

**Solución:**
```sql
-- Ver distribución de clasificaciones
SELECT call_classification, COUNT(*), 
       SUM(CASE WHEN is_billable THEN 1 ELSE 0 END) as billables
FROM ai_revenue_mart 
WHERE organization_name = 'X' AND product = 'PHONE_CALL'
GROUP BY call_classification;
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

---

## 7.3 Changelog

| Versión | Fecha | Cambios |
|---------|-------|---------|
| 1.1 | Enero 2026 | Billability configurable por organización (bill_good_calls, bill_short_calls, bill_completed). Nuevo modelo ai_messages_detail. Soporte para Chile (CL). Nuevas organizaciones: ZigFun, Peru Rail. |
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

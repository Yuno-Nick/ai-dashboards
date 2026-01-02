# 📊 Documentación Técnica - Sistema de Alertas AI Calls

> **Versión:** 2.0  
> **Última actualización:** Diciembre 2025  
> **Audiencia:** Analistas técnicos y equipo de Data Engineering  
> **Propósito:** Documentación de continuidad del proyecto

---

# 1. OVERVIEW

## 1.1 Objetivo del Sistema

El Sistema de Alertas de AI Calls es una plataforma de monitoreo en tiempo real diseñada para detectar anomalías en el comportamiento de las llamadas realizadas por agentes de IA para recuperación de pagos fallidos.

### Problema que Resuelve

Las llamadas de IA operan 24/7 y pueden experimentar degradaciones silenciosas que, sin monitoreo adecuado, pasan desapercibidas hasta que el impacto en el negocio es significativo. Este sistema detecta:

| Tipo de Problema | Impacto en Negocio | Alerta que lo Detecta |
|------------------|--------------------|-----------------------|
| Caída en volumen de llamadas | Menor alcance de clientes morosos | Alert 1: Volume Drop |
| Problemas de conexión | Llamadas no completadas, recursos desperdiciados | Alert 2: Completion Rate Drop |
| Conversaciones inefectivas | Llamadas que no logran engagement | Alert 3: Quality Rate Drop |
| Usuarios colgando rápido | Problemas de audio, script o primera impresión | Alert 4: Short Call Rate Spike |
| Llamadas anormalmente largas/cortas | Bot atrapado en loops o terminando prematuramente | Alert 5: Call Duration Anomaly |

### Principios de Diseño

1. **Reducción de Falsos Positivos:** El sistema usa validación dual (múltiples baselines) y umbrales estadísticos en lugar de umbrales arbitrarios.

2. **Comparaciones "Apples-to-Apples":** Todas las comparaciones temporales se hacen hasta el mismo momento del día (hora:minuto), no contra días completos.

3. **Contexto Estadístico:** Las alertas 4 y 5 usan z-scores (desviaciones estándar) para adaptarse automáticamente a los patrones históricos de cada organización.

4. **Confirmación por Consenso:** Las alertas principales solo se disparan cuando los 3 sub-alerts (DoD, WoW, 30d avg) coinciden en WARNING o CRITICAL.

---

## 1.2 Arquitectura General

### Flujo de Datos

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                              FUENTE DE DATOS                                │
├─────────────────────────────────────────────────────────────────────────────┤
│  ai_calls_detail                                                            │
│  └── Tabla principal con registros individuales de cada llamada             │
│      └── Refresh: cada 5 minutos                                            │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                            CAPA DE QUERIES                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────────┐  ┌─────────────────┐  ┌─────────────────┐             │
│  │     CHARTS      │  │     ALERTS      │  │     METRICS     │             │
│  │   (Tab 1)       │  │    (Tab 2)      │  │    (Tab 3)      │             │
│  ├─────────────────┤  ├─────────────────┤  ├─────────────────┤             │
│  │ • total_calls   │  │ Main Alerts:    │  │ current_summary │             │
│  │ • completed_    │  │ • alert_1       │  │ • Estado actual │             │
│  │   calls         │  │ • alert_2       │  │   del día       │             │
│  │ • total_calls_  │  │ • alert_3       │  │                 │             │
│  │   all_orgs      │  │ • alert_4       │  │ hourly_summary  │             │
│  │                 │  │ • alert_5       │  │ • Histórico 7   │             │
│  │                 │  │                 │  │   días por hora │             │
│  │                 │  │ Sub-Alerts:     │  │                 │             │
│  │                 │  │ • *_dod (x5)    │  │                 │             │
│  │                 │  │ • *_wow (x5)    │  │                 │             │
│  │                 │  │ • *_30davg (x5) │  │                 │             │
│  └─────────────────┘  └─────────────────┘  └─────────────────┘             │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
                                      │
                                      ▼
┌─────────────────────────────────────────────────────────────────────────────┐
│                         METABASE DASHBOARD                                  │
├─────────────────────────────────────────────────────────────────────────────┤
│  ┌─────────────┐    ┌─────────────┐    ┌─────────────┐                     │
│  │   Tab 1     │    │   Tab 2     │    │   Tab 3     │                     │
│  │   Charts    │    │   Alertas   │    │  Métricas   │                     │
│  └─────────────┘    └─────────────┘    └─────────────┘                     │
│                            │                                                │
│                            ▼                                                │
│                     Slack Integration                                       │
│                     (CRITICAL/WARNING)                                      │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Jerarquía de Alertas

```
ALERTA PRINCIPAL (Main Alert)
│
├── Solo se dispara si los 3 sub-alerts coinciden en WARNING o CRITICAL
│
├── Sub-Alert X.1: vs DoD (Day over Day)
│   └── Compara HOY vs AYER (mismo momento)
│   └── Usa stddev de TODOS los días (últimos 30d)
│
├── Sub-Alert X.2: vs WoW (Week over Week)
│   └── Compara HOY vs HACE 7 DÍAS (mismo momento)
│   └── Usa stddev del MISMO DÍA DE SEMANA
│
└── Sub-Alert X.3: vs 30d Avg
    └── Compara HOY vs PROMEDIO 30 DÍAS (mismo día de semana, mismo momento)
    └── Usa stddev del MISMO DÍA DE SEMANA
```

### ¿Por qué 3 Sub-Alerts?

| Sub-Alert | Baseline | Qué Detecta | Debilidad si se usa solo |
|-----------|----------|-------------|--------------------------|
| **DoD** | Ayer | Cambios recientes, problemas de hoy | Sensible a volatilidad diaria |
| **WoW** | Semana pasada | Patrones semanales, estacionalidad | Ignora tendencias recientes |
| **30d Avg** | Promedio histórico | Desviaciones del comportamiento normal | Lento para detectar cambios |

**La combinación de los 3** asegura que una alerta solo se dispara cuando hay consenso: el problema es real, no es volatilidad puntual, y representa una desviación significativa del comportamiento histórico.

---

## 1.3 Estructura del Dashboard (3 Tabs)

El dashboard en Metabase está organizado en 3 tabs con propósitos distintos:

### Tab 1: Charts (Visualización)

**Propósito:** Proveer contexto visual del comportamiento de llamadas antes de investigar alertas.

| Chart | Query | Descripción |
|-------|-------|-------------|
| **Calls por Día/Hora** | `total_calls.sql` | Heatmap que muestra el volumen de llamadas por hora para cada día. Permite identificar patrones temporales y anomalías visuales. |
| **Completed Calls por Día/Hora** | `completed_calls.sql` | Similar al anterior pero solo para llamadas completadas (excluye failed, voicemail). |
| **Calls por Organización** | `total_calls_all_orgs.sql` | Vista agregada de todas las organizaciones para comparar volúmenes relativos. |

**Atributos clave de los charts:**

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `created_date` | DATE | Fecha de la llamada |
| `hour_of_day` | INTEGER | Hora del día (0-23) |
| `total_calls` | INTEGER | Conteo de llamadas |
| `block_status` | VARCHAR | Estado visual: `CURRENT_HOUR`, `TODAY_COMPLETED`, `TODAY_PENDING`, `PAST_DAY` |
| `block_label` | VARCHAR | Etiqueta para tooltip: "Lun 2025-12-22 - 14:00" |
| `day_label` | VARCHAR | Día formateado: "Lunes 22/12" |

**Filtros disponibles:**
- `{{time}}`: Rango de fechas
- `{{organization_name}}`: Filtrar por organización específica
- `{{countries}}`: Filtrar por país

---

### Tab 2: Alertas

**Propósito:** Mostrar alertas activas (CRITICAL y WARNING) que requieren atención.

#### Alertas Principales

| Query | Métrica | Trigger |
|-------|---------|---------|
| `alert_1_volume_drop.sql` | `total_calls` | Caída de volumen vs 3 baselines |
| `alert_2_completion_rate_drop.sql` | `completed_calls / total_calls` | Caída de tasa de completación |
| `alert_3_quality_rate_drop.sql` | `good_calls / completed_calls` | Caída de calidad de conversación |
| `alert_4_short_call_rate_spike.sql` | `short_calls / completed_calls` | Spike en llamadas cortas |
| `alert_5_call_duration_anomaly.sql` | `avg_call_duration_seconds` | Duración anómala (↑ o ↓) |

#### Sub-Alertas (15 queries)

Cada alerta principal tiene 3 sub-alertas que la alimentan:

| Sufijo | Baseline | Ejemplo |
|--------|----------|---------|
| `_dod` | Day over Day (ayer) | `sub_alert_11_dod.sql` |
| `_wow` | Week over Week (semana pasada) | `sub_alert_12_wow.sql` |
| `_30davg` | Promedio 30 días | `sub_alert_13_30davg.sql` |

**Lógica de disparo:**
- La alerta principal muestra `CRITICAL` si los 3 sub-alerts son `CRITICAL`
- La alerta principal muestra `WARNING` si los 3 sub-alerts son `WARNING` o `CRITICAL`
- Si no hay consenso → `FINE` (no se muestra alerta)

---

### Tab 3: Métricas (Explicación de Alertas)

**Propósito:** Proveer contexto detallado para investigar y entender las alertas.

#### Current Summary

| Query | Descripción |
|-------|-------------|
| `current_summary_alert_1.sql` | Estado actual del día para volumen |
| `current_summary_alert_2.sql` | Estado actual para completion rate |
| `current_summary_alert_3.sql` | Estado actual para quality rate |
| `current_summary_alert_4.sql` | Estado actual para short call rate |
| `current_summary_alert_5.sql` | Estado actual para call duration |

**Contenido:** Muestra TODAS las organizaciones con su estado actual (FINE, WARNING, CRITICAL, INSUFFICIENT_DATA), no solo las alertas activas. Incluye:
- Valores actuales de la métrica
- Valores de los 3 baselines (DoD, WoW, 30d avg)
- Z-scores calculados
- Severidad de cada sub-alert

#### Hourly Summary

| Query | Descripción |
|-------|-------------|
| `hourly_summary_alert_1.sql` | Histórico 7 días por hora - volumen |
| `hourly_summary_alert_2.sql` | Histórico 7 días por hora - completion rate |
| `hourly_summary_alert_3.sql` | Histórico 7 días por hora - quality rate |
| `hourly_summary_alert_4.sql` | Histórico 7 días por hora - short call rate |
| `hourly_summary_alert_5.sql` | Histórico 7 días por hora - call duration |

**Contenido:** Vista histórica de los últimos 7 días con granularidad horaria. Permite:
- Ver tendencias y patrones
- Identificar horas problemáticas recurrentes
- Comparar días de la semana
- Detectar degradaciones graduales

---

## 1.4 Niveles de Severidad (Global)

Todas las alertas usan el mismo sistema de 4 niveles de severidad:

| Nivel | Significado | Acción Requerida |
|-------|-------------|------------------|
| 🔴 **CRITICAL** | Degradación severa que requiere atención inmediata | Investigación inmediata |
| 🟡 **WARNING** | Degradación moderada que debe monitorearse | Monitorear, investigar pronto |
| 🟢 **FINE** | Operación dentro de rangos normales | Ninguna |
| ⚪ **INSUFFICIENT_DATA** | Datos insuficientes para evaluar confiablemente | Ninguna (esperar más datos) |

> **Nota:** Cada alerta define sus propios umbrales específicos para determinar la severidad, dependiendo de la métrica que monitorea y su metodología de cálculo. Los detalles de umbrales se documentan en la Sección 5 (Detalle por Alerta).

---

# 2. TAB 1: CHARTS (Visualización)

## 2.1 Propósito

El Tab de Charts provee **contexto visual** del comportamiento de llamadas. Antes de investigar una alerta, los charts permiten:

- Identificar patrones temporales (horas pico, días de baja actividad)
- Detectar anomalías visuales que complementan las alertas numéricas
- Comparar el comportamiento actual vs días anteriores
- Entender la distribución de volumen por organización

---

## 2.2 Charts Disponibles

### 2.2.1 Total Calls por Día/Hora

**Query:** `charts/total_calls.sql`

**Descripción:** Heatmap que muestra el volumen total de llamadas por cada hora del día, para cada día del rango seleccionado. Permite visualizar patrones de operación y detectar caídas de volumen.

**Visualización recomendada:** Heatmap o Pivot Table con colores por intensidad.

#### Atributos de Salida

| Atributo | Tipo | Descripción | Ejemplo |
|----------|------|-------------|---------|
| `created_date` | DATE | Fecha de las llamadas | `2025-12-22` |
| `organization_name` | VARCHAR | Nombre de la organización | `Rappi` |
| `country` | VARCHAR(2) | Código ISO del país | `PE` |
| `hour_of_day` | INTEGER | Hora del día (0-23) | `14` |
| `total_calls` | INTEGER | Cantidad total de llamadas en esa hora | `87` |
| `block_status` | VARCHAR | Estado del bloque temporal para visualización | `PAST_DAY` |
| `block_label` | VARCHAR | Etiqueta corta para tooltips | `Lun 2025-12-22 - 14:00` |
| `day_label` | VARCHAR | Día formateado legible | `Lunes 22/12` |

#### Valores de `block_status`

| Valor | Significado |
|-------|-------------|
| `CURRENT_HOUR` | Es la hora actual del día de hoy |
| `TODAY_COMPLETED` | Hora de hoy que ya pasó |
| `TODAY_PENDING` | Hora de hoy que aún no llega |
| `PAST_DAY` | Hora de un día anterior |

#### Filtros Disponibles

| Filtro | Variable Metabase | Descripción |
|--------|-------------------|-------------|
| Rango de fechas | `{{time}}` | Filtra el período a visualizar |
| Organización | `{{organization_name}}` | Filtra por una organización específica |
| País | `{{countries}}` | Filtra por uno o más países |

#### Ejemplo de Resultado (Rappi PE - Semana del 16-22 Dic 2025)

| created_date | hour_of_day | total_calls | block_status | day_label |
|--------------|-------------|-------------|--------------|-----------|
| 2025-12-16 | 8 | 12 | PAST_DAY | Lunes 16/12 |
| 2025-12-16 | 9 | 45 | PAST_DAY | Lunes 16/12 |
| 2025-12-16 | 10 | 78 | PAST_DAY | Lunes 16/12 |
| 2025-12-16 | 11 | 92 | PAST_DAY | Lunes 16/12 |
| 2025-12-16 | 12 | 85 | PAST_DAY | Lunes 16/12 |
| ... | ... | ... | ... | ... |
| 2025-12-22 | 14 | 67 | TODAY_COMPLETED | Domingo 22/12 |
| 2025-12-22 | 15 | 43 | CURRENT_HOUR | Domingo 22/12 |
| 2025-12-22 | 16 | 0 | TODAY_PENDING | Domingo 22/12 |

---

### 2.2.2 Completed Calls por Día/Hora

**Query:** `charts/completed_calls.sql`

**Descripción:** Heatmap similar al anterior pero contando únicamente las llamadas completadas (excluye `failed` y `voicemail`). Útil para visualizar el volumen efectivo de contactos realizados.

**Visualización recomendada:** Heatmap o Pivot Table con colores por intensidad.

#### Atributos de Salida

Los atributos son idénticos a `total_calls.sql`. La diferencia está en el filtro interno de la query que solo cuenta llamadas con `call_classification IN ('good_calls', 'short_calls', 'completed')`.

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `created_date` | DATE | Fecha de las llamadas |
| `organization_name` | VARCHAR | Nombre de la organización |
| `country` | VARCHAR(2) | Código ISO del país |
| `hour_of_day` | INTEGER | Hora del día (0-23) |
| `total_calls` | INTEGER | Cantidad de **completed calls** en esa hora |
| `block_status` | VARCHAR | Estado del bloque temporal |
| `block_label` | VARCHAR | Etiqueta para tooltips |
| `day_label` | VARCHAR | Día formateado legible |

#### Filtros Disponibles

| Filtro | Variable Metabase | Descripción |
|--------|-------------------|-------------|
| Rango de fechas | `{{time}}` | Filtra el período a visualizar |
| Organización | `{{organization_name}}` | Filtra por una organización específica |
| País | `{{countries}}` | Filtra por uno o más países |

---

### 2.2.3 Total Calls - Todas las Organizaciones

**Query:** `charts/total_calls_all_orgs.sql`

**Descripción:** Vista agregada que muestra el volumen de llamadas por hora/día para **todas las organizaciones** simultáneamente. Permite comparar volúmenes relativos entre organizaciones y detectar si un problema es generalizado o específico de una organización.

**Visualización recomendada:** Stacked bar chart por organización, o tabla pivoteada con organizaciones como columnas.

#### Atributos de Salida

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `created_date` | DATE | Fecha de las llamadas |
| `organization_name` | VARCHAR | Nombre de la organización |
| `country` | VARCHAR(2) | Código ISO del país |
| `hour_of_day` | INTEGER | Hora del día (0-23) |
| `total_calls` | INTEGER | Cantidad total de llamadas |
| `block_status` | VARCHAR | Estado del bloque temporal |
| `block_label` | VARCHAR | Etiqueta para tooltips |
| `day_label` | VARCHAR | Día formateado legible |

#### Filtros Disponibles

| Filtro | Variable Metabase | Descripción |
|--------|-------------------|-------------|
| Rango de fechas | `{{time}}` | Filtra el período a visualizar |
| País | `{{countries}}` | Filtra por uno o más países |

> **Nota:** Este chart NO incluye filtro de `{{organization_name}}` porque su propósito es mostrar todas las organizaciones juntas.

#### Ejemplo de Uso

Comparar el volumen del Lunes 16/12 a las 10:00 AM entre organizaciones:

| organization_name | country | total_calls |
|-------------------|---------|-------------|
| Rappi | PE | 78 |
| Rappi | CO | 134 |
| Rappi | MX | 256 |
| Otro Cliente | PE | 45 |

---

## 2.3 Query SQL de Referencia

```sql
-- total_calls.sql (estructura simplificada)
WITH hourly_data AS (
  SELECT
    created_date,
    country,
    organization_name,
    hour_of_day,
    COUNT(*) AS total_calls,
    
    -- Estado del bloque para visualización
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
    END AS block_status
    
  FROM ai_calls_detail
  WHERE TRUE
    [[AND {{time}}]]
    [[AND {{organization_name}}]]
    [[AND {{countries}}]]
  GROUP BY created_date, hour_of_day, country, organization_name
)
SELECT * FROM hourly_data
ORDER BY created_date, hour_of_day;
```

---

*Continúa en Sección 3: Tab 2 - Alertas*

---

# 3. TAB 2: ALERTAS

## 3.1 Propósito

El Tab de Alertas muestra las **alertas activas** (CRITICAL y WARNING) que requieren atención del equipo. Solo aparecen alertas cuando se detecta una anomalía confirmada por múltiples baselines.

---

## 3.2 Estructura de Alertas

### Alertas Principales vs Sub-Alertas

El sistema usa una arquitectura de **dos niveles**:

```
┌─────────────────────────────────────────────────────────────────┐
│                    ALERTA PRINCIPAL                             │
│                    (alert_X.sql)                                │
│                                                                 │
│   Solo se dispara si los 3 sub-alerts coinciden en             │
│   WARNING o CRITICAL simultáneamente                            │
│                                                                 │
├─────────────────────────────────────────────────────────────────┤
│                                                                 │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐             │
│  │ Sub-Alert   │  │ Sub-Alert   │  │ Sub-Alert   │             │
│  │    X.1      │  │    X.2      │  │    X.3      │             │
│  │   (DoD)     │  │   (WoW)     │  │  (30d Avg)  │             │
│  └─────────────┘  └─────────────┘  └─────────────┘             │
│                                                                 │
└─────────────────────────────────────────────────────────────────┘
```

### Lógica de Disparo

| Condición | Resultado en Alerta Principal |
|-----------|-------------------------------|
| Los 3 sub-alerts son `CRITICAL` | `CRITICAL` |
| Los 3 sub-alerts son `WARNING` o `CRITICAL` (mezclados) | `WARNING` |
| Al menos 1 sub-alert es `FINE` o `INSUFFICIENT_DATA` | No se dispara (no aparece) |

Esta lógica de **consenso** reduce significativamente los falsos positivos.

---

## 3.3 Las 5 Alertas Principales

| # | Nombre | Query | Métrica | Dirección |
|---|--------|-------|---------|-----------|
| 1 | Volume Drop | `alert_1_volume_drop.sql` | `total_calls` | Lower is bad ↓ |
| 2 | Completion Rate Drop | `alert_2_completion_rate_drop.sql` | `completed_calls / total_calls` | Lower is bad ↓ |
| 3 | Quality Rate Drop | `alert_3_quality_rate_drop.sql` | `good_calls / completed_calls` | Lower is bad ↓ |
| 4 | Short Call Rate Spike | `alert_4_short_call_rate_spike.sql` | `short_calls / completed_calls` | Higher is bad ↑ |
| 5 | Call Duration Anomaly | `alert_5_call_duration_anomaly.sql` | `avg_call_duration_seconds` | Bidireccional ↕ |

### Resumen de Cada Alerta

#### Alert 1: Volume Drop
- **Qué detecta:** Caída significativa en el número total de llamadas realizadas
- **Cuándo es problema:** Cuando hay menos llamadas de las esperadas vs los 3 baselines
- **Posibles causas:** Sistema caído, integración fallida, problema de envío de datos del cliente

#### Alert 2: Completion Rate Drop
- **Qué detecta:** Caída en el porcentaje de llamadas que logran conectar
- **Fórmula:** `completed_calls / total_calls`
- **Cuándo es problema:** Muchas llamadas fallan antes de conectar
- **Posibles causas:** Números inválidos, problemas de telefonía, carrier issues

#### Alert 3: Quality Rate Drop
- **Qué detecta:** Caída en el porcentaje de conversaciones efectivas
- **Fórmula:** `good_calls / completed_calls`
- **Cuándo es problema:** Las llamadas conectan pero no logran engagement
- **Posibles causas:** Problemas de script, audio, o comportamiento del agente

#### Alert 4: Short Call Rate Spike
- **Qué detecta:** Aumento anormal en llamadas que terminan muy rápido
- **Fórmula:** `short_calls / completed_calls`
- **Cuándo es problema:** Usuarios cuelgan inmediatamente después de contestar
- **Posibles causas:** Primera impresión mala, problemas de audio, script inicial confuso

#### Alert 5: Call Duration Anomaly
- **Qué detecta:** Duración promedio de llamadas fuera de lo normal (muy cortas O muy largas)
- **Métrica:** `avg_call_duration_seconds`
- **Cuándo es problema:** 
  - TOO_SHORT: Llamadas terminan antes de lo esperado
  - TOO_LONG: Bot posiblemente atrapado en loops
- **Posibles causas:** Cambios en lógica del bot, problemas de finalización de llamada

---

## 3.4 Los 15 Sub-Alerts

Cada alerta principal tiene 3 sub-alerts que comparan contra diferentes baselines:

### Estructura de Nomenclatura

`sub_alert_XY_tipo.sql`

Donde:
- `X` = Número de alerta (1-5)
- `Y` = Número de sub-alert (1-3)
- `tipo` = Baseline usado (dod, wow, 30davg)

### Listado Completo

| Sub-Alert | Query | Baseline | Stddev Usado |
|-----------|-------|----------|--------------|
| **Alert 1: Volume Drop** ||||
| 1.1 | `sub_alert_11_dod.sql` | Ayer mismo momento | `stddev_all_days` |
| 1.2 | `sub_alert_12_wow.sql` | Hace 7 días mismo momento | `stddev_same_weekday` |
| 1.3 | `sub_alert_13_30davg.sql` | Promedio 30d mismo weekday | `stddev_same_weekday` |
| **Alert 2: Completion Rate Drop** ||||
| 2.1 | `sub_alert_21_dod.sql` | Ayer mismo momento | `stddev_all_days` |
| 2.2 | `sub_alert_22_wow.sql` | Hace 7 días mismo momento | `stddev_same_weekday` |
| 2.3 | `sub_alert_23_30davg.sql` | Promedio 30d mismo weekday | `stddev_same_weekday` |
| **Alert 3: Quality Rate Drop** ||||
| 3.1 | `sub_alert_31_dod.sql` | Ayer mismo momento | `stddev_all_days` |
| 3.2 | `sub_alert_32_wow.sql` | Hace 7 días mismo momento | `stddev_same_weekday` |
| 3.3 | `sub_alert_33_30davg.sql` | Promedio 30d mismo weekday | `stddev_same_weekday` |
| **Alert 4: Short Call Rate Spike** ||||
| 4.1 | `sub_alert_41_dod.sql` | Ayer mismo momento | `stddev_all_days` |
| 4.2 | `sub_alert_42_wow.sql` | Hace 7 días mismo momento | `stddev_same_weekday` |
| 4.3 | `sub_alert_43_30davg.sql` | Promedio 30d mismo weekday | `stddev_same_weekday` |
| **Alert 5: Call Duration Anomaly** ||||
| 5.1 | `sub_alert_51_dod.sql` | Ayer mismo momento | `stddev_all_days` |
| 5.2 | `sub_alert_52_wow.sql` | Hace 7 días mismo momento | `stddev_same_weekday` |
| 5.3 | `sub_alert_53_30davg.sql` | Promedio 30d mismo weekday | `stddev_same_weekday` |

### Explicación de Baselines

| Baseline | Abreviatura | Comparación | Uso de Stddev |
|----------|-------------|-------------|---------------|
| **Day over Day** | DoD | Hoy vs Ayer (mismo momento del día) | `stddev_all_days`: varianza de todos los días sin importar día de semana |
| **Week over Week** | WoW | Hoy vs Hace 7 días (mismo momento) | `stddev_same_weekday`: varianza solo de Lunes vs Lunes, Martes vs Martes, etc. |
| **30-Day Average** | 30d Avg | Hoy vs Promedio de los últimos 30 días del mismo día de semana | `stddev_same_weekday`: varianza del mismo día de semana |

### ¿Por qué diferentes Stddev?

- **DoD usa `stddev_all_days`:** Porque compara días consecutivos sin importar si ayer fue Lunes o Domingo. La variabilidad día-a-día incluye todos los patrones.

- **WoW y 30d Avg usan `stddev_same_weekday`:** Porque comparan el mismo día de semana (Lunes con Lunes, Viernes con Viernes). La variabilidad debe medirse solo contra días similares.

---

## 3.5 Concepto de Comparación "Apples-to-Apples"

Todas las comparaciones temporales se hacen **hasta el mismo momento del día**, no contra días completos.

### Ejemplo

Si hoy es **Lunes 22 de Diciembre a las 14:30**:

| Baseline | Se compara contra |
|----------|-------------------|
| DoD | Domingo 21 de Diciembre, datos hasta las 14:30 |
| WoW | Lunes 15 de Diciembre, datos hasta las 14:30 |
| 30d Avg | Promedio de todos los Lunes de los últimos 30 días, cada uno con datos hasta las 14:30 |

### Implementación en SQL

```sql
-- Filtro "apples-to-apples" usado en todos los baselines
AND (
    EXTRACT(HOUR FROM created_at) < EXTRACT(HOUR FROM CURRENT_TIMESTAMP())
    OR (
        EXTRACT(HOUR FROM created_at) = EXTRACT(HOUR FROM CURRENT_TIMESTAMP())
        AND EXTRACT(MINUTE FROM created_at) <= EXTRACT(MINUTE FROM CURRENT_TIMESTAMP())
    )
)
```

Este filtro asegura que solo se incluyan llamadas hasta la misma hora:minuto del día actual.

---

## 3.6 Atributos Comunes de Salida (Alertas Principales)

Las alertas principales comparten una estructura de salida similar:

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `organization_name` | VARCHAR | Nombre de la organización |
| `country` | VARCHAR(2) | Código ISO del país |
| `current_*` | FLOAT/INT | Valor actual de la métrica |
| `baseline_dod_*` | FLOAT/INT | Valor del baseline DoD |
| `baseline_wow_*` | FLOAT/INT | Valor del baseline WoW |
| `baseline_30d_*` | FLOAT/INT | Valor del baseline 30d Avg |
| `z_score_dod` | FLOAT | Desviación estándar vs DoD |
| `z_score_wow` | FLOAT | Desviación estándar vs WoW |
| `z_score_30d` | FLOAT | Desviación estándar vs 30d Avg |
| `severity_dod` | VARCHAR | Severidad del sub-alert DoD |
| `severity_wow` | VARCHAR | Severidad del sub-alert WoW |
| `severity_30d` | VARCHAR | Severidad del sub-alert 30d Avg |
| `main_severity` | VARCHAR | Severidad final de la alerta principal |
| `alert_message` | VARCHAR | Mensaje descriptivo de la alerta |

---

## 3.7 Filtros Disponibles

| Filtro | Variable Metabase | Disponible en |
|--------|-------------------|---------------|
| Organización | `{{organization_name}}` | Todas las alertas |
| País | `{{countries}}` | Todas las alertas |

> **Nota:** Las alertas no tienen filtro de fecha porque siempre muestran el estado **actual** en tiempo real.

---

*Continúa en Sección 4: Tab 3 - Métricas*

---

# 4. TAB 3: MÉTRICAS (Explicación de Alertas)

## 4.1 Propósito

El Tab de Métricas provee **contexto detallado** para investigar y entender las alertas. A diferencia del Tab 2 que solo muestra alertas activas, este tab muestra:

- **Todas las organizaciones** con su estado actual (incluyendo FINE e INSUFFICIENT_DATA)
- **Valores de todos los baselines** para comparación manual
- **Z-scores calculados** para entender la magnitud de las desviaciones
- **Histórico por hora** para identificar patrones y tendencias

---

## 4.2 Current Summary

### Descripción

Las queries de `current_summary` muestran el **estado actual del día** para cada métrica. Proveen una foto instantánea de todas las organizaciones con sus valores actuales, baselines y severidades calculadas.

### Queries Disponibles

| Query | Métrica Monitoreada |
|-------|---------------------|
| `current_summary_alert_1.sql` | Volume (total_calls) |
| `current_summary_alert_2.sql` | Completion Rate (completed_calls / total_calls) |
| `current_summary_alert_3.sql` | Quality Rate (good_calls / completed_calls) |
| `current_summary_alert_4.sql` | Short Call Rate (short_calls / completed_calls) |
| `current_summary_alert_5.sql` | Call Duration (avg_call_duration_seconds) |

### Atributos de Salida (Ejemplo: current_summary_alert_1)

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `organization_name` | VARCHAR | Nombre de la organización |
| `country` | VARCHAR(2) | Código ISO del país |
| `current_total_calls` | INTEGER | Llamadas totales hoy hasta este momento |
| `baseline_dod_total_calls` | INTEGER | Llamadas de ayer al mismo momento |
| `baseline_wow_total_calls` | INTEGER | Llamadas hace 7 días al mismo momento |
| `baseline_30d_avg_total_calls` | FLOAT | Promedio de llamadas de los últimos 30 días (mismo weekday, mismo momento) |
| `absolute_change_dod` | INTEGER | Diferencia absoluta vs ayer |
| `absolute_change_wow` | INTEGER | Diferencia absoluta vs semana pasada |
| `absolute_change_30d` | FLOAT | Diferencia absoluta vs promedio 30d |
| `pct_change_dod` | FLOAT | Cambio porcentual vs ayer |
| `pct_change_wow` | FLOAT | Cambio porcentual vs semana pasada |
| `pct_change_30d` | FLOAT | Cambio porcentual vs promedio 30d |
| `z_score_dod` | FLOAT | Desviaciones estándar vs ayer |
| `z_score_wow` | FLOAT | Desviaciones estándar vs semana pasada |
| `z_score_30d` | FLOAT | Desviaciones estándar vs promedio 30d |
| `severity_dod` | VARCHAR | Severidad del sub-alert DoD |
| `severity_wow` | VARCHAR | Severidad del sub-alert WoW |
| `severity_30d` | VARCHAR | Severidad del sub-alert 30d |
| `main_severity` | VARCHAR | Severidad combinada (requiere consenso de los 3) |

### Ejemplo de Resultado (Rappi PE - 22 Dic 2025 a las 14:30)

| organization_name | country | current_total_calls | baseline_dod | baseline_wow | baseline_30d_avg | z_score_dod | z_score_wow | z_score_30d | severity_dod | severity_wow | severity_30d | main_severity |
|-------------------|---------|---------------------|--------------|--------------|------------------|-------------|-------------|-------------|--------------|--------------|--------------|---------------|
| Rappi | PE | 245 | 312 | 287 | 295 | -2.3 | -1.8 | -2.1 | WARNING | FINE | WARNING | FINE |
| Rappi | CO | 456 | 423 | 445 | 438 | 0.8 | 0.3 | 0.5 | FINE | FINE | FINE | FINE |
| Rappi | MX | 89 | 245 | 234 | 228 | -3.1 | -2.8 | -2.9 | CRITICAL | CRITICAL | CRITICAL | CRITICAL |

**Interpretación del ejemplo:**
- **Rappi PE:** Tiene z-scores negativos pero solo 2 de 3 sub-alerts son WARNING → `main_severity = FINE` (no hay consenso)
- **Rappi CO:** Todos los z-scores están cerca de 0 → Todo FINE
- **Rappi MX:** Los 3 sub-alerts son CRITICAL → `main_severity = CRITICAL` (hay consenso)

### Filtros Disponibles

| Filtro | Variable Metabase | Descripción |
|--------|-------------------|-------------|
| Organización | `{{organization_name}}` | Filtrar por organización específica |
| País | `{{country}}` | Filtrar por país |

---

## 4.3 Hourly Summary

### Descripción

Las queries de `hourly_summary` muestran el **histórico de los últimos 7 días con granularidad horaria**. Permiten:

- Ver la evolución temporal de cada métrica
- Identificar horas del día problemáticas de forma recurrente
- Comparar el comportamiento entre días de la semana
- Detectar degradaciones graduales que no disparan alertas instantáneas

### Queries Disponibles

| Query | Métrica Monitoreada |
|-------|---------------------|
| `hourly_summary_alert_1.sql` | Volume (total_calls) |
| `hourly_summary_alert_2.sql` | Completion Rate |
| `hourly_summary_alert_3.sql` | Quality Rate |
| `hourly_summary_alert_4.sql` | Short Call Rate |
| `hourly_summary_alert_5.sql` | Call Duration |

### Atributos de Salida (Ejemplo: hourly_summary_alert_1)

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `eval_hour` | TIMESTAMP | Hora evaluada (truncada a hora) |
| `eval_date` | DATE | Fecha de la evaluación |
| `hour_of_day` | INTEGER | Hora del día (0-23) |
| `day_of_week` | INTEGER | Día de la semana (1=Domingo, 7=Sábado) |
| `organization_name` | VARCHAR | Nombre de la organización |
| `country` | VARCHAR(2) | Código ISO del país |
| `current_total_calls` | INTEGER | Llamadas en esa hora |
| `baseline_dod_total_calls` | INTEGER | Llamadas del día anterior a la misma hora |
| `baseline_wow_total_calls` | INTEGER | Llamadas de hace 7 días a la misma hora |
| `baseline_30d_avg_total_calls` | FLOAT | Promedio de la misma hora en los últimos 30 días |
| `absolute_change_dod` | INTEGER | Diferencia vs día anterior |
| `absolute_change_wow` | INTEGER | Diferencia vs semana pasada |
| `z_score_dod` | FLOAT | Z-score vs día anterior |
| `z_score_wow` | FLOAT | Z-score vs semana pasada |
| `z_score_30d` | FLOAT | Z-score vs promedio 30d |
| `severity_dod` | VARCHAR | Severidad sub-alert DoD para esa hora |
| `severity_wow` | VARCHAR | Severidad sub-alert WoW para esa hora |
| `severity_30d` | VARCHAR | Severidad sub-alert 30d para esa hora |
| `main_severity` | VARCHAR | Severidad combinada para esa hora |

### Ejemplo de Resultado (Rappi PE - Últimos 3 días, horas 9-12)

| eval_date | hour_of_day | current_total_calls | baseline_dod | baseline_wow | z_score_dod | z_score_wow | main_severity |
|-----------|-------------|---------------------|--------------|--------------|-------------|-------------|---------------|
| 2025-12-20 | 9 | 45 | 42 | 48 | 0.3 | -0.4 | FINE |
| 2025-12-20 | 10 | 78 | 81 | 75 | -0.2 | 0.3 | FINE |
| 2025-12-20 | 11 | 92 | 88 | 95 | 0.4 | -0.3 | FINE |
| 2025-12-20 | 12 | 85 | 90 | 82 | -0.5 | 0.3 | FINE |
| 2025-12-21 | 9 | 38 | 45 | 42 | -0.8 | -0.5 | FINE |
| 2025-12-21 | 10 | 65 | 78 | 81 | -1.2 | -1.5 | FINE |
| 2025-12-21 | 11 | 71 | 92 | 88 | -2.1 | -1.7 | FINE |
| 2025-12-21 | 12 | 68 | 85 | 90 | -1.8 | -2.3 | FINE |
| 2025-12-22 | 9 | 22 | 38 | 45 | -2.4 | -2.8 | WARNING |
| 2025-12-22 | 10 | 35 | 65 | 78 | -2.9 | -3.1 | CRITICAL |
| 2025-12-22 | 11 | 41 | 71 | 92 | -2.7 | -3.5 | CRITICAL |
| 2025-12-22 | 12 | 38 | 68 | 85 | -2.6 | -3.2 | CRITICAL |

**Interpretación del ejemplo:**
- **20 Dic:** Comportamiento normal, z-scores cercanos a 0
- **21 Dic:** Empiezan a verse z-scores negativos, pero sin alcanzar umbrales
- **22 Dic:** Degradación clara, múltiples horas en WARNING y CRITICAL

### Filtros Disponibles

| Filtro | Variable Metabase | Descripción |
|--------|-------------------|-------------|
| Organización | `{{organization_name}}` | Filtrar por organización específica |
| País | `{{country}}` | Filtrar por país |

### Visualización Recomendada

- **Line chart:** Para ver tendencia temporal de la métrica
- **Heatmap:** Con `eval_date` en Y, `hour_of_day` en X, y color por `main_severity`
- **Table:** Para análisis detallado de valores específicos

---

## 4.4 Diferencias entre Current Summary y Hourly Summary

| Aspecto | Current Summary | Hourly Summary |
|---------|-----------------|----------------|
| **Granularidad temporal** | Acumulado del día hasta el momento actual | Por hora individual |
| **Rango de datos** | Solo hoy | Últimos 7 días |
| **Filas por org/país** | 1 fila | Múltiples filas (1 por hora) |
| **Uso principal** | Estado actual en tiempo real | Análisis de tendencias e histórico |
| **Cuándo usar** | Monitoreo continuo, investigación inmediata | Análisis post-mortem, identificación de patrones |

---

## 4.5 Cómo Usar el Tab de Métricas

### Escenario 1: Investigar una alerta activa

1. Ver la alerta en Tab 2 (Alertas)
2. Ir a Tab 3 → Current Summary de la métrica correspondiente
3. Revisar los z-scores individuales para entender cuál baseline tiene mayor desviación
4. Ir a Hourly Summary para ver si es un problema reciente o una tendencia

### Escenario 2: Monitoreo proactivo

1. Revisar Current Summary periódicamente
2. Identificar organizaciones con z-scores negativos aunque no hayan disparado alerta
3. Monitorear si los z-scores empeoran con el tiempo

### Escenario 3: Análisis post-mortem

1. Ir a Hourly Summary
2. Filtrar por la organización afectada
3. Identificar el momento exacto donde comenzó la degradación
4. Correlacionar con eventos conocidos (deploys, cambios de configuración, etc.)

---

*Continúa en Sección 5: Detalle por Alerta*

---

# 5. DETALLE POR ALERTA

Esta sección documenta cada alerta en profundidad: fórmulas de cálculo, umbrales, justificación estadística y ejemplos prácticos.

---

## 5.1 Alert 1: Volume Drop

### Descripción General

| Aspecto | Detalle |
|---------|---------|
| **Objetivo** | Detectar caídas significativas en el volumen de llamadas realizadas |
| **Métrica** | `total_calls` |
| **Dirección** | Lower is bad (↓) |
| **Granularidad** | Diaria acumulada hasta el momento actual |
| **Query principal** | `alert_1_volume_drop.sql` |

### Fórmula de Cálculo

```
total_calls = COUNT(*) de ai_calls_detail
              WHERE created_date = CURRENT_DATE()
              AND created_at <= CURRENT_TIMESTAMP()
```

### Sub-Alerts

| Sub-Alert | Query | Baseline | Descripción |
|-----------|-------|----------|-------------|
| 1.1 | `sub_alert_11_dod.sql` | Ayer mismo momento | Compara total_calls de hoy vs ayer hasta la misma hora:minuto |
| 1.2 | `sub_alert_12_wow.sql` | Hace 7 días mismo momento | Compara total_calls de hoy vs hace una semana hasta la misma hora:minuto |
| 1.3 | `sub_alert_13_30davg.sql` | Promedio 30d mismo weekday | Compara total_calls de hoy vs promedio de los últimos 30 días del mismo día de semana |

### Cálculo del Z-Score

```
z_score = (valor_actual - valor_baseline) / stddev

Donde:
- Para DoD: stddev = stddev_all_days (varianza de todos los días)
- Para WoW y 30d: stddev = stddev_same_weekday (varianza del mismo día de semana)
```

### Umbrales de Severidad

| Severidad | Condición Z-Score | Interpretación |
|-----------|-------------------|----------------|
| 🔴 CRITICAL | z_score < -2.5 | Caída extrema: más de 2.5 desviaciones estándar por debajo |
| 🟡 WARNING | z_score < -2.0 | Caída significativa: más de 2.0 desviaciones estándar por debajo |
| 🟢 FINE | z_score >= -2.0 | Dentro del rango normal de variación |

### Criterios de INSUFFICIENT_DATA

| Criterio | Umbral | Razón |
|----------|--------|-------|
| Pocas llamadas hoy | < 30 calls | Muestra insuficiente para evaluación confiable |
| Sin baseline | baseline = NULL | No hay datos del período de comparación |
| Poca historia | sample_size < 10 (DoD) o < 3 (WoW) | Varianza no representativa |
| Sin varianza | stddev = 0 | No se puede calcular z-score |

### Ejemplo Práctico (Rappi PE - Lunes 22 Dic 2025 a las 14:30)

**Datos de entrada:**

| Período | total_calls |
|---------|-------------|
| Hoy (Lunes hasta 14:30) | 156 |
| Ayer (Domingo hasta 14:30) | 189 |
| Hace 7 días (Lunes 15 Dic hasta 14:30) | 245 |
| Promedio Lunes últimos 30d (hasta 14:30) | 238 |
| stddev_all_days | 42 |
| stddev_same_weekday (Lunes) | 35 |

**Cálculos:**

```
Z-Score DoD = (156 - 189) / 42 = -0.79  → FINE
Z-Score WoW = (156 - 245) / 35 = -2.54  → CRITICAL
Z-Score 30d = (156 - 238) / 35 = -2.34  → WARNING
```

**Resultado:**

| Sub-Alert | Z-Score | Severidad |
|-----------|---------|-----------|
| 1.1 (DoD) | -0.79 | FINE |
| 1.2 (WoW) | -2.54 | CRITICAL |
| 1.3 (30d) | -2.34 | WARNING |
| **Main Alert** | - | **FINE** (no hay consenso) |

**Interpretación:** Aunque hay caídas significativas vs la semana pasada y el promedio histórico, la comparación vs ayer está bien. Esto sugiere que el Domingo tuvo bajo volumen (normal para fin de semana) y hoy Lunes aún no recupera. No se dispara alerta porque no hay consenso de los 3 sub-alerts.

### Atributos de Salida Específicos

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `current_total_calls` | INTEGER | Llamadas totales hoy hasta el momento actual |
| `baseline_dod_total_calls` | INTEGER | Llamadas de ayer al mismo momento |
| `baseline_wow_total_calls` | INTEGER | Llamadas hace 7 días al mismo momento |
| `baseline_30d_avg_total_calls` | FLOAT | Promedio de llamadas (mismo weekday, últimos 30d) |
| `absolute_change_dod` | INTEGER | current - baseline_dod |
| `absolute_change_wow` | INTEGER | current - baseline_wow |
| `absolute_change_30d` | FLOAT | current - baseline_30d |
| `pct_change_dod` | FLOAT | Cambio porcentual vs ayer |
| `pct_change_wow` | FLOAT | Cambio porcentual vs semana pasada |
| `pct_change_30d` | FLOAT | Cambio porcentual vs promedio 30d |

---

## 5.2 Alert 2: Completion Rate Drop

### Descripción General

| Aspecto | Detalle |
|---------|---------|
| **Objetivo** | Detectar caídas en el porcentaje de llamadas que logran conectar |
| **Métrica** | `completion_rate = completed_calls / total_calls` |
| **Dirección** | Lower is bad (↓) |
| **Granularidad** | Diaria acumulada hasta el momento actual |
| **Query principal** | `alert_2_completion_rate_drop.sql` |

### Fórmula de Cálculo

```
completion_rate = completed_calls / total_calls

Donde:
- completed_calls = COUNT(*) WHERE call_classification IN ('good_calls', 'short_calls', 'completed')
- total_calls = COUNT(*) de todas las llamadas
```

**Nota:** Las llamadas `failed` y `voicemail` NO se cuentan como completed.

### Sub-Alerts

| Sub-Alert | Query | Baseline | Descripción |
|-----------|-------|----------|-------------|
| 2.1 | `sub_alert_21_dod.sql` | Ayer mismo momento | Compara completion_rate de hoy vs ayer |
| 2.2 | `sub_alert_22_wow.sql` | Hace 7 días mismo momento | Compara completion_rate de hoy vs hace una semana |
| 2.3 | `sub_alert_23_30davg.sql` | Promedio 30d mismo weekday | Compara completion_rate de hoy vs promedio histórico |

### Cálculo del Z-Score

```
z_score = (completion_rate_actual - completion_rate_baseline) / stddev

Donde el stddev se calcula sobre los completion_rates históricos, no sobre conteos.
```

### Umbrales de Severidad

| Severidad | Condición Z-Score | Interpretación |
|-----------|-------------------|----------------|
| 🔴 CRITICAL | z_score < -2.5 | Caída extrema en tasa de completación |
| 🟡 WARNING | z_score < -2.0 | Caída significativa en tasa de completación |
| 🟢 FINE | z_score >= -2.0 | Tasa de completación dentro del rango normal |

### Criterios de INSUFFICIENT_DATA

| Criterio | Umbral | Razón |
|----------|--------|-------|
| Pocas llamadas hoy | < 30 total_calls | Tasa calculada sobre muestra pequeña no es confiable |
| Pocas llamadas en baseline | < 30 total_calls | Baseline no confiable |
| Poca historia | sample_size < 10 (DoD) o < 3 (WoW) | Varianza no representativa |
| Sin varianza | stddev = 0 | No se puede calcular z-score |

### Ejemplo Práctico (Rappi PE - Lunes 22 Dic 2025 a las 14:30)

**Datos de entrada:**

| Período | total_calls | completed_calls | completion_rate |
|---------|-------------|-----------------|-----------------|
| Hoy (Lunes hasta 14:30) | 156 | 118 | 0.756 (75.6%) |
| Ayer (Domingo hasta 14:30) | 189 | 152 | 0.804 (80.4%) |
| Hace 7 días (Lunes 15 Dic hasta 14:30) | 245 | 208 | 0.849 (84.9%) |
| Promedio Lunes últimos 30d | - | - | 0.832 (83.2%) |
| stddev_all_days | - | - | 0.045 |
| stddev_same_weekday (Lunes) | - | - | 0.038 |

**Cálculos:**

```
Z-Score DoD = (0.756 - 0.804) / 0.045 = -1.07  → FINE
Z-Score WoW = (0.756 - 0.849) / 0.038 = -2.45  → WARNING
Z-Score 30d = (0.756 - 0.832) / 0.038 = -2.00  → WARNING
```

**Resultado:**

| Sub-Alert | Z-Score | Severidad |
|-----------|---------|-----------|
| 2.1 (DoD) | -1.07 | FINE |
| 2.2 (WoW) | -2.45 | WARNING |
| 2.3 (30d) | -2.00 | WARNING |
| **Main Alert** | - | **FINE** (no hay consenso, DoD es FINE) |

**Interpretación:** La tasa de completación está por debajo del histórico semanal y mensual, pero comparado con ayer no hay caída significativa. Esto sugiere que la tasa baja viene de días anteriores, no es un problema nuevo de hoy.

### Atributos de Salida Específicos

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `current_total_calls` | INTEGER | Llamadas totales hoy |
| `current_completed_calls` | INTEGER | Llamadas completadas hoy |
| `current_completion_rate` | FLOAT | Tasa de completación actual (0-1) |
| `baseline_dod_rate` | FLOAT | Tasa de completación de ayer |
| `baseline_wow_rate` | FLOAT | Tasa de completación hace 7 días |
| `baseline_30d_rate` | FLOAT | Tasa promedio de completación (mismo weekday, 30d) |
| `pp_change_dod` | FLOAT | Cambio en puntos porcentuales vs ayer |
| `pp_change_wow` | FLOAT | Cambio en puntos porcentuales vs semana pasada |
| `pp_change_30d` | FLOAT | Cambio en puntos porcentuales vs promedio 30d |

---

## 5.3 Alert 3: Quality Rate Drop

### Descripción General

| Aspecto | Detalle |
|---------|---------|
| **Objetivo** | Detectar caídas en el porcentaje de conversaciones efectivas |
| **Métrica** | `quality_rate = good_calls / completed_calls` |
| **Dirección** | Lower is bad (↓) |
| **Granularidad** | Diaria acumulada hasta el momento actual |
| **Query principal** | `alert_3_quality_rate_drop.sql` |

### Fórmula de Cálculo

```
quality_rate = good_calls / completed_calls

Donde:
- good_calls = COUNT(*) WHERE call_classification = 'good_calls'
- completed_calls = COUNT(*) WHERE call_classification IN ('good_calls', 'short_calls', 'completed')
```

**Diferencia con Completion Rate:**
- **Completion Rate:** Mide qué porcentaje de llamadas CONECTA (vs las que fallan)
- **Quality Rate:** Mide qué porcentaje de llamadas conectadas son EFECTIVAS (good vs short)

### Sub-Alerts

| Sub-Alert | Query | Baseline | Descripción |
|-----------|-------|----------|-------------|
| 3.1 | `sub_alert_31_dod.sql` | Ayer mismo momento | Compara quality_rate de hoy vs ayer |
| 3.2 | `sub_alert_32_wow.sql` | Hace 7 días mismo momento | Compara quality_rate de hoy vs hace una semana |
| 3.3 | `sub_alert_33_30davg.sql` | Promedio 30d mismo weekday | Compara quality_rate de hoy vs promedio histórico |

### Cálculo del Z-Score

```
z_score = (quality_rate_actual - quality_rate_baseline) / stddev
```

### Umbrales de Severidad

| Severidad | Condición Z-Score | Interpretación |
|-----------|-------------------|----------------|
| 🔴 CRITICAL | z_score < -2.5 | Caída extrema en calidad de conversaciones |
| 🟡 WARNING | z_score < -2.0 | Caída significativa en calidad |
| 🟢 FINE | z_score >= -2.0 | Calidad dentro del rango normal |

### Criterios de INSUFFICIENT_DATA

| Criterio | Umbral | Razón |
|----------|--------|-------|
| Pocas llamadas completadas hoy | < 30 completed_calls | Tasa sobre muestra pequeña no es confiable |
| Pocas llamadas completadas en baseline | < 30 completed_calls | Baseline no confiable |
| Poca historia | sample_size < 10 (DoD) o < 3 (WoW) | Varianza no representativa |
| Sin varianza | stddev = 0 | No se puede calcular z-score |

### Ejemplo Práctico (Rappi PE - Lunes 22 Dic 2025 a las 14:30)

**Datos de entrada:**

| Período | completed_calls | good_calls | quality_rate |
|---------|-----------------|------------|--------------|
| Hoy (Lunes hasta 14:30) | 118 | 72 | 0.610 (61.0%) |
| Ayer (Domingo hasta 14:30) | 152 | 98 | 0.645 (64.5%) |
| Hace 7 días (Lunes 15 Dic hasta 14:30) | 208 | 156 | 0.750 (75.0%) |
| Promedio Lunes últimos 30d | - | - | 0.725 (72.5%) |
| stddev_all_days | - | - | 0.052 |
| stddev_same_weekday (Lunes) | - | - | 0.041 |

**Cálculos:**

```
Z-Score DoD = (0.610 - 0.645) / 0.052 = -0.67  → FINE
Z-Score WoW = (0.610 - 0.750) / 0.041 = -3.41  → CRITICAL
Z-Score 30d = (0.610 - 0.725) / 0.041 = -2.80  → CRITICAL
```

**Resultado:**

| Sub-Alert | Z-Score | Severidad |
|-----------|---------|-----------|
| 3.1 (DoD) | -0.67 | FINE |
| 3.2 (WoW) | -3.41 | CRITICAL |
| 3.3 (30d) | -2.80 | CRITICAL |
| **Main Alert** | - | **FINE** (no hay consenso, DoD es FINE) |

**Interpretación:** La calidad está muy por debajo del histórico, pero vs ayer no hay cambio significativo. Esto indica un problema que viene de días anteriores, posiblemente desde el fin de semana. Aunque no dispara alerta principal, amerita investigación.

### Atributos de Salida Específicos

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `current_completed_calls` | INTEGER | Llamadas completadas hoy |
| `current_good_calls` | INTEGER | Llamadas buenas hoy |
| `current_quality_rate` | FLOAT | Tasa de calidad actual (0-1) |
| `baseline_dod_rate` | FLOAT | Tasa de calidad de ayer |
| `baseline_dod_good` | INTEGER | Good calls de ayer |
| `baseline_dod_completed` | INTEGER | Completed calls de ayer |
| `baseline_wow_rate` | FLOAT | Tasa de calidad hace 7 días |
| `baseline_30d_rate` | FLOAT | Tasa promedio de calidad (mismo weekday, 30d) |
| `pp_change_dod` | FLOAT | Cambio en puntos porcentuales vs ayer |
| `pp_change_wow` | FLOAT | Cambio en puntos porcentuales vs semana pasada |
| `pp_change_30d` | FLOAT | Cambio en puntos porcentuales vs promedio 30d |

---

## 5.4 Alert 4: Short Call Rate Spike

### Descripción General

| Aspecto | Detalle |
|---------|---------|
| **Objetivo** | Detectar aumentos anormales en llamadas que terminan muy rápido |
| **Métrica** | `short_call_rate = short_calls / completed_calls` |
| **Dirección** | Higher is bad (↑) - Opuesto a las alertas 1-3 |
| **Granularidad** | Diaria acumulada hasta el momento actual |
| **Query principal** | `alert_4_short_call_rate_spike.sql` |

### Fórmula de Cálculo

```
short_call_rate = short_calls / completed_calls

Donde:
- short_calls = COUNT(*) WHERE call_classification = 'short_calls'
- completed_calls = COUNT(*) WHERE call_classification IN ('good_calls', 'short_calls', 'completed')
```

**¿Qué es una short call?**
Una llamada que conectó pero tuvo una conversación muy breve (< 1000 caracteres de transcripción). Indica que el usuario colgó rápidamente después de contestar.

### Sub-Alerts

| Sub-Alert | Query | Baseline | Descripción |
|-----------|-------|----------|-------------|
| 4.1 | `sub_alert_41_dod.sql` | Ayer mismo momento | Compara short_call_rate de hoy vs ayer |
| 4.2 | `sub_alert_42_wow.sql` | Hace 7 días mismo momento | Compara short_call_rate de hoy vs hace una semana |
| 4.3 | `sub_alert_43_30davg.sql` | Promedio 30d mismo weekday | Compara short_call_rate de hoy vs promedio histórico |

### Cálculo del Z-Score

```
z_score = (short_call_rate_actual - short_call_rate_baseline) / stddev
```

**Importante:** En esta alerta, un z_score POSITIVO es malo (indica spike), al contrario de las alertas 1-3.

### Umbrales de Severidad

| Severidad | Condición Z-Score | Interpretación |
|-----------|-------------------|----------------|
| 🔴 CRITICAL | z_score > +2.5 | Spike extremo en llamadas cortas |
| 🟡 WARNING | z_score > +2.0 | Spike significativo en llamadas cortas |
| 🟢 FINE | z_score <= +2.0 | Tasa de llamadas cortas dentro del rango normal |

### Criterios de INSUFFICIENT_DATA

| Criterio | Umbral | Razón |
|----------|--------|-------|
| Pocas llamadas completadas hoy | < 30 completed_calls | Tasa sobre muestra pequeña no es confiable |
| Pocas llamadas completadas en baseline | < 30 completed_calls | Baseline no confiable |
| Poca historia | sample_size < 10 (DoD) o < 3 (WoW) | Varianza no representativa |
| Sin varianza | stddev = 0 | No se puede calcular z-score |

### Ejemplo Práctico (Rappi PE - Lunes 22 Dic 2025 a las 14:30)

**Datos de entrada:**

| Período | completed_calls | short_calls | short_call_rate |
|---------|-----------------|-------------|-----------------|
| Hoy (Lunes hasta 14:30) | 118 | 46 | 0.390 (39.0%) |
| Ayer (Domingo hasta 14:30) | 152 | 54 | 0.355 (35.5%) |
| Hace 7 días (Lunes 15 Dic hasta 14:30) | 208 | 52 | 0.250 (25.0%) |
| Promedio Lunes últimos 30d | - | - | 0.275 (27.5%) |
| stddev_all_days | - | - | 0.048 |
| stddev_same_weekday (Lunes) | - | - | 0.039 |

**Cálculos:**

```
Z-Score DoD = (0.390 - 0.355) / 0.048 = +0.73  → FINE
Z-Score WoW = (0.390 - 0.250) / 0.039 = +3.59  → CRITICAL
Z-Score 30d = (0.390 - 0.275) / 0.039 = +2.95  → CRITICAL
```

**Resultado:**

| Sub-Alert | Z-Score | Severidad |
|-----------|---------|-----------|
| 4.1 (DoD) | +0.73 | FINE |
| 4.2 (WoW) | +3.59 | CRITICAL |
| 4.3 (30d) | +2.95 | CRITICAL |
| **Main Alert** | - | **FINE** (no hay consenso, DoD es FINE) |

**Interpretación:** La tasa de short calls es muy alta comparada con el histórico, pero solo ligeramente superior a ayer. El problema viene acumulándose desde días anteriores. La tendencia es preocupante aunque no dispare alerta.

### Atributos de Salida Específicos

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `current_completed_calls` | INTEGER | Llamadas completadas hoy |
| `current_short_calls` | INTEGER | Llamadas cortas hoy |
| `current_short_call_rate` | FLOAT | Tasa de llamadas cortas actual (0-1) |
| `baseline_dod_rate` | FLOAT | Tasa de short calls de ayer |
| `baseline_dod_short` | INTEGER | Short calls de ayer |
| `baseline_dod_completed` | INTEGER | Completed calls de ayer |
| `baseline_wow_rate` | FLOAT | Tasa de short calls hace 7 días |
| `baseline_30d_rate` | FLOAT | Tasa promedio de short calls (mismo weekday, 30d) |
| `pp_change_dod` | FLOAT | Cambio en puntos porcentuales vs ayer (positivo = peor) |
| `pp_change_wow` | FLOAT | Cambio en puntos porcentuales vs semana pasada |
| `pp_change_30d` | FLOAT | Cambio en puntos porcentuales vs promedio 30d |

---

## 5.5 Alert 5: Call Duration Anomaly

### Descripción General

| Aspecto | Detalle |
|---------|---------|
| **Objetivo** | Detectar duración promedio de llamadas fuera de lo normal |
| **Métrica** | `avg_call_duration_seconds` |
| **Dirección** | Bidireccional (↕) - Tanto muy corto como muy largo es malo |
| **Granularidad** | Diaria acumulada hasta el momento actual |
| **Query principal** | `alert_5_call_duration_anomaly.sql` |

### Fórmula de Cálculo

```
avg_call_duration_seconds = AVG(call_duration_seconds)
                            WHERE call_classification IN ('good_calls', 'short_calls', 'completed')
```

**Nota:** Solo se calcula sobre llamadas completadas, no sobre llamadas fallidas.

### Sub-Alerts

| Sub-Alert | Query | Baseline | Descripción |
|-----------|-------|----------|-------------|
| 5.1 | `sub_alert_51_dod.sql` | Ayer mismo momento | Compara duración promedio de hoy vs ayer |
| 5.2 | `sub_alert_52_wow.sql` | Hace 7 días mismo momento | Compara duración promedio de hoy vs hace una semana |
| 5.3 | `sub_alert_53_30davg.sql` | Promedio 30d mismo weekday | Compara duración promedio de hoy vs promedio histórico |

### Cálculo del Z-Score

```
z_score = (avg_duration_actual - avg_duration_baseline) / stddev
```

### Umbrales de Severidad (BIDIRECCIONAL)

| Severidad | Condición Z-Score | Tipo de Anomalía | Interpretación |
|-----------|-------------------|------------------|----------------|
| 🔴 CRITICAL | z_score < -2.5 | TOO_SHORT | Llamadas anormalmente cortas |
| 🔴 CRITICAL | z_score > +2.5 | TOO_LONG | Llamadas anormalmente largas |
| 🟡 WARNING | z_score < -2.0 | TOO_SHORT | Llamadas más cortas de lo normal |
| 🟡 WARNING | z_score > +2.0 | TOO_LONG | Llamadas más largas de lo normal |
| 🟢 FINE | -2.0 <= z_score <= +2.0 | NORMAL | Duración dentro del rango esperado |

**Importante:** Esta alerta usa el valor absoluto del z-score (`|z_score|`) para determinar severidad, pero preserva el signo para indicar la dirección (TOO_SHORT vs TOO_LONG).

### Criterios de INSUFFICIENT_DATA

| Criterio | Umbral | Razón |
|----------|--------|-------|
| Pocas llamadas completadas hoy | < 30 completed_calls | Promedio sobre muestra pequeña es volátil |
| Pocas llamadas completadas en baseline | < 30 completed_calls | Baseline no confiable |
| Poca historia | sample_size < 10 (DoD) o < 3 (WoW) | Varianza no representativa |
| Sin varianza | stddev = 0 | No se puede calcular z-score |

### Ejemplo Práctico - TOO_SHORT (Rappi PE - Lunes 22 Dic 2025 a las 14:30)

**Datos de entrada:**

| Período | completed_calls | avg_duration_seconds |
|---------|-----------------|----------------------|
| Hoy (Lunes hasta 14:30) | 118 | 45.2s |
| Ayer (Domingo hasta 14:30) | 152 | 52.8s |
| Hace 7 días (Lunes 15 Dic hasta 14:30) | 208 | 78.5s |
| Promedio Lunes últimos 30d | - | 82.3s |
| stddev_all_days | - | 12.5s |
| stddev_same_weekday (Lunes) | - | 9.8s |

**Cálculos:**

```
Z-Score DoD = (45.2 - 52.8) / 12.5 = -0.61  → FINE
Z-Score WoW = (45.2 - 78.5) / 9.8 = -3.40  → CRITICAL (TOO_SHORT)
Z-Score 30d = (45.2 - 82.3) / 9.8 = -3.79  → CRITICAL (TOO_SHORT)
```

**Resultado:**

| Sub-Alert | Z-Score | Severidad | Tipo |
|-----------|---------|-----------|------|
| 5.1 (DoD) | -0.61 | FINE | - |
| 5.2 (WoW) | -3.40 | CRITICAL | TOO_SHORT |
| 5.3 (30d) | -3.79 | CRITICAL | TOO_SHORT |
| **Main Alert** | - | **FINE** | - |

**Interpretación:** Las llamadas son significativamente más cortas que el histórico, pero no vs ayer. Indica que la degradación viene de días anteriores.

### Ejemplo Práctico - TOO_LONG (Escenario Hipotético)

**Datos de entrada (escenario diferente):**

| Período | avg_duration_seconds |
|---------|----------------------|
| Hoy | 145.8s |
| Ayer | 142.3s |
| Hace 7 días | 78.5s |
| Promedio 30d | 82.3s |

**Cálculos:**

```
Z-Score DoD = (145.8 - 142.3) / 12.5 = +0.28  → FINE
Z-Score WoW = (145.8 - 78.5) / 9.8 = +6.87  → CRITICAL (TOO_LONG)
Z-Score 30d = (145.8 - 82.3) / 9.8 = +6.48  → CRITICAL (TOO_LONG)
```

**Interpretación:** Las llamadas duran casi el doble de lo normal. Posible causa: bot atrapado en loops, usuarios confundidos sin poder finalizar, o problema de lógica de terminación.

### Atributos de Salida Específicos

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `current_completed_calls` | INTEGER | Llamadas completadas hoy |
| `current_avg_duration` | FLOAT | Duración promedio actual en segundos |
| `baseline_dod_duration` | FLOAT | Duración promedio de ayer |
| `baseline_dod_completed` | INTEGER | Completed calls de ayer |
| `baseline_wow_duration` | FLOAT | Duración promedio hace 7 días |
| `baseline_30d_duration` | FLOAT | Duración promedio histórica (mismo weekday, 30d) |
| `seconds_change_dod` | FLOAT | Cambio en segundos vs ayer |
| `seconds_change_wow` | FLOAT | Cambio en segundos vs semana pasada |
| `seconds_change_30d` | FLOAT | Cambio en segundos vs promedio 30d |
| `anomaly_type` | VARCHAR | `TOO_SHORT`, `TOO_LONG`, o `NORMAL` |

---

## 5.6 Resumen Comparativo de las 5 Alertas

| Alert | Métrica | Fórmula | Dirección | Z-Score Malo |
|-------|---------|---------|-----------|--------------|
| 1 - Volume Drop | `total_calls` | COUNT(*) | ↓ Lower is bad | < -2.0 |
| 2 - Completion Rate | `completion_rate` | completed / total | ↓ Lower is bad | < -2.0 |
| 3 - Quality Rate | `quality_rate` | good / completed | ↓ Lower is bad | < -2.0 |
| 4 - Short Call Spike | `short_call_rate` | short / completed | ↑ Higher is bad | > +2.0 |
| 5 - Duration Anomaly | `avg_duration` | AVG(seconds) | ↕ Bidireccional | \|z\| > 2.0 |

---

*Continúa en Sección 6: Diccionario de Atributos Global*

---

# 6. DICCIONARIO DE ATRIBUTOS GLOBAL

Esta sección consolida todos los atributos usados en las queries del sistema de alertas, organizados por categoría.

---

## 6.1 Identificadores

| Atributo | Tipo | Descripción | Usado en |
|----------|------|-------------|----------|
| `organization_code` | VARCHAR | Código único de la organización | Todas las queries |
| `organization_name` | VARCHAR | Nombre legible de la organización | Todas las queries |
| `country` | VARCHAR(2) | Código ISO del país (PE, CO, MX, etc.) | Todas las queries |
| `created_date` | DATE | Fecha de la llamada | Charts, Hourly Summary |
| `created_hour` | TIMESTAMP | Hora truncada de la llamada | Hourly Summary |
| `eval_date` | DATE | Fecha de evaluación (alias de created_date) | Hourly Summary |
| `eval_hour` | TIMESTAMP | Hora de evaluación (alias de created_hour) | Hourly Summary |
| `hour_of_day` | INTEGER | Hora del día (0-23) | Charts, Hourly Summary |
| `day_of_week` | INTEGER | Día de la semana (1=Dom, 7=Sáb) | Hourly Summary |

---

## 6.2 Métricas de Conteo

| Atributo | Tipo | Descripción | Fórmula |
|----------|------|-------------|---------|
| `total_calls` | INTEGER | Total de llamadas realizadas | `COUNT(*)` |
| `completed_calls` | INTEGER | Llamadas que conectaron | `COUNT(*) WHERE call_classification IN ('good_calls', 'short_calls', 'completed')` |
| `good_calls` | INTEGER | Llamadas con conversación efectiva | `COUNT(*) WHERE call_classification = 'good_calls'` |
| `short_calls` | INTEGER | Llamadas con conversación muy breve | `COUNT(*) WHERE call_classification = 'short_calls'` |
| `failed_calls` | INTEGER | Llamadas que no conectaron | `COUNT(*) WHERE call_classification = 'failed'` |

---

## 6.3 Métricas de Tasa (Rate)

| Atributo | Tipo | Rango | Descripción | Fórmula |
|----------|------|-------|-------------|---------|
| `completion_rate` | FLOAT | 0-1 | Tasa de llamadas completadas | `completed_calls / total_calls` |
| `quality_rate` | FLOAT | 0-1 | Tasa de llamadas efectivas | `good_calls / completed_calls` |
| `short_call_rate` | FLOAT | 0-1 | Tasa de llamadas cortas | `short_calls / completed_calls` |
| `avg_call_duration_seconds` | FLOAT | 0-∞ | Duración promedio en segundos | `AVG(call_duration_seconds)` |

**Nota:** Todas las tasas se expresan en formato decimal (0.85 = 85%). Para mostrar como porcentaje, multiplicar por 100.

---

## 6.4 Atributos de Baseline

### Prefijos de Baseline

| Prefijo | Significado | Período de Comparación |
|---------|-------------|------------------------|
| `baseline_dod_*` | Day over Day | Ayer al mismo momento |
| `baseline_wow_*` | Week over Week | Hace 7 días al mismo momento |
| `baseline_30d_*` | 30-Day Average | Promedio últimos 30 días (mismo weekday) |

### Atributos de Baseline por Alerta

| Atributo | Tipo | Alerta | Descripción |
|----------|------|--------|-------------|
| `baseline_dod_total_calls` | INTEGER | Alert 1 | Total calls de ayer |
| `baseline_wow_total_calls` | INTEGER | Alert 1 | Total calls hace 7 días |
| `baseline_30d_avg_total_calls` | FLOAT | Alert 1 | Promedio de total calls |
| `baseline_dod_rate` | FLOAT | Alert 2,3,4 | Tasa del día anterior |
| `baseline_wow_rate` | FLOAT | Alert 2,3,4 | Tasa de hace 7 días |
| `baseline_30d_rate` | FLOAT | Alert 2,3,4 | Tasa promedio 30d |
| `baseline_dod_duration` | FLOAT | Alert 5 | Duración promedio de ayer |
| `baseline_wow_duration` | FLOAT | Alert 5 | Duración promedio hace 7 días |
| `baseline_30d_duration` | FLOAT | Alert 5 | Duración promedio 30d |
| `baseline_dod_completed` | INTEGER | Alert 2-5 | Completed calls del baseline DoD |
| `baseline_wow_completed` | INTEGER | Alert 2-5 | Completed calls del baseline WoW |
| `baseline_dod_good` | INTEGER | Alert 3 | Good calls del baseline DoD |
| `baseline_wow_good` | INTEGER | Alert 3 | Good calls del baseline WoW |
| `baseline_dod_short` | INTEGER | Alert 4 | Short calls del baseline DoD |
| `baseline_wow_short` | INTEGER | Alert 4 | Short calls del baseline WoW |

---

## 6.5 Atributos de Cambio

### Cambio Absoluto

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `absolute_change_dod` | INTEGER/FLOAT | Diferencia: `current - baseline_dod` |
| `absolute_change_wow` | INTEGER/FLOAT | Diferencia: `current - baseline_wow` |
| `absolute_change_30d` | FLOAT | Diferencia: `current - baseline_30d` |

### Cambio Porcentual

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `pct_change_dod` | FLOAT | Cambio porcentual vs ayer: `(current - baseline) / baseline * 100` |
| `pct_change_wow` | FLOAT | Cambio porcentual vs semana pasada |
| `pct_change_30d` | FLOAT | Cambio porcentual vs promedio 30d |

### Cambio en Puntos Porcentuales

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `pp_change_dod` | FLOAT | Diferencia en puntos porcentuales vs ayer: `(current_rate - baseline_rate) * 100` |
| `pp_change_wow` | FLOAT | Diferencia en pp vs semana pasada |
| `pp_change_30d` | FLOAT | Diferencia en pp vs promedio 30d |

### Cambio en Segundos (Alert 5)

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `seconds_change_dod` | FLOAT | Diferencia en segundos vs ayer |
| `seconds_change_wow` | FLOAT | Diferencia en segundos vs semana pasada |
| `seconds_change_30d` | FLOAT | Diferencia en segundos vs promedio 30d |

---

## 6.6 Atributos Estadísticos

### Desviación Estándar (Stddev)

| Atributo | Tipo | Descripción | Cuándo se usa |
|----------|------|-------------|---------------|
| `stddev_all_days` | FLOAT | Stddev calculado sobre todos los días de los últimos 30d | Para z-score de DoD |
| `stddev_same_weekday` | FLOAT | Stddev calculado solo sobre el mismo día de semana | Para z-score de WoW y 30d |
| `stddev_value` | FLOAT | Alias genérico de stddev | Hourly Summary |

### Z-Score

| Atributo | Tipo | Rango típico | Descripción |
|----------|------|--------------|-------------|
| `z_score_dod` | FLOAT | -5 a +5 | Desviaciones estándar vs ayer |
| `z_score_wow` | FLOAT | -5 a +5 | Desviaciones estándar vs semana pasada |
| `z_score_30d` | FLOAT | -5 a +5 | Desviaciones estándar vs promedio 30d |

**Interpretación del Z-Score:**
- `z = 0`: Igual al baseline
- `z = -2`: 2 desviaciones estándar por debajo (peor para Alert 1-3)
- `z = +2`: 2 desviaciones estándar por arriba (peor para Alert 4)
- `|z| = 2`: 2 desviaciones en cualquier dirección (Alert 5)

### Tamaño de Muestra

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `sample_size` | INTEGER | Número de días/horas usados para calcular estadísticas |
| `sample_size_all_days` | INTEGER | Días con datos en los últimos 30d |
| `sample_size_weekday` | INTEGER | Días del mismo weekday con datos |

---

## 6.7 Atributos de Severidad

| Atributo | Tipo | Valores Posibles | Descripción |
|----------|------|------------------|-------------|
| `severity_dod` | VARCHAR | CRITICAL, WARNING, FINE, INSUFFICIENT_DATA | Severidad del sub-alert DoD |
| `severity_wow` | VARCHAR | CRITICAL, WARNING, FINE, INSUFFICIENT_DATA | Severidad del sub-alert WoW |
| `severity_30d` | VARCHAR | CRITICAL, WARNING, FINE, INSUFFICIENT_DATA | Severidad del sub-alert 30d |
| `main_severity` | VARCHAR | CRITICAL, WARNING, FINE | Severidad combinada (requiere consenso) |
| `alert_severity` | VARCHAR | CRITICAL, WARNING, FINE, INSUFFICIENT_DATA | Alias de severidad en algunas queries |

### Lógica de main_severity

```
IF severity_dod = 'CRITICAL' AND severity_wow = 'CRITICAL' AND severity_30d = 'CRITICAL':
    main_severity = 'CRITICAL'
ELIF severity_dod IN ('CRITICAL', 'WARNING') 
     AND severity_wow IN ('CRITICAL', 'WARNING') 
     AND severity_30d IN ('CRITICAL', 'WARNING'):
    main_severity = 'WARNING'
ELSE:
    main_severity = 'FINE'
```

---

## 6.8 Atributos de Mensaje

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `alert_message` | VARCHAR | Mensaje descriptivo de la alerta con detalles de métricas |
| `insufficient_reason` | VARCHAR | Razón específica de INSUFFICIENT_DATA |

### Valores de insufficient_reason

| Valor | Significado |
|-------|-------------|
| `NO_BASELINE` | No hay datos del período de comparación |
| `FEW_COMPLETED_TODAY` | Menos de 30 completed calls hoy |
| `FEW_COMPLETED_BASELINE` | Menos de 30 completed calls en baseline |
| `NO_VARIANCE` | Stddev = 0, no se puede calcular z-score |
| `FEW_SAMPLES` | Pocos días en el historial |

---

## 6.9 Atributos de Visualización (Charts)

| Atributo | Tipo | Descripción |
|----------|------|-------------|
| `block_status` | VARCHAR | Estado del bloque temporal: CURRENT_HOUR, TODAY_COMPLETED, TODAY_PENDING, PAST_DAY |
| `block_label` | VARCHAR | Etiqueta corta para tooltips: "Lun 2025-12-22 - 14:00" |
| `day_label` | VARCHAR | Día formateado legible: "Lunes 22/12" |

---

## 6.10 Atributos Específicos de Alert 5

| Atributo | Tipo | Valores | Descripción |
|----------|------|---------|-------------|
| `anomaly_type` | VARCHAR | TOO_SHORT, TOO_LONG, NORMAL | Tipo de anomalía detectada |
| `current_avg_duration` | FLOAT | - | Duración promedio actual en segundos |

---

# 7. ANEXOS

## 7.1 Glosario de Términos

| Término | Definición |
|---------|------------|
| **Apples-to-Apples** | Metodología de comparación que asegura que se comparan períodos equivalentes (misma hora:minuto del día) |
| **Baseline** | Valor de referencia contra el cual se compara el valor actual |
| **Completed Call** | Llamada que logró conectar con el destinatario, independientemente del resultado de la conversación |
| **DoD (Day over Day)** | Comparación del día actual vs el día anterior |
| **Failed Call** | Llamada que no logró conectar (número inválido, sin respuesta, buzón de voz) |
| **Good Call** | Llamada completada con una conversación efectiva (>1000 caracteres de transcripción) |
| **Main Alert** | Alerta principal que solo se dispara cuando los 3 sub-alerts coinciden |
| **Short Call** | Llamada completada pero con conversación muy breve (<1000 caracteres) |
| **Stddev (Standard Deviation)** | Desviación estándar, medida de dispersión de los datos |
| **Sub-Alert** | Componente individual de una alerta que compara contra un baseline específico |
| **WoW (Week over Week)** | Comparación del día actual vs el mismo día de la semana anterior |
| **Z-Score** | Número de desviaciones estándar que un valor está alejado de la media |
| **30d Avg** | Promedio de los últimos 30 días del mismo día de semana |

---

## 7.2 FAQ / Troubleshooting

### ¿Por qué no se dispara una alerta aunque veo métricas malas?

**Causa más común:** No hay consenso de los 3 sub-alerts.

Para que una alerta principal se dispare, los 3 sub-alerts (DoD, WoW, 30d) deben estar en WARNING o CRITICAL simultáneamente. Si uno de ellos está en FINE, la alerta no se dispara.

**Cómo verificar:**
1. Ir a Tab 3 → Current Summary de la alerta correspondiente
2. Revisar las columnas `severity_dod`, `severity_wow`, `severity_30d`
3. Confirmar si las 3 están en WARNING/CRITICAL

### ¿Por qué aparece INSUFFICIENT_DATA?

**Causas posibles:**
- Muy pocas llamadas hoy (< 30 completed calls)
- No hay datos del período de comparación (baseline NULL)
- Historial insuficiente (< 10 días para DoD, < 3 para WoW)
- Sin varianza histórica (todos los días idénticos)

**Cómo verificar:**
1. Revisar la columna `insufficient_reason` en Current Summary
2. Verificar los conteos en `current_completed_calls` y `baseline_*_completed`

### ¿Por qué el z-score es NULL?

**Causas:**
- `stddev = 0` (sin varianza histórica)
- `stddev = NULL` (historia insuficiente para calcular)
- `baseline = NULL` (sin datos de comparación)

### ¿Cómo interpreto un z-score de -2.5?

Un z-score de -2.5 significa que el valor actual está 2.5 desviaciones estándar **por debajo** del baseline. En una distribución normal:
- ~99% de los valores históricos estaban por encima de este nivel
- Es un evento muy inusual (probabilidad ~0.6%)

Para Alert 4 (Short Call Spike), un z-score **positivo** de +2.5 sería igualmente preocupante.

### ¿Por qué los umbrales son -2.0 y -2.5?

Basado en propiedades de la distribución normal:
- **z = ±2.0:** ~95% de valores caen dentro de este rango → 5% de falsos positivos esperados
- **z = ±2.5:** ~99% de valores caen dentro de este rango → 1% de falsos positivos esperados

Estos umbrales balancean sensibilidad (detectar problemas reales) con especificidad (evitar falsas alarmas).

### ¿Qué hago si una organización siempre aparece en INSUFFICIENT_DATA?

**Opciones:**
1. **Esperar:** Si es una organización nueva, necesita acumular historial
2. **Reducir umbrales:** Si tiene bajo volumen permanente, considerar umbrales personalizados
3. **Agrupar:** Combinar con otras organizaciones similares para aumentar muestra

---

## 7.3 Changelog

| Versión | Fecha | Cambios |
|---------|-------|---------|
| 2.0 | Diciembre 2025 | Documentación técnica completa. Incluye las 5 alertas, 15 sub-alerts, charts, y métricas. |
| 1.0 | - | Versión inicial del sistema de alertas |

---

## 7.4 Estructura de Archivos del Repositorio

```
dashboards/alerts/
│
├── ALERTS_DOCUMENTATION.md          # Documentación original (referencia)
├── ALERTS_EXECUTIVE_SUMMARY.md      # Resumen ejecutivo (no técnico)
├── ALERTS_TECHNICAL_DOCUMENTATION.md # Esta documentación
│
└── queries/
    │
    ├── charts/                       # Tab 1: Visualización
    │   ├── total_calls.sql
    │   ├── total_calls_all_orgs.sql
    │   └── completed_calls.sql
    │
    ├── alerts/                       # Tab 2: Alertas
    │   ├── alert_1_volume_drop.sql
    │   ├── alert_2_completion_rate_drop.sql
    │   ├── alert_3_quality_rate_drop.sql
    │   ├── alert_4_short_call_rate_spike.sql
    │   ├── alert_5_call_duration_anomaly.sql
    │   │
    │   └── sub_alerts/
    │       ├── sub_alert_11_dod.sql
    │       ├── sub_alert_12_wow.sql
    │       ├── sub_alert_13_30davg.sql
    │       ├── sub_alert_21_dod.sql
    │       ├── sub_alert_22_wow.sql
    │       ├── sub_alert_23_30davg.sql
    │       ├── sub_alert_31_dod.sql
    │       ├── sub_alert_32_wow.sql
    │       ├── sub_alert_33_30davg.sql
    │       ├── sub_alert_41_dod.sql
    │       ├── sub_alert_42_wow.sql
    │       ├── sub_alert_43_30davg.sql
    │       ├── sub_alert_51_dod.sql
    │       ├── sub_alert_52_wow.sql
    │       └── sub_alert_53_30davg.sql
    │
    └── metrics/                      # Tab 3: Métricas
        ├── current_summary/
        │   ├── current_summary_alert_1.sql
        │   ├── current_summary_alert_2.sql
        │   ├── current_summary_alert_3.sql
        │   ├── current_summary_alert_4.sql
        │   └── current_summary_alert_5.sql
        │
        └── hourly_summary/
            ├── hourly_summary_alert_1.sql
            ├── hourly_summary_alert_2.sql
            ├── hourly_summary_alert_3.sql
            ├── hourly_summary_alert_4.sql
            └── hourly_summary_alert_5.sql
```

---

*Fin de la documentación*
# 📊 Documentación de Alertas - AI Calls Dashboard

## 🎯 Quick Reference: Alert Severity Levels

| Alert | Métrica | 🟢 FINE | 🟡 WARNING | 🔴 CRITICAL | ⚪ INSUFFICIENT_DATA |
|-------|---------|---------|------------|-------------|---------------------|
| **Alert 1**<br>Hourly Quality | `T_v_LW_ratio`<br>(Today vs Last Week) | `≥ 0.90`<br>(≥90%) | `0.70 - 0.89`<br>(70-89%) | `< 0.70`<br>(<70%) | `< 20 calls` en T o LW |
| **Alert 2**<br>Daily Quality | `T_v_Y_ratio` **AND**<br>`T_v_30D_ratio` | Una baseline `≥ 0.90` | AMBAS `0.70 - 0.89` | AMBAS `< 0.70` | `< 50 calls` T/Y<br>O `< 20 días` 30D |
| **Alert 3**<br>Daily Volume | `T_v_LW_ratio` **AND**<br>`T_v_30D_ratio` | Una baseline `≥ 0.90` | AMBAS `0.70 - 0.89` | AMBAS `< 0.70` | `< 3 weekdays`<br>O LW `< 50 calls` |
| **Alert 4**<br>Short Call Spike | `sigma_deviation`<br>(T vs μ±σ) | `≤ +2σ` | `> +2σ`<br>(con ≥5 short calls) | `> +3σ`<br>O P95*1.2 | `< 10 calls` T<br>O `< 10 hrs` baseline |
| **Alert 5**<br>Call Duration | `\|sigma_deviation\|`<br>(bidireccional) | `≤ ±2σ` | `> ±2σ` | `> ±3σ` | `< 10 calls` T<br>O `< 10 hrs` baseline |

**Leyenda:**
- **T:** Today (hoy/hora actual)
- **Y:** Yesterday (ayer)
- **LW:** Last Week (semana pasada)
- **30D:** 30-Day Average (promedio 30 días)
- **μ:** Media/promedio
- **σ:** Desviación estándar
- **AND:** Ambas condiciones deben cumplirse simultáneamente

---

## Índice
1. [Alert 1: Hourly Quality Degradation](#alert-1-hourly-quality-degradation)
2. [Alert 2: Daily Quality Degradation](#alert-2-daily-quality-degradation)
3. [Alert 3: Daily Volume Drop](#alert-3-daily-volume-drop)
4. [Alert 4: Short Call Rate Spike](#alert-4-short-call-rate-spike)
5. [Alert 5: Call Duration Anomaly](#alert-5-call-duration-anomaly)
6. [Resumen Comparativo](#-resumen-comparativo-de-las-5-alertas)
7. [Términos Clave](#-términos-clave)
8. [Uso de las Alertas](#-uso-de-las-alertas)

---

## Alert 1: Hourly Quality Degradation

### 📋 Descripción General
Detecta degradación en la calidad de las llamadas comparando la hora actual con la misma hora de la semana pasada. Esta alerta identifica caídas significativas en el ratio de "good calls" vs "completed calls" en ventanas horarias.

**Tipo de comparación:** Week-over-Week (WoW) - Hora actual vs misma hora hace 7 días

**Granularidad:** Horaria

**Horario de operación:** 6:00 AM - 11:00 PM (solo genera alertas en este rango)

---

### 📊 Variables de Salida

| Variable | Tipo | Descripción |
|----------|------|-------------|
| `datetime` | TIMESTAMP | Marca de tiempo del momento en que se genera la alerta |
| `T_rate` | FLOAT | **Today Rate** - Ratio de calidad de la hora actual. Calculado como: `good_calls / completed_calls`. Valores entre 0 y 1 (ejemplo: 0.85 = 85% de calidad) |
| `LW_rate` | FLOAT | **Last Week Rate** - Ratio de calidad de la misma hora hace una semana. Baseline de comparación |
| `T_v_LW_ratio` | FLOAT | **Today vs Last Week Ratio** - Ratio de comparación entre hoy y semana pasada. Calculado como: `T_rate / LW_rate`. Valores < 1.0 indican degradación (ejemplo: 0.85 = caída del 15%) |
| `alert_message` | VARCHAR | Mensaje descriptivo de la alerta con detalles de la degradación, métricas actuales y baseline |

---

### 🚨 Alert Severity Levels

| Severity | Condición | Umbral | Descripción |
|----------|-----------|--------|-------------|
| **🔴 CRITICAL** | `T_v_LW_ratio < 0.70` | Caída > 30% | Calidad actual <70% del baseline de semana pasada. Degradación severa, acción inmediata. |
| **🟡 WARNING** | `T_v_LW_ratio < 0.90` | Caída 10-30% | Calidad actual 70-90% del baseline. Degradación moderada, requiere monitoreo. |
| **🟢 FINE** | `T_v_LW_ratio >= 0.90` | Caída < 10% | Calidad actual ≥90% del baseline. Operación normal. |
| **⚪ INSUFFICIENT_DATA** | `T_calls < 20` OR `LW_calls < 20` | Muestra insuficiente | Datos insuficientes para determinar confiablemente (mínimo 20 completed calls por periodo). |

**Lógica de evaluación:**
1. Primero verifica si hay suficientes datos (≥20 completed calls en ambos periodos)
2. Si hay datos suficientes, calcula `T_v_LW_ratio`
3. Aplica umbrales en orden: CRITICAL (< 0.70) → WARNING (< 0.90) → FINE

**Ejemplo de umbrales:**
- Si `LW_rate = 0.90` (90%):
  - CRITICAL: `T_rate < 0.63` (63%)
  - WARNING: `T_rate < 0.81` (81%)
  - FINE: `T_rate >= 0.81` (81%+)

---

### ⚙️ Cómo Funciona Internamente

#### Paso 1: Extracción de Métricas de la Hora Actual
```sql
-- Obtiene estadísticas de la hora actual (CURRENT_TIMESTAMP truncada a hora)
SELECT
  organization_code,
  organization_name,
  country,
  COUNT(*) AS total_calls,
  SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END) AS completed_calls,
  SUM(CASE WHEN call_classification = 'good_calls' THEN 1 ELSE 0 END) AS good_calls,
  ROUND(good_calls::float / NULLIF(completed_calls, 0), 4) AS quality_rate
FROM ai_calls_detail
WHERE created_hour = date_trunc('hour', CURRENT_TIMESTAMP())
```

#### Paso 2: Extracción de Métricas de la Semana Pasada (Baseline)
```sql
-- Obtiene estadísticas de la misma hora hace exactamente 7 días
WHERE created_hour = date_trunc('hour', CURRENT_TIMESTAMP() - INTERVAL 1 WEEK)
```

#### Paso 3: Comparación y Determinación de Severidad
```sql
CASE
  -- Insufficient data: Menos de 20 completed calls en hora actual O baseline
  WHEN completed_calls < 20 OR baseline_completed_calls < 20 
    THEN 'INSUFFICIENT_DATA'
  
  -- CRITICAL: Caída > 30% (quality < 70% del baseline)
  WHEN T_rate / LW_rate < 0.70
    THEN 'CRITICAL'
  
  -- WARNING: Caída 10-30% (quality 70-90% del baseline)
  WHEN T_rate / LW_rate < 0.90
    THEN 'WARNING'
  
  ELSE 'FINE'
END
```

#### Paso 4: Filtrado de Alertas
Solo se muestran alertas que cumplan:
- `alert_severity IN ('CRITICAL', 'WARNING')`
- `current_hour BETWEEN 6 AND 23` (horario operacional)
- `current_completed_calls >= 20` (muestra suficiente)
- `lastweek_completed_calls >= 20` (baseline confiable)

---

### 📝 Ejemplo Práctico

**Escenario:** Hoy es Lunes 22 de Diciembre de 2025 a las 5:00 PM

**Datos de entrada:**
- **Hora actual (Lunes 5:00 PM):**
  - Total calls: 181
  - Completed calls: 150
  - Good calls: 120
  - Quality rate: 120/150 = **0.80 (80%)**

- **Semana pasada (Lunes 15 Dic 5:00 PM):**
  - Total calls: 204
  - Completed calls: 170
  - Good calls: 160
  - Quality rate: 160/170 = **0.94 (94%)**

**Cálculos:**
```
T_rate = 0.80
LW_rate = 0.94
T_v_LW_ratio = 0.80 / 0.94 = 0.851 (85.1%)
Caída = (1 - 0.851) * 100 = 14.9%
```

**Resultado:**
- **Severidad:** `WARNING` (caída del 14.9%, entre 10% y 30%)
- **Salida:**

| datetime | T_rate | LW_rate | T_v_LW_ratio | alert_message |
|----------|--------|---------|--------------|---------------|
| 2025-12-22 17:00:00 | 0.80 | 0.94 | 0.851 | WARNING: Rappi (PE) - Good call quality dropped by 14.9% vs last week same hour. Current: 120/150 (80.0%) |

---

## Alert 2: Daily Quality Degradation

### 📋 Descripción General
Detecta degradación en la calidad de las llamadas usando **DOBLE BASELINE**: compara el día actual (hasta la hora actual) contra ayer Y contra el promedio de los últimos 30 días. Esta alerta usa una validación más estricta para reducir falsos positivos, requiriendo que la degradación se presente en **AMBAS comparaciones**.

**Tipo de comparación:** Dual Baseline
- **Baseline 1:** Day-over-Day (DoD) - Hoy vs Ayer (hasta misma hora)
- **Baseline 2:** 30-Day Average - Hoy vs Promedio de TODOS los últimos 30 días (hasta misma hora)

**Granularidad:** Diaria (acumulada hasta hora actual)

---

### 📊 Variables de Salida

| Variable | Tipo | Descripción |
|----------|------|-------------|
| `datetime` | TIMESTAMP | Marca de tiempo del momento en que se genera la alerta |
| `T_rate` | FLOAT | **Today Rate** - Ratio de calidad de hoy (hasta hora actual). Calculado como: `good_calls / completed_calls` |
| `Y_rate` | FLOAT | **Yesterday Rate** - Ratio de calidad de ayer (hasta misma hora que hoy). Primera baseline de comparación |
| `30D_AVG_rate` | FLOAT | **30-Day Average Rate** - Promedio de quality_rate de TODOS los últimos 30 días (cada día hasta misma hora). Segunda baseline de comparación |
| `T_v_Y_ratio` | FLOAT | **Today vs Yesterday Ratio** - Ratio de comparación con ayer. Calculado como: `T_rate / Y_rate` |
| `T_v_30D_ratio` | FLOAT | **Today vs 30-Day Average Ratio** - Ratio de comparación con promedio 30 días. Calculado como: `T_rate / 30D_AVG_rate` |
| `alert_message` | VARCHAR | Mensaje descriptivo mencionando AMBAS baselines y porcentajes de degradación |

---

### 🚨 Alert Severity Levels (DUAL BASELINE)

| Severity | Condición | Umbrales | Descripción |
|----------|-----------|----------|-------------|
| **🔴 CRITICAL** | `(T_v_Y_ratio < 0.70)` **AND** `(T_v_30D_ratio < 0.70)` | Caída > 30% en AMBAS | Calidad hoy <70% de ayer Y <70% del promedio 30d. Degradación severa confirmada. |
| **🟡 WARNING** | `(T_v_Y_ratio < 0.90)` **AND** `(T_v_30D_ratio < 0.90)` | Caída 10-30% en AMBAS | Calidad hoy 70-90% de ambas baselines. Degradación moderada confirmada. |
| **🟢 FINE** | Otro caso con datos suficientes | Caída < 10% en ≥1 baseline | Calidad aceptable en al menos una baseline. Operación normal o no confirmada. |
| **⚪ INSUFFICIENT_DATA** | `T_calls < 50` OR `Y_calls < 50` OR `30D_days < 20` | Muestra insuficiente | Datos insuficientes: mínimo 50 calls hoy/ayer, y 20 días en histórico 30d. |

**⚠️ IMPORTANTE - Lógica AND:**
Esta alerta usa **AMBOS criterios simultáneamente** (operador AND). Solo se dispara si la degradación es evidente en las DOS comparaciones:
- ❌ Si solo cae vs ayer pero NO vs 30D_AVG → `FINE` (volatilidad normal)
- ❌ Si solo cae vs 30D_AVG pero NO vs ayer → `FINE` (posible recuperación)
- ✅ Si cae vs ayer Y también vs 30D_AVG → `WARNING` o `CRITICAL` (degradación real)

**Lógica de evaluación:**
1. Verifica datos suficientes (≥50 calls hoy/ayer, ≥20 días histórico)
2. Calcula AMBOS ratios: `T_v_Y_ratio` y `T_v_30D_ratio`
3. Aplica umbrales con AND lógico:
   - CRITICAL: `(T_v_Y < 0.70) AND (T_v_30D < 0.70)`
   - WARNING: `(T_v_Y < 0.90) AND (T_v_30D < 0.90)`

**Ejemplo de umbrales:**
- Si `Y_rate = 0.90` y `30D_AVG_rate = 0.88`:
  - CRITICAL: `T_rate < 0.63` (63%) para ayer AND `T_rate < 0.62` (62%) para 30D
  - WARNING: `T_rate < 0.81` (81%) para ayer AND `T_rate < 0.79` (79%) para 30D
  - Debe cumplir AMBOS simultáneamente

---

### ⚙️ Cómo Funciona Internamente

#### Paso 1: Extracción de Métricas de Hoy (Hasta Hora Actual)
```sql
SELECT
  organization_code,
  organization_name,
  country,
  SUM(CASE WHEN call_classification = 'good_calls' THEN 1 ELSE 0 END) AS good_calls,
  SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END) AS completed_calls,
  ROUND(good_calls::float / NULLIF(completed_calls, 0), 4) AS quality_rate
FROM ai_calls_detail
WHERE 
  created_date = CURRENT_DATE()
  AND created_at < CURRENT_TIMESTAMP()  -- Solo hasta la hora actual
```

#### Paso 2: Extracción de Métricas de Ayer (Baseline 1)
```sql
-- Mismo periodo que hoy pero de ayer
WHERE 
  created_date = CURRENT_DATE() - INTERVAL 1 DAY
  AND created_at < CURRENT_TIMESTAMP() - INTERVAL 1 DAY  -- Hasta misma hora
```

#### Paso 3: Cálculo de Promedio 30 Días (Baseline 2)
```sql
-- Para cada uno de los últimos 30 días, calcula quality_rate hasta misma hora
-- Luego promedia todos esos quality_rates
SELECT
  organization_code,
  AVG(daily_quality_rate) AS avg_quality_rate_30d,
  COUNT(DISTINCT created_date) AS days_with_data
FROM (
  SELECT
    created_date,
    ROUND(good_calls::float / NULLIF(completed_calls, 0), 4) AS daily_quality_rate
  FROM ai_calls_detail
  WHERE 
    created_date >= CURRENT_DATE() - INTERVAL 30 DAY
    AND created_date < CURRENT_DATE()
    -- Solo hasta la misma hora del día (comparación apples-to-apples)
    AND (
      EXTRACT(HOUR FROM created_at) < EXTRACT(HOUR FROM CURRENT_TIMESTAMP())
      OR (
        EXTRACT(HOUR FROM created_at) = EXTRACT(HOUR FROM CURRENT_TIMESTAMP())
        AND EXTRACT(MINUTE FROM created_at) <= EXTRACT(MINUTE FROM CURRENT_TIMESTAMP())
      )
    )
  GROUP BY created_date
  HAVING completed_calls >= 10  -- Mínimo 10 completed calls por día
)
```

#### Paso 4: Determinación de Severidad (Requiere AMBOS Criterios)
```sql
CASE
  -- Insufficient data
  WHEN today_completed_calls < 50 
    OR yesterday_completed_calls < 50
    OR baseline_days_count < 20  -- Mínimo 20 días con data
    THEN 'INSUFFICIENT_DATA'
  
  -- CRITICAL: Caída > 30% vs AMBAS baselines (operador AND)
  WHEN (T_rate / Y_rate < 0.70) AND (T_rate / 30D_AVG_rate < 0.70)
    THEN 'CRITICAL'
  
  -- WARNING: Caída 10-30% vs AMBAS baselines (operador AND)
  WHEN (T_rate / Y_rate < 0.90) AND (T_rate / 30D_AVG_rate < 0.90)
    THEN 'WARNING'
  
  ELSE 'FINE'
END
```

**IMPORTANTE:** La alerta solo se dispara si la degradación es evidente en **AMBAS comparaciones** (AND lógico), no solo en una. Esto reduce significativamente los falsos positivos.

#### Paso 5: Filtrado de Alertas
Solo se muestran alertas que cumplan:
- `alert_severity IN ('CRITICAL', 'WARNING')`
- `today_completed_calls >= 50`
- `yesterday_completed_calls >= 50`
- `baseline_days_count >= 20` (suficiente historia)

---

### 📝 Ejemplo Práctico

**Escenario:** Hoy es Martes 22 de Diciembre de 2025 a las 3:00 PM

**Datos de entrada:**
- **Hoy (Martes hasta 3:00 PM):**
  - Total calls: 450
  - Completed calls: 380
  - Good calls: 300
  - Quality rate: 300/380 = **0.789 (78.9%)**

- **Ayer (Lunes hasta 3:00 PM):**
  - Completed calls: 400
  - Good calls: 360
  - Quality rate: 360/400 = **0.90 (90%)**

- **Promedio 30 días (cada día hasta 3:00 PM):**
  - Días con data: 28 días
  - Promedio quality rate: **0.88 (88%)**

**Cálculos:**
```
T_rate = 0.789
Y_rate = 0.90
30D_AVG_rate = 0.88

T_v_Y_ratio = 0.789 / 0.90 = 0.877 (87.7%)
Caída vs ayer = (1 - 0.877) * 100 = 12.3%

T_v_30D_ratio = 0.789 / 0.88 = 0.897 (89.7%)
Caída vs 30d = (1 - 0.897) * 100 = 10.3%
```

**Evaluación:**
- `T_v_Y_ratio = 0.877 < 0.90` ✅ (Caída > 10% vs ayer)
- `T_v_30D_ratio = 0.897 < 0.90` ✅ (Caída > 10% vs 30d avg)
- **Ambas condiciones cumplen** → `WARNING`

**Resultado:**

| datetime | T_rate | Y_rate | 30D_AVG_rate | T_v_Y_ratio | T_v_30D_ratio | alert_message |
|----------|--------|--------|--------------|-------------|---------------|---------------|
| 2025-12-22 15:00:00 | 0.789 | 0.90 | 0.88 | 0.877 | 0.897 | WARNING: Rappi (PE) - Quality dropped by 12.3% vs yesterday AND 10.3% below 30-day avg. Today: 78.9% vs Yesterday: 90.0% |

**Interpretación:** La calidad ha caído tanto respecto a ayer como respecto al promedio histórico, lo que indica una degradación real y no una volatilidad puntual.

---

## Alert 3: Daily Volume Drop

### 📋 Descripción General
Detecta caídas significativas en el volumen de llamadas usando **DOBLE BASELINE**: compara el día actual (hasta la hora actual) contra el mismo día de la semana pasada Y contra el promedio del mismo día de semana de los últimos 30 días. Esta alerta requiere que la caída se presente en **AMBAS comparaciones** para reducir falsos positivos por variabilidad semanal natural.

**Tipo de comparación:** Dual Baseline
- **Baseline 1:** Week-over-Week (WoW) - Hoy vs Mismo día semana pasada (hasta misma hora)
- **Baseline 2:** Same-Weekday 30-Day Average - Hoy vs Promedio del mismo día de semana últimos 30 días (hasta misma hora)

**Granularidad:** Diaria (acumulada hasta hora actual)

**Horario de alerta:** Solo se alerta después de las 1:00 PM (para tener suficiente data)

---

### 📊 Variables de Salida

| Variable | Tipo | Descripción |
|----------|------|-------------|
| `datetime` | TIMESTAMP | Marca de tiempo del momento en que se genera la alerta |
| `T_Calls` | INTEGER | **Today Calls** - Número total de llamadas hoy (hasta hora actual) |
| `LW_Calls` | INTEGER | **Last Week Calls** - Número de llamadas del mismo día/hora hace una semana. Primera baseline de comparación |
| `30D_AVG_Calls` | FLOAT | **30-Day Average Calls** - Promedio de llamadas del mismo día de semana en los últimos 30 días (hasta misma hora). Segunda baseline de comparación. Ejemplo: Si hoy es Lunes, promedia solo los Lunes |
| `T_v_LW_ratio` | FLOAT | **Today vs Last Week Ratio** - Ratio de comparación con semana pasada. Calculado como: `T_Calls / LW_Calls` |
| `T_v_30D_ratio` | FLOAT | **Today vs 30-Day Average Ratio** - Ratio de comparación con promedio del mismo día de semana. Calculado como: `T_Calls / 30D_AVG_Calls` |
| `alert_message` | VARCHAR | Mensaje descriptivo mencionando AMBAS baselines, porcentajes de caída y volúmenes absolutos |

---

### 🚨 Alert Severity Levels (DUAL BASELINE)

| Severity | Condición | Umbrales | Descripción |
|----------|-----------|----------|-------------|
| **🔴 CRITICAL** | `(T_v_LW_ratio < 0.70)` **AND** `(T_v_30D_ratio < 0.70)` | Caída > 30% en AMBAS | Volumen hoy <70% de semana pasada Y <70% del promedio mismo día de semana. Caída severa confirmada. |
| **🟡 WARNING** | `(T_v_LW_ratio < 0.90)` **AND** `(T_v_30D_ratio < 0.90)` | Caída 10-30% en AMBAS | Volumen hoy 70-90% de ambas baselines. Caída moderada confirmada. |
| **🟢 FINE** | Otro caso con datos suficientes | Caída < 10% en ≥1 baseline | Volumen aceptable en al menos una baseline. Operación normal o variabilidad natural. |
| **⚪ INSUFFICIENT_DATA** | `30D_weekday_count < 3` OR `30D_AVG < 30` OR `LW_calls < 50` | Muestra insuficiente | Datos insuficientes: mínimo 3 días del mismo día de semana en 30d, promedio ≥30 calls/día, y ≥50 calls LW. |

**⚠️ IMPORTANTE - Lógica AND con Mismo Día de Semana:**
Esta alerta usa **AMBOS criterios simultáneamente** (operador AND) y compara contra el **mismo día de la semana**:
- Baseline 1: Mismo día hace 7 días (ej: Lunes vs Lunes anterior)
- Baseline 2: Promedio de **solo** el mismo día de semana en 30 días (ej: promedio de los 4 Lunes)

**Ventaja de filtrar por día de semana:**
- Evita falsos positivos por patrones semanales (ej: Lunes tiene más volumen que Viernes)
- Compara "apples-to-apples" (Lunes vs Lunes, Viernes vs Viernes)

**Lógica de evaluación:**
1. Verifica datos suficientes (≥3 días del mismo día de semana, baseline promedio ≥30, LW ≥50)
2. Calcula AMBOS ratios: `T_v_LW_ratio` y `T_v_30D_ratio`
3. Aplica umbrales con AND lógico:
   - CRITICAL: `(T_v_LW < 0.70) AND (T_v_30D < 0.70)`
   - WARNING: `(T_v_LW < 0.90) AND (T_v_30D < 0.90)`
4. Solo alerta después de las **1:00 PM** (para tener suficiente data acumulada del día)

**Ejemplo de umbrales:**
- Si hoy es Lunes, `LW_Calls = 204` y `30D_AVG_Calls = 218` (promedio de 4 Lunes):
  - CRITICAL: `T_Calls < 143` (70% de 204) AND `T_Calls < 153` (70% de 218)
  - WARNING: `T_Calls < 184` (90% de 204) AND `T_Calls < 196` (90% de 218)
  - Debe cumplir AMBOS simultáneamente

---

### ⚙️ Cómo Funciona Internamente

#### Paso 1: Extracción de Volumen de Hoy (Hasta Hora Actual)
```sql
SELECT
  organization_code,
  organization_name,
  country,
  COUNT(*) AS total_calls,
  SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END) AS completed_calls
FROM ai_calls_detail
WHERE 
  created_date = CURRENT_DATE()
  AND created_at < CURRENT_TIMESTAMP()  -- Solo hasta la hora actual
```

#### Paso 2: Extracción de Volumen de Semana Pasada (Baseline 1)
```sql
-- Mismo día de la semana hace 7 días, hasta misma hora
WHERE 
  created_date = CURRENT_DATE() - INTERVAL 7 DAY
  AND created_at < CURRENT_TIMESTAMP() - INTERVAL 7 DAY
```

#### Paso 3: Cálculo de Promedio Mismo Día de Semana 30 Días (Baseline 2)
```sql
-- Filtra solo días del mismo día de semana (ej: si hoy es Lunes, solo Lunes)
-- Calcula promedio de llamadas acumuladas hasta misma hora
SELECT
  organization_code,
  AVG(daily_calls_until_now) AS avg_daily_calls_30d,
  COUNT(DISTINCT created_date) AS days_with_data  -- Cuántos Lunes hubo, por ejemplo
FROM (
  SELECT
    created_date,
    COUNT(*) AS daily_calls_until_now
  FROM ai_calls_detail
  WHERE 
    created_date >= CURRENT_DATE() - INTERVAL 30 DAY
    AND created_date < CURRENT_DATE()
    -- FILTRO CLAVE: Solo mismo día de semana
    AND DAYOFWEEK(created_date) = DAYOFWEEK(CURRENT_DATE())
    -- Solo hasta misma hora del día (comparación apples-to-apples)
    AND (
      EXTRACT(HOUR FROM created_at) < EXTRACT(HOUR FROM CURRENT_TIMESTAMP())
      OR (
        EXTRACT(HOUR FROM created_at) = EXTRACT(HOUR FROM CURRENT_TIMESTAMP())
        AND EXTRACT(MINUTE FROM created_at) <= EXTRACT(MINUTE FROM CURRENT_TIMESTAMP())
      )
    )
  GROUP BY created_date
)
```

**Ejemplo:** Si hoy es Lunes 22 de Diciembre a las 5:00 PM, el promedio 30D incluirá:
- Lunes 15 de Diciembre hasta 5:00 PM
- Lunes 8 de Diciembre hasta 5:00 PM
- Lunes 1 de Diciembre hasta 5:00 PM
- Lunes 24 de Noviembre hasta 5:00 PM
- (Aproximadamente 4-5 Lunes en ventana de 30 días)

#### Paso 4: Determinación de Severidad (Requiere AMBOS Criterios)
```sql
CASE
  -- Insufficient data
  WHEN baseline_days_count < 3  -- Mínimo 3 días del mismo día de semana
    OR baseline_avg_calls < 30
    OR lastweek_calls < 50
    THEN 'INSUFFICIENT_DATA'
  
  -- CRITICAL: Caída > 30% vs AMBAS baselines (operador AND)
  WHEN (T_Calls / LW_Calls < 0.70) AND (T_Calls / 30D_AVG_Calls < 0.70)
    THEN 'CRITICAL'
  
  -- WARNING: Caída 10-30% vs AMBAS baselines (operador AND)
  WHEN (T_Calls / LW_Calls < 0.90) AND (T_Calls / 30D_AVG_Calls < 0.90)
    THEN 'WARNING'
  
  ELSE 'FINE'
END
```

#### Paso 5: Filtrado de Alertas
Solo se muestran alertas que cumplan:
- `alert_severity IN ('CRITICAL', 'WARNING')`
- `current_hour >= 13` (después de 1:00 PM para tener datos suficientes)
- `baseline_days_count >= 3` (mínimo 3 días del mismo día de semana)
- `lastweek_calls >= 50` (baseline confiable)

---

### 📝 Ejemplo Práctico

**Escenario:** Hoy es Lunes 22 de Diciembre de 2025 a las 5:00 PM (como en la imagen)

**Datos de entrada:**
- **Hoy (Lunes 22 Dic hasta 5:00 PM):**
  - Total calls: **181**
  - Completed calls: 150

- **Semana pasada (Lunes 15 Dic hasta 5:00 PM):**
  - Total calls: **204**
  - Completed calls: 170

- **Promedio últimos 30 días (solo Lunes hasta 5:00 PM):**
  - Días con data: 4 Lunes
  - Promedio: **(200 + 210 + 215 + 220) / 4 = 218 calls**

**Cálculos:**
```
T_Calls = 181
LW_Calls = 204
30D_AVG_Calls = 218

T_v_LW_ratio = 181 / 204 = 0.887 (88.7%)
Caída vs semana pasada = (1 - 0.887) * 100 = 11.3%

T_v_30D_ratio = 181 / 218 = 0.830 (83.0%)
Caída vs 30d avg = (1 - 0.830) * 100 = 17.0%
```

**Evaluación:**
- `T_v_LW_ratio = 0.887 < 0.90` ✅ (Caída > 10% vs semana pasada)
- `T_v_30D_ratio = 0.830 < 0.90` ✅ (Caída > 10% vs 30d avg)
- **Ambas condiciones cumplen** → `WARNING`

**Resultado (como en la imagen):**

| datetime | T_Calls | LW_Calls | 30D_AVG_Calls | T_v_LW_ratio | T_v_30D_ratio | alert_message |
|----------|---------|----------|---------------|--------------|---------------|---------------|
| 2025-12-22 17:00:00 | 181 | 204 | 218 | 0.89 | 0.83 | WARNING: Rappi (PE) - Call volume dropped by 11.3% vs last week AND 17.1% below same-weekday avg (last 30d). Today: 181 calls vs Last Week: 204 calls (Same-Weekday Avg: 218) |

**Interpretación:** El volumen de hoy está bajo tanto comparado con la semana pasada como con el patrón histórico de Lunes, indicando una caída real y no variabilidad normal día-a-día.

---

## Alert 4: Short Call Rate Spike

### 📋 Descripción General
Detecta anomalías en el ratio de llamadas cortas (short calls) usando **detección estadística basada en desviación estándar**. Esta alerta identifica cuando el porcentaje de llamadas cortas está significativamente por encima del promedio histórico, lo que puede indicar problemas técnicos, mala calidad de conexión, o problemas en el flujo conversacional del bot.

**Tipo de comparación:** Detección de Anomalías Estadísticas (Baseline de 30 días con σ - desviación estándar)

**Granularidad:** Horaria (compara hora actual con distribución histórica de la misma hora)

**Método:** Usa estadísticas pre-calculadas de `alerts_baseline_stats` para eficiencia

**Horario de operación:** 6:00 AM - 11:00 PM

---

### 📊 Variables de Salida

| Variable | Tipo | Descripción |
|----------|------|-------------|
| `datetime` | TIMESTAMP | Marca de tiempo de la hora analizada |
| `T_rate` | FLOAT | **Today Rate** - Ratio actual de short calls. Calculado como: `short_calls / completed_calls`. Ejemplo: 0.15 = 15% de llamadas son cortas |
| `30D_AVG_rate` | FLOAT | **30-Day Average Rate** - Promedio histórico del short call rate para la misma hora del día en los últimos 30 días. Baseline de comparación |
| `sigma_deviation` | FLOAT | **Desviación en Sigmas (σ)** - Número de desviaciones estándar que la tasa actual está por encima del promedio. Calculado como: `(T_rate - 30D_AVG_rate) / stddev_30d`. Ejemplo: 2.5σ significa 2.5 desviaciones estándar por encima de lo normal |
| `alert_message` | VARCHAR | Mensaje descriptivo con el spike detectado, métricas actuales, baseline y nivel de desviación estadística |

---

### 🚨 Alert Severity Levels (DETECCIÓN ESTADÍSTICA)

| Severity | Condición | Umbral Estadístico | Descripción |
|----------|-----------|-------------------|-------------|
| **🔴 CRITICAL** | `T_rate > μ + 3σ` OR `(T_rate > P95 * 1.2 AND short_calls ≥ 10)` | > 3σ O > 20% del P95 | Spike extremo: tasa 3 sigma por encima del promedio (probabilidad <0.3%) O supera P95 por >20% con ≥10 short calls. |
| **🟡 WARNING** | `T_rate > μ + 2σ` AND `short_calls ≥ 5` | > 2σ | Spike significativo: tasa 2 sigma por encima del promedio (fuera del 95% esperado) con ≥5 short calls. |
| **🟢 FINE** | `T_rate ≤ μ + 2σ` | Dentro de 2σ | Tasa de short calls dentro del rango esperado (95% de valores históricos). Operación normal. |
| **⚪ INSUFFICIENT_DATA** | `T_calls < 10` OR `baseline_sample_size < 10` | Muestra insuficiente | Datos insuficientes: mínimo 10 completed calls en hora actual y 10 horas en baseline de 30 días. |

**📊 Conceptos Estadísticos:**
- **μ (mu):** Media/promedio del short call rate histórico
- **σ (sigma):** Desviación estándar del short call rate histórico
- **P95:** Percentil 95 (95% de valores históricos están por debajo)
- **Distribución Normal:**
  - ~68% de valores caen dentro de μ ± 1σ
  - ~95% de valores caen dentro de μ ± 2σ
  - ~99.7% de valores caen dentro de μ ± 3σ

**Lógica de evaluación:**
1. Verifica datos suficientes (≥10 completed calls, baseline ≥10 horas)
2. Calcula desviación: `sigma_deviation = (T_rate - μ) / σ`
3. Aplica umbrales estadísticos:
   - CRITICAL: `σ_deviation > 3` OR `(T_rate > P95 * 1.2 AND short_calls ≥ 10)`
   - WARNING: `σ_deviation > 2 AND short_calls ≥ 5`
4. Solo alerta en horario operacional (6 AM - 11 PM)

**Ejemplo numérico:**
- Baseline: `μ = 0.12 (12%)`, `σ = 0.04 (4%)`, `P95 = 0.18 (18%)`
- Umbrales calculados:
  - WARNING: `T_rate > 0.12 + 2*0.04 = 0.20` (20%) con ≥5 short calls
  - CRITICAL (opción 1): `T_rate > 0.12 + 3*0.04 = 0.24` (24%)
  - CRITICAL (opción 2): `T_rate > 0.18 * 1.2 = 0.216` (21.6%) con ≥10 short calls
- Si `T_rate = 0.22 (22%)` y `short_calls = 8`:
  - `σ_deviation = (0.22 - 0.12) / 0.04 = 2.5σ`
  - Resultado: **WARNING** (>2σ pero <3σ, con suficientes short calls)

---

### ⚙️ Cómo Funciona Internamente

#### Paso 1: Extracción de Métricas de la Hora Actual
```sql
SELECT
  organization_code,
  organization_name,
  country,
  created_hour,
  COUNT(*) AS total_calls,
  SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END) AS completed_calls,
  SUM(CASE WHEN call_classification = 'short_calls' THEN 1 ELSE 0 END) AS short_calls,
  ROUND(short_calls::float / NULLIF(completed_calls, 0), 4) AS short_call_rate
FROM ai_calls_detail
WHERE created_hour = date_trunc('hour', CURRENT_TIMESTAMP())
```

#### Paso 2: Obtención de Estadísticas Baseline (Pre-calculadas)

**¿Qué es `alerts_baseline_stats`?**

`alerts_baseline_stats` es una **Materialized View** (vista materializada) dbt que pre-calcula estadísticas históricas rolling de los últimos 7 y 30 días. Esta tabla optimiza las alertas 4 y 5 al evitar cálculos costosos en tiempo real.

**¿Por qué se usa?**

En lugar de calcular desviaciones estándar, percentiles y promedios cada vez que se ejecuta una alerta (lo cual sería muy lento), estas estadísticas se pre-calculan y se actualizan **cada 1 hora** automáticamente. Esto permite:
- ⚡ **Consultas ultra-rápidas:** Las alertas solo hacen un `JOIN` simple
- 📊 **Estadísticas complejas:** Cálculos de σ, percentiles (P25, P50, P75, P95)
- 🎯 **Granularidad por hora del día:** Compara hora actual con patrón histórico de la misma hora
- 🔄 **Actualización automática:** StarRocks refresca la vista cada hora

**¿Cómo se calcula?**

La vista materializada sigue este proceso:

1. **Agregación horaria (últimos 30 días):**
   ```sql
   -- Desde ai_calls_detail, agrupa por hora
   SELECT
     organization_code, country, hour_of_day, created_hour,
     COUNT(*) AS completed_calls,
     ROUND(short_calls / completed_calls, 4) AS short_call_rate,
     ROUND(AVG(call_duration_seconds), 2) AS avg_call_duration_seconds
   FROM ai_calls_detail
   WHERE created_date >= CURRENT_DATE() - INTERVAL 30 DAY
   GROUP BY organization_code, country, hour_of_day, created_hour
   HAVING completed_calls >= 10  -- Solo horas con volumen suficiente
   ```

2. **Cálculo de estadísticas por hora del día (30 días):**
   ```sql
   -- Para cada combinación de org, país, hora_del_día
   SELECT
     organization_code, country, hour_of_day,
     
     -- Alert 4: Short Call Rate
     AVG(short_call_rate) AS avg_short_call_rate_30d,           -- μ (media)
     STDDEV(short_call_rate) AS stddev_short_call_rate_30d,     -- σ (desv. estándar)
     percentile_approx(short_call_rate, 0.50) AS p50_...,       -- Mediana
     percentile_approx(short_call_rate, 0.95) AS p95_...,       -- Percentil 95
     
     -- Alert 5: Call Duration
     AVG(avg_call_duration_seconds) AS avg_call_duration_30d,   -- μ (media)
     STDDEV(avg_call_duration_seconds) AS stddev_..._30d,       -- σ (desv. estándar)
     percentile_approx(avg_call_duration_seconds, 0.05) AS p05, -- Percentil 5
     percentile_approx(avg_call_duration_seconds, 0.95) AS p95, -- Percentil 95
     
     COUNT(*) AS sample_size_30d                                 -- # horas con datos
   FROM recent_data
   GROUP BY organization_code, country, hour_of_day
   ```

3. **Pre-cálculo de umbrales:**
   ```sql
   -- Umbrales de alerta ya calculados
   avg_short_call_rate_30d + 2 * stddev_30d AS short_call_rate_upper_threshold,
   avg_call_duration_30d - 2 * stddev_30d AS call_duration_lower_threshold,
   avg_call_duration_30d + 2 * stddev_30d AS call_duration_upper_threshold
   ```

**Ejemplo de datos en `alerts_baseline_stats`:**

| organization_code | country | hour_of_day | avg_short_call_rate_30d | stddev_short_call_rate_30d | p95_short_call_rate_30d | sample_size_30d |
|-------------------|---------|-------------|-------------------------|----------------------------|-------------------------|-----------------|
| rappi_pe | PE | 16 | 0.1200 | 0.0400 | 0.1800 | 28 |
| rappi_pe | PE | 17 | 0.1150 | 0.0380 | 0.1750 | 29 |

**Join con métricas actuales:**

```sql
-- Las alertas hacen un JOIN simple y rápido
FROM current_hour_metrics curr
INNER JOIN alerts_baseline_stats base
  ON curr.organization_code = base.organization_code
  AND curr.country = base.country
  AND EXTRACT(HOUR FROM curr.created_hour) = base.hour_of_day  -- Misma hora del día

-- Estadísticas disponibles inmediatamente:
-- - avg_short_call_rate_30d: Promedio del short call rate (μ)
-- - stddev_short_call_rate_30d: Desviación estándar (σ)
-- - p50_short_call_rate_30d: Mediana (percentil 50)
-- - p95_short_call_rate_30d: Percentil 95
-- - sample_size_30d: Número de horas con datos en últimos 30 días
```

**Ventajas de este enfoque:**
- ✅ **Compara "apples-to-apples":** Lunes 4 PM vs promedio histórico de Lunes 4 PM
- ✅ **Considera patrones horarios:** Diferentes horas tienen diferentes comportamientos
- ✅ **Eficiente:** Pre-cálculo evita computación pesada en tiempo real
- ✅ **Confiable:** `sample_size_30d` indica cuántas horas históricas se usaron

#### Paso 3: Cálculo de Desviación Estadística
```sql
-- Calcula cuántas desviaciones estándar está el valor actual del promedio
sigma_deviation = (current_short_call_rate - avg_short_call_rate_30d) / stddev_short_call_rate_30d

-- Ejemplo:
-- Si avg = 0.10 (10%), stddev = 0.03, y current = 0.16 (16%)
-- sigma_deviation = (0.16 - 0.10) / 0.03 = 2.0σ
```

#### Paso 4: Determinación de Severidad
```sql
CASE
  -- Insufficient data
  WHEN completed_calls < 10 
    OR sample_size_30d < 10
    THEN 'INSUFFICIENT_DATA'
  
  -- CRITICAL: > 3 desviaciones estándar O > percentil 95 por gran margen
  WHEN current_rate > avg_30d + 3 * stddev_30d
    OR (current_rate > p95_30d * 1.2 AND short_calls >= 10)
    THEN 'CRITICAL'
  
  -- WARNING: > 2 desviaciones estándar
  WHEN current_rate > avg_30d + 2 * stddev_30d
    AND short_calls >= 5
    THEN 'WARNING'
  
  ELSE 'FINE'
END
```

**Nota sobre cambios de umbral:**
- Se redujo de `< 20` a `< 10` completed calls para INSUFFICIENT_DATA
- Se eliminó la verificación `has_sufficient_baseline_data = FALSE` 
- Esto hace la alerta menos restrictiva, permitiendo detección temprana con muestras más pequeñas

**Umbrales Estadísticos:**
- **WARNING:** `T_rate > μ + 2σ` (valor actual > promedio + 2 desviaciones estándar)
  - En distribución normal, ~95% de valores caen dentro de 2σ
- **CRITICAL:** `T_rate > μ + 3σ` (valor actual > promedio + 3 desviaciones estándar)
  - En distribución normal, ~99.7% de valores caen dentro de 3σ
  - Valores >3σ son extremadamente raros (0.3% probabilidad)

#### Paso 5: Filtrado de Alertas
Solo se muestran alertas que cumplan:
- `alert_severity IN ('CRITICAL', 'WARNING')`
- `current_hour BETWEEN 6 AND 23`
- `current_completed_calls >= 10`

---

### 📝 Ejemplo Práctico

**Escenario:** Hoy es Miércoles 22 de Diciembre de 2025 a las 4:00 PM

**Datos de entrada:**

**Hora actual (Miércoles 4:00 PM):**
- Total calls: 220
- Completed calls: 180
- Short calls: 40
- Short call rate: 40/180 = **0.222 (22.2%)**

**Baseline (últimos 30 días, horas de 4:00 PM):**
- Promedio (μ): **0.12 (12%)**
- Desviación estándar (σ): **0.04 (4%)**
- Mediana: 0.11
- Percentil 95: 0.18
- Sample size: 28 horas

**Cálculos:**
```
T_rate = 0.222 (22.2%)
30D_AVG_rate = 0.12 (12%)
stddev = 0.04

sigma_deviation = (0.222 - 0.12) / 0.04 = 2.55σ

Umbral WARNING: 0.12 + 2*0.04 = 0.20 (20%)
Umbral CRITICAL: 0.12 + 3*0.04 = 0.24 (24%)
```

**Evaluación:**
- `T_rate = 0.222 > 0.20 (umbral WARNING)` ✅
- `T_rate = 0.222 < 0.24 (umbral CRITICAL)` ✅
- `sigma_deviation = 2.55σ > 2σ` ✅
- **Resultado:** `WARNING`

**Resultado:**

| datetime | T_rate | 30D_AVG_rate | sigma_deviation | alert_message |
|----------|--------|--------------|-----------------|---------------|
| 2025-12-22 16:00:00 | 0.222 | 0.12 | 2.55 | WARNING: Rappi (PE) - Elevated short call rate. Current: 22.2% vs Baseline: 12.0% (+2.55σ) |

**Interpretación:** El porcentaje de llamadas cortas está 2.55 desviaciones estándar por encima del promedio histórico. Esto indica una anomalía estadísticamente significativa que merece investigación (posibles causas: problemas de red, cambios en el bot, problemas con proveedores de telefonía).

---

## Alert 5: Call Duration Anomaly

### 📋 Descripción General
Detecta anomalías en la duración promedio de las llamadas usando **detección estadística bidireccional**. Esta alerta identifica cuando la duración de las llamadas está significativamente fuera del rango normal, tanto si es **demasiado corta** como **demasiado larga**, lo que puede indicar diferentes tipos de problemas operacionales o técnicos.

**Tipo de comparación:** Detección de Anomalías Estadísticas Bidireccional (Baseline de 30 días con μ ± 2σ)

**Granularidad:** Horaria (tiempo real, compara hora actual con distribución histórica)

**Método:** Usa estadísticas pre-calculadas de `alerts_baseline_stats` para eficiencia

**Tipos de anomalía:**
- **TOO_SHORT:** Duración anormalmente corta (posible problema de calidad, desconexiones)
- **TOO_LONG:** Duración anormalmente larga (posible problema de bot, loops, o casos edge)

**Horario de operación:** 6:00 AM - 11:00 PM

---

### 📊 Variables de Salida

| Variable | Tipo | Descripción |
|----------|------|-------------|
| `datetime` | TIMESTAMP | Marca de tiempo del momento en que se genera la alerta |
| `T_avg_duration_seconds` | FLOAT | **Today Average Duration** - Duración promedio actual de las llamadas en segundos |
| `30D_AVG_duration_seconds` | FLOAT | **30-Day Average Duration** - Duración promedio histórica para la misma hora del día en los últimos 30 días. Baseline de comparación (μ) |
| `sigma_deviation` | FLOAT | **Desviación en Sigmas (σ)** - Número de desviaciones estándar que la duración actual difiere del promedio. Puede ser positivo (más larga) o negativo (más corta). Calculado como: `(T_avg - 30D_AVG) / stddev_30d` |
| `alert_message` | VARCHAR | Mensaje descriptivo indicando tipo de anomalía (TOO_SHORT/TOO_LONG), duración actual vs baseline, y nivel de desviación estadística |

---

### 🚨 Alert Severity Levels (DETECCIÓN ESTADÍSTICA BIDIRECCIONAL)

| Severity | Condición | Umbral Estadístico | Descripción |
|----------|-----------|-------------------|-------------|
| **🔴 CRITICAL** | `\|T_avg - μ\| > 3σ` | Desviación > 3σ (cualquier dirección) | Anomalía extrema: duración promedio >3 desviaciones estándar del histórico (probabilidad <0.3%). Ya sea demasiado corta o larga. |
| **🟡 WARNING** | `\|T_avg - μ\| > 2σ` | Desviación > 2σ (cualquier dirección) | Anomalía significativa: duración >2 desviaciones estándar del promedio (fuera del 95% esperado). |
| **🟢 FINE** | `\|T_avg - μ\| ≤ 2σ` | Dentro de ±2σ | Duración dentro del rango esperado (95% de valores históricos). Operación normal. |
| **⚪ INSUFFICIENT_DATA** | `T_calls < 10` OR `baseline_sample_size < 10` | Muestra insuficiente | Datos insuficientes: mínimo 10 completed calls en hora actual y 10 horas en baseline de 30 días. |

**🔄 Tipos de Anomalía:**

| Tipo | Condición | Interpretación | Posibles Causas |
|------|-----------|----------------|-----------------|
| **TOO_SHORT** | `T_avg < μ - 2σ` | Llamadas anormalmente cortas | - Problemas de calidad de red<br>- Desconexiones frecuentes<br>- Usuarios colgando prematuramente<br>- Problemas en el flujo del bot |
| **TOO_LONG** | `T_avg > μ + 2σ` | Llamadas anormalmente largas | - Loops en el bot<br>- Casos edge no manejados<br>- Problemas en lógica de finalización<br>- Consultas inusualmente complejas |
| **NORMAL** | `μ - 2σ ≤ T_avg ≤ μ + 2σ` | Duración dentro de lo esperado | Operación normal |

**📊 Conceptos Estadísticos:**
- **μ (mu):** Media/promedio de la duración histórica (en segundos)
- **σ (sigma):** Desviación estándar de la duración histórica
- **Lower Threshold:** `μ - 2σ` (límite inferior de lo aceptable)
- **Upper Threshold:** `μ + 2σ` (límite superior de lo aceptable)
- **|x|:** Valor absoluto (distancia sin importar dirección)

**Lógica de evaluación:**
1. Verifica datos suficientes (≥10 completed calls, baseline ≥10 horas)
2. Calcula desviación: `sigma_deviation = (T_avg - μ) / σ`
   - Si negativo: llamadas más cortas de lo normal
   - Si positivo: llamadas más largas de lo normal
3. Calcula valor absoluto: `|sigma_deviation|`
4. Clasifica tipo de anomalía:
   - Si `T_avg < μ - 2σ` → `TOO_SHORT`
   - Si `T_avg > μ + 2σ` → `TOO_LONG`
   - Sino → `NORMAL`
5. Aplica umbrales de severidad:
   - CRITICAL: `|σ_deviation| > 3`
   - WARNING: `|σ_deviation| > 2`
6. Solo alerta en horario operacional (6 AM - 11 PM)

**Ejemplo numérico (TOO_SHORT):**
- Baseline: `μ = 180s`, `σ = 35s`
- Umbrales:
  - Lower: `180 - 2*35 = 110s`
  - Upper: `180 + 2*35 = 250s`
  - CRITICAL: `|σ| > 3` → `T_avg < 75s` o `T_avg > 285s`
  - WARNING: `|σ| > 2` → `T_avg < 110s` o `T_avg > 250s`
- Si `T_avg = 86.7s`:
  - `σ_deviation = (86.7 - 180) / 35 = -2.67σ`
  - `|σ_deviation| = 2.67 > 2` pero `< 3`
  - Tipo: `TOO_SHORT` (86.7 < 110)
  - Resultado: **WARNING**

**Ejemplo numérico (TOO_LONG):**
- Mismo baseline: `μ = 170s`, `σ = 28s`
- Si `T_avg = 260s`:
  - `σ_deviation = (260 - 170) / 28 = +3.21σ`
  - `|σ_deviation| = 3.21 > 3`
  - Tipo: `TOO_LONG` (260 > 226)
  - Resultado: **CRITICAL**

---

### ⚙️ Cómo Funciona Internamente

#### Paso 1: Extracción de Métricas de la Hora Actual (Tiempo Real)
```sql
SELECT
  organization_code,
  organization_name,
  country,
  COUNT(*) AS total_calls,
  SUM(CASE WHEN call_classification IN ('good_calls', 'short_calls', 'completed') THEN 1 ELSE 0 END) AS completed_calls,
  ROUND(AVG(call_duration_seconds), 2) AS avg_call_duration_seconds
FROM ai_calls_detail
WHERE created_hour = date_trunc('hour', CURRENT_TIMESTAMP())
```

#### Paso 2: Obtención de Estadísticas Baseline (Pre-calculadas)

**Uso de `alerts_baseline_stats` para Alert 5**

Esta alerta también utiliza la vista materializada `alerts_baseline_stats`, pero en este caso aprovecha las **estadísticas de duración de llamadas** pre-calculadas. A diferencia de Alert 4 (que solo detecta spikes hacia arriba), Alert 5 es **bidireccional** y necesita umbrales superior E inferior.

**¿Qué estadísticas se usan?**

```sql
-- Join con tabla de estadísticas baseline (actualizada cada 1 hora)
FROM current_hour_realtime curr
INNER JOIN alerts_baseline_stats base
  ON curr.organization_code = base.organization_code
  AND curr.country = base.country
  AND EXTRACT(HOUR FROM CURRENT_TIMESTAMP()) = base.hour_of_day

-- Estadísticas pre-calculadas para call duration:
-- - avg_call_duration_30d: Promedio histórico de duración (μ) en segundos
-- - stddev_call_duration_30d: Desviación estándar (σ) en segundos
-- - p05_call_duration_30d: Percentil 5 (5% de duraciones más cortas)
-- - p25_call_duration_30d: Percentil 25 (cuartil inferior)
-- - p50_call_duration_30d: Mediana (percentil 50)
-- - p75_call_duration_30d: Percentil 75 (cuartil superior)
-- - p95_call_duration_30d: Percentil 95 (5% de duraciones más largas)
-- - call_duration_lower_threshold: μ - 2σ (límite inferior para TOO_SHORT)
-- - call_duration_upper_threshold: μ + 2σ (límite superior para TOO_LONG)
-- - sample_size_30d: Número de horas con datos en últimos 30 días
```

**Cálculo específico para duración:**

La tabla `alerts_baseline_stats` calcula estas estadísticas así:

```sql
-- 1. Primero obtiene duración promedio POR HORA desde ai_calls_detail
SELECT
  organization_code, country, hour_of_day, created_hour,
  ROUND(AVG(call_duration_seconds), 2) AS avg_call_duration_seconds
FROM ai_calls_detail
WHERE created_date >= CURRENT_DATE() - INTERVAL 30 DAY
GROUP BY organization_code, country, hour_of_day, created_hour
HAVING completed_calls >= 10

-- 2. Luego calcula estadísticas sobre esos promedios horarios
SELECT
  organization_code, country, hour_of_day,
  AVG(avg_call_duration_seconds) AS avg_call_duration_30d,        -- μ
  STDDEV(avg_call_duration_seconds) AS stddev_call_duration_30d,  -- σ
  percentile_approx(avg_call_duration_seconds, 0.05) AS p05,      -- 5%
  percentile_approx(avg_call_duration_seconds, 0.95) AS p95,      -- 95%
  
  -- Pre-calcula umbrales bidireccionales
  AVG(...) - 2 * STDDEV(...) AS call_duration_lower_threshold,  -- μ - 2σ
  AVG(...) + 2 * STDDEV(...) AS call_duration_upper_threshold,  -- μ + 2σ
  
  COUNT(*) AS sample_size_30d
FROM ...
GROUP BY organization_code, country, hour_of_day
```

**Ejemplo de datos para Rappi PE a las 4 PM:**

| Estadística | Valor | Interpretación |
|-------------|-------|----------------|
| `avg_call_duration_30d` | 180s | Promedio histórico: 3 minutos |
| `stddev_call_duration_30d` | 35s | Desviación estándar típica |
| `p05_call_duration_30d` | 120s | 5% de llamadas duran menos de 2 min |
| `p50_call_duration_30d` | 175s | Mediana: 2.9 minutos |
| `p95_call_duration_30d` | 240s | 5% de llamadas duran más de 4 min |
| `call_duration_lower_threshold` | 110s | μ - 2σ: Umbral TOO_SHORT |
| `call_duration_upper_threshold` | 250s | μ + 2σ: Umbral TOO_LONG |
| `sample_size_30d` | 28 | 28 horas de 4 PM en últimos 30 días |

**Ventajas para detección bidireccional:**
- ✅ **Umbrales pre-calculados:** No necesita calcular `μ - 2σ` y `μ + 2σ` en cada ejecución
- ✅ **Rango completo de percentiles:** Permite análisis detallado de distribución
- ✅ **Detecta ambos extremos:** TOO_SHORT (< μ - 2σ) y TOO_LONG (> μ + 2σ)
- ✅ **Considera variabilidad horaria:** La duración típica varía según hora del día

#### Paso 3: Cálculo de Desviación Estadística
```sql
-- Calcula cuántas desviaciones estándar está el valor actual del promedio
sigma_deviation = (current_avg_duration - avg_duration_30d) / stddev_duration_30d

-- Ejemplo 1 (TOO_SHORT):
-- Si avg = 180s, stddev = 30s, y current = 120s
-- sigma_deviation = (120 - 180) / 30 = -2.0σ (negativo = más corto)

-- Ejemplo 2 (TOO_LONG):
-- Si avg = 180s, stddev = 30s, y current = 250s
-- sigma_deviation = (250 - 180) / 30 = +2.33σ (positivo = más largo)
```

#### Paso 4: Clasificación de Tipo de Anomalía
```sql
CASE 
  WHEN current_avg_duration < call_duration_lower_threshold  -- μ - 2σ
    THEN 'TOO_SHORT'
  WHEN current_avg_duration > call_duration_upper_threshold  -- μ + 2σ
    THEN 'TOO_LONG'
  ELSE 'NORMAL'
END AS anomaly_type
```

#### Paso 5: Determinación de Severidad
```sql
CASE
  -- Insufficient data
  WHEN completed_calls < 10 
    OR sample_size_30d < 10
    THEN 'INSUFFICIENT_DATA'
  
  -- CRITICAL: > 3 desviaciones estándar (en cualquier dirección)
  WHEN ABS(current_avg_duration - avg_duration_30d) > 3 * stddev_30d
    THEN 'CRITICAL'
  
  -- WARNING: > 2 desviaciones estándar (en cualquier dirección)
  WHEN ABS(current_avg_duration - avg_duration_30d) > 2 * stddev_30d
    THEN 'WARNING'
  
  ELSE 'FINE'
END
```

**Nota sobre cambios de umbral:**
- Se redujo de `< 20` a `< 10` completed calls para INSUFFICIENT_DATA
- Se eliminó la verificación `has_sufficient_baseline_data = FALSE`
- Esto hace la alerta menos restrictiva, permitiendo detección temprana de anomalías con muestras más pequeñas

**Umbrales Estadísticos (Bidireccionales):**
- **Rango Normal:** `μ ± 2σ` (95% de valores esperados)
- **WARNING:** `|current - μ| > 2σ`
- **CRITICAL:** `|current - μ| > 3σ`

#### Paso 6: Filtrado de Alertas
Solo se muestran alertas que cumplan:
- `alert_severity IN ('CRITICAL', 'WARNING')`
- `current_hour BETWEEN 6 AND 23`
- `current_completed_calls >= 10`

---

### 📝 Ejemplo Práctico 1: Duración Anormalmente Corta

**Escenario:** Hoy es Jueves 22 de Diciembre de 2025 a las 10:00 AM

**Datos de entrada:**

**Hora actual (Jueves 10:00 AM):**
- Total calls: 150
- Completed calls: 130
- Total call seconds: 13,000
- Average duration: 13,000/150 = **86.7 segundos** (~1.4 minutos)

**Baseline (últimos 30 días, horas de 10:00 AM):**
- Promedio (μ): **180 segundos** (3 minutos)
- Desviación estándar (σ): **35 segundos**
- Mediana: 175s
- P25: 150s
- P75: 210s
- Lower threshold (μ - 2σ): 180 - 2*35 = **110 segundos**
- Upper threshold (μ + 2σ): 180 + 2*35 = **250 segundos**
- Sample size: 27 horas

**Cálculos:**
```
T_avg_duration_seconds = 86.7s
30D_AVG_duration_seconds = 180s
stddev = 35s

sigma_deviation = (86.7 - 180) / 35 = -2.67σ (negativo = más corto)

Lower threshold = 110s
```

**Evaluación:**
- `T_avg_duration = 86.7s < 110s (lower threshold)` ✅ → Anomalía TOO_SHORT
- `|sigma_deviation| = 2.67 > 2σ` ✅ → WARNING
- `|sigma_deviation| = 2.67 < 3σ` ✅ → No es CRITICAL

**Resultado:**

| datetime | T_avg_duration_seconds | 30D_AVG_duration_seconds | sigma_deviation | alert_message |
|----------|------------------------|--------------------------|-----------------|---------------|
| 2025-12-22 10:00:00 | 86.7 | 180 | -2.67 | WARNING: Rappi (PE) - Shorter than usual call duration. Current: 87s vs Baseline: 180s |

**Interpretación:** Las llamadas están durando significativamente menos de lo normal (2.67 desviaciones estándar por debajo del promedio). Posibles causas: problemas de calidad de red, usuarios colgando antes de tiempo, problemas en el flujo conversacional del bot que causan frustración temprana.

---

### 📝 Ejemplo Práctico 2: Duración Anormalmente Larga

**Escenario:** Hoy es Viernes 22 de Diciembre de 2025 a las 2:00 PM

**Datos de entrada:**

**Hora actual (Viernes 2:00 PM):**
- Total calls: 200
- Completed calls: 170
- Total call seconds: 52,000
- Average duration: 52,000/200 = **260 segundos** (~4.3 minutos)

**Baseline (últimos 30 días, horas de 2:00 PM):**
- Promedio (μ): **170 segundos** (~2.8 minutos)
- Desviación estándar (σ): **28 segundos**
- Upper threshold (μ + 2σ): 170 + 2*28 = **226 segundos**
- Sample size: 29 horas

**Cálculos:**
```
T_avg_duration_seconds = 260s
30D_AVG_duration_seconds = 170s
stddev = 28s

sigma_deviation = (260 - 170) / 28 = +3.21σ (positivo = más largo)

Upper threshold = 226s
```

**Evaluación:**
- `T_avg_duration = 260s > 226s (upper threshold)` ✅ → Anomalía TOO_LONG
- `sigma_deviation = 3.21 > 3σ` ✅ → CRITICAL

**Resultado:**

| datetime | T_avg_duration_seconds | 30D_AVG_duration_seconds | sigma_deviation | alert_message |
|----------|------------------------|--------------------------|-----------------|---------------|
| 2025-12-22 14:00:00 | 260 | 170 | +3.21 | CRITICAL: Rappi (PE) - Call duration ANOMALY: Unusually LONG! Current avg: 260s vs Baseline: 170s (+3.21σ above normal) |

**Interpretación:** Las llamadas están durando significativamente más de lo normal (3.21 desviaciones estándar por encima del promedio). Posibles causas: problemas en el bot que causan loops, casos edge no manejados correctamente, alta complejidad de consultas de usuarios, o problemas en la lógica de finalización de llamadas.

---

## 📌 Resumen Comparativo de las 5 Alertas

| Alert | Tipo de Comparación | Granularidad | Baselines | Método Detección | Umbrales Severidad | Horario Alerta |
|-------|-------------------|--------------|-----------|------------------|-------------------|----------------|
| **Alert 1** | Week-over-Week (WoW) | Horaria | 1 baseline (semana pasada misma hora) | Threshold fijo | 🟡 WARNING: `< 90%`<br>🔴 CRITICAL: `< 70%` | 6 AM - 11 PM |
| **Alert 2** | Dual Baseline (DoD + 30D) | Diaria | 2 baselines (ayer + promedio 30d todos los días) | Threshold fijo AND lógico | 🟡 WARNING: `< 90%` en AMBAS<br>🔴 CRITICAL: `< 70%` en AMBAS | Todo el día |
| **Alert 3** | Dual Baseline (WoW + 30D) | Diaria | 2 baselines (semana pasada + promedio 30d mismo día semana) | Threshold fijo AND lógico | 🟡 WARNING: `< 90%` en AMBAS<br>🔴 CRITICAL: `< 70%` en AMBAS | Después de 1 PM |
| **Alert 4** | Detección Estadística | Horaria | 1 baseline (30d mismo hora) con σ | Desviación estándar | 🟡 WARNING: `> μ + 2σ`<br>🔴 CRITICAL: `> μ + 3σ` o `> P95*1.2` | 6 AM - 11 PM |
| **Alert 5** | Detección Estadística Bidireccional | Horaria (tiempo real) | 1 baseline (30d misma hora) con σ | Desviación estándar bidireccional | 🟡 WARNING: `\|x - μ\| > 2σ`<br>🔴 CRITICAL: `\|x - μ\| > 3σ` | 6 AM - 11 PM |

**Notas importantes:**
- **Alert 2 y 3:** Usan operador AND - deben cumplirse AMBAS condiciones simultáneamente
- **Alert 4:** Solo detecta spikes (aumentos), no caídas
- **Alert 5:** Bidireccional - detecta tanto duraciones TOO_SHORT como TOO_LONG
- **Todas:** Requieren muestra mínima de datos (varía por alerta), sino reportan INSUFFICIENT_DATA

---

## 🔍 Términos Clave

### Métricas de Clasificación de Llamadas
- **good_calls:** Llamadas completadas de alta calidad (duración > umbral de llamada corta)
- **short_calls:** Llamadas completadas pero con duración muy corta (posible mala calidad)
- **completed_calls:** Total de llamadas completadas (`good_calls + short_calls`)
- **quality_rate:** Ratio de good_calls respecto a completed_calls (`good_calls / completed_calls`)

### Notación de Periodos Temporales
- **T (Today):** Métrica del periodo actual (hoy o hora actual)
- **Y (Yesterday):** Métrica de ayer mismo momento
- **LW (Last Week):** Métrica de la semana pasada mismo día/hora
- **30D_AVG (30-Day Average):** Promedio de los últimos 30 días
- **30D (30-Day):** Relativo a los últimos 30 días

### Conceptos Estadísticos
- **μ (mu):** Media o promedio
- **σ (sigma):** Desviación estándar
- **Pxx (Percentil):** Valor por debajo del cual cae el xx% de los datos
  - P50: Mediana (50% de datos están por debajo)
  - P95: 95% de datos están por debajo
- **Threshold:** Umbral calculado (ej: μ ± 2σ)
- **Sigma deviation:** Número de desviaciones estándar de distancia del promedio

### Niveles de Severidad

Los niveles de severidad son estándares para todas las alertas, pero los umbrales específicos varían según el tipo de detección:

| Severity | Símbolo | Descripción General | Acción Recomendada |
|----------|---------|---------------------|-------------------|
| **🔴 CRITICAL** | CRITICAL | Degradación severa o anomalía extrema que requiere **acción inmediata**. Impacto significativo en la operación. | Investigar y resolver de inmediato. Notificar al equipo on-call. |
| **🟡 WARNING** | WARNING | Degradación moderada o anomalía significativa que requiere **monitoreo activo**. Puede escalar a CRITICAL si no se atiende. | Revisar en próximas 1-2 horas. Preparar plan de acción. |
| **🟢 FINE** | FINE | Métrica dentro del rango normal esperado. Operación normal. | No se requiere acción. Continuar monitoreo de rutina. |
| **⚪ INSUFFICIENT_DATA** | INSUFFICIENT_DATA | No hay suficientes datos para determinar confiablemente. Puede ser normal durante horas de bajo tráfico. | Revisar si persiste en horas pico. Verificar integración de datos. |

#### Umbrales por Tipo de Alerta

**Alertas basadas en Threshold Fijo (Alert 1, 2, 3):**

| Severity | Alert 1 (Hourly Quality) | Alert 2 (Daily Quality) | Alert 3 (Daily Volume) |
|----------|--------------------------|-------------------------|------------------------|
| **CRITICAL** | Caída > 30% vs LW<br>`ratio < 0.70` | Caída > 30% vs Y **AND** 30D<br>`ratio < 0.70` en ambos | Caída > 30% vs LW **AND** 30D<br>`ratio < 0.70` en ambos |
| **WARNING** | Caída 10-30% vs LW<br>`0.70 ≤ ratio < 0.90` | Caída 10-30% vs Y **AND** 30D<br>`0.70 ≤ ratio < 0.90` en ambos | Caída 10-30% vs LW **AND** 30D<br>`0.70 ≤ ratio < 0.90` en ambos |
| **FINE** | Caída < 10%<br>`ratio ≥ 0.90` | Caída < 10% en al menos una baseline | Caída < 10% en al menos una baseline |
| **INSUFFICIENT_DATA** | `calls < 20` en T o LW | `calls < 50` en T o Y<br>O `days < 20` en 30D | `weekday_count < 3`<br>O `avg < 30`<br>O `LW < 50` |

**Alertas basadas en Detección Estadística (Alert 4, 5):**

| Severity | Alert 4 (Short Call Rate) | Alert 5 (Call Duration) |
|----------|---------------------------|------------------------|
| **CRITICAL** | `rate > μ + 3σ`<br>O `rate > P95 * 1.2` con ≥10 short calls | `\|duration - μ\| > 3σ`<br>(cualquier dirección) |
| **WARNING** | `rate > μ + 2σ`<br>con ≥5 short calls | `\|duration - μ\| > 2σ`<br>(cualquier dirección) |
| **FINE** | `rate ≤ μ + 2σ` | `\|duration - μ\| ≤ 2σ` |
| **INSUFFICIENT_DATA** | `calls < 10`<br>O `baseline_hours < 10` | `calls < 10`<br>O `baseline_hours < 10` |

#### Consideraciones Importantes

1. **Alertas con Dual Baseline (Alert 2 y 3):**
   - Usan **operador AND** lógico
   - Solo alertan si AMBAS condiciones se cumplen simultáneamente
   - Esto reduce significativamente los falsos positivos

2. **Alertas Estadísticas (Alert 4 y 5):**
   - Usan desviación estándar (σ) como umbral dinámico
   - Se adaptan automáticamente a la variabilidad histórica
   - Alert 5 es bidireccional (detecta TOO_SHORT y TOO_LONG)

3. **Requisitos de Datos Mínimos:**
   - Varían por alerta según granularidad y tipo de comparación
   - Diseñados para evitar alertas basadas en muestras pequeñas no representativas
   - INSUFFICIENT_DATA no es un error, es una salvaguarda de calidad

4. **Horarios Operacionales:**
   - Alert 1, 4, 5: Solo alertan entre 6:00 AM - 11:00 PM
   - Alert 2: Opera todo el día
   - Alert 3: Solo alerta después de 1:00 PM (para tener suficiente data acumulada)

---

## 📚 Uso de las Alertas

### Vistas Disponibles por Alerta

Cada alerta tiene **DOS archivos SQL**:

1. **`alert_X.sql`** (Vista de Alertas)
   - Solo muestra alertas activas (CRITICAL y WARNING)
   - Incluye mensaje de alerta descriptivo
   - Filtrada por horario operacional
   - Requiere muestra mínima de datos

2. **`normal_alert_X.sql`** (Vista de Métricas)
   - Muestra TODAS las organizaciones con sus métricas
   - No filtra por severidad
   - Incluye columna `alert_severity` para análisis
   - Útil para monitoreo preventivo y análisis histórico

### Filtros en Metabase

Todas las vistas soportan filtros variables:
- `{{organization_name}}`: Filtrar por organización
- `{{countries}}`: Filtrar por país
- `{{time}}`: Rango de fechas (solo en vistas normales de alert 4 y 5)

---

**Última actualización:** Diciembre 2025  
**Versión:** 1.0  
**Contacto:** Data Engineering Team


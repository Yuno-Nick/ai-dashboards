# 🤝 Guía de Contribución - AI Dashboards

Gracias por contribuir a nuestros dashboards! Esta guía te ayudará a mantener la calidad y consistencia del repositorio.

---

## 📋 Tabla de Contenidos

1. [Antes de Empezar](#antes-de-empezar)
2. [Tipos de Contribuciones](#tipos-de-contribuciones)
3. [Estándares de Código SQL](#estándares-de-código-sql)
4. [Estándares de Documentación](#estándares-de-documentación)
5. [Proceso de Pull Request](#proceso-de-pull-request)
6. [Testing y Validación](#testing-y-validación)
7. [Mensajes de Commit](#mensajes-de-commit)

---

## 🎯 Antes de Empezar

### Checklist de Prerequisites

- [ ] Tienes acceso a Metabase (producción y staging)
- [ ] Tienes acceso a StarRocks
- [ ] Has leído el [README principal](./README.md)
- [ ] Entiendes la estructura del repositorio
- [ ] Has revisado la documentación del dashboard que vas a modificar

### Principios Fundamentales

1. **Documentación primero:** Si no está documentado, no existe
2. **Claridad sobre brevedad:** Código legible > Código corto
3. **Mantén la compatibilidad:** Los cambios no deben romper dashboards existentes
4. **Prueba todo:** Valida tus queries antes de hacer commit
5. **Comunica cambios:** Actualiza CHANGELOG y avisa al equipo

---

## 🔄 Tipos de Contribuciones

### 1. 🐛 Bug Fixes

**Cuándo:**
- Corrección de errores en queries
- Ajuste de umbrales incorrectos
- Fix de sintaxis SQL

**Proceso:**
```bash
1. Identifica el bug y su impacto
2. Crea branch: fix/descripcion-corta
3. Corrige el query
4. Prueba en staging
5. Actualiza CHANGELOG del dashboard
6. Commit: "fix(dashboard): descripción del fix"
7. Pull request con evidencia del fix
```

**Ejemplo:**
```
fix(alerts): correct CRITICAL threshold in alert_2 from 0.80 to 0.70

- Changed threshold to match documented specification
- Tested with historical data
- Updated CHANGELOG.md
```

### 2. ✨ Nuevas Features

**Cuándo:**
- Nueva alerta o vista
- Nueva funcionalidad en dashboard existente
- Nuevo filtro o visualización

**Proceso:**
```bash
1. Discute la feature con el owner del dashboard
2. Crea branch: feature/nombre-feature
3. Implementa la feature
4. Crea/actualiza documentación técnica
5. Actualiza resumen ejecutivo si aplica
6. Agrega tests si es posible
7. Actualiza CHANGELOG detalladamente
8. Pull request con ejemplos y capturas
```

**Ejemplo:**
```
feat(alerts): add alert_6 for response time spikes

- Implements statistical detection for response time
- Uses 2σ threshold with 30-day baseline
- Includes metrics view (normal_alert_6.sql)
- Documented in ALERTS_DOCUMENTATION.md
- Added to executive summary with examples
```

### 3. 📚 Mejoras de Documentación

**Cuándo:**
- Clarificar documentación existente
- Agregar ejemplos
- Corregir typos
- Actualizar información obsoleta

**Proceso:**
```bash
1. Identifica qué mejorar
2. Crea branch: docs/descripcion
3. Actualiza documentación
4. Verifica formato markdown
5. Commit: "docs(dashboard): descripción"
6. Pull request
```

### 4. 🏗️ Refactoring

**Cuándo:**
- Optimización de queries
- Reorganización de estructura
- Mejora de rendimiento

**Proceso:**
```bash
1. Documenta el problema actual
2. Propón solución al owner
3. Crea branch: refactor/descripcion
4. Implementa cambios manteniendo compatibilidad
5. Valida que resultados sean idénticos
6. Actualiza documentación
7. Pull request con benchmarks
```

---

## 📝 Estándares de Código SQL

### Estructura de Archivo

```sql
-- ==============================================================================
-- [NOMBRE DEL QUERY]
-- ==============================================================================
-- [Descripción breve de 1-2 líneas del propósito]
-- 
-- Última actualización: YYYY-MM-DD
-- Owner: [Tu Nombre/Equipo]
-- 
-- Dependencias:
-- - {{ ref('tabla_dbt') }} o nombre_tabla
-- - {{ ref('otra_tabla') }}
-- 
-- Filtros de Metabase (si aplica):
-- - {{organization_name}}: Filtrar por organización
-- - {{countries}}: Filtrar por país
-- - {{time}}: Rango de fechas
-- 
-- Outputs:
-- - columna_1: Descripción
-- - columna_2: Descripción
-- ==============================================================================

-- CTEs principales
WITH cte_descriptivo AS (
  SELECT
    -- Comentarios para lógica compleja
    columna_1,
    columna_2
  FROM tabla
  WHERE condicion
)

-- Query final
SELECT
  columna_1,
  columna_2
FROM cte_descriptivo
ORDER BY columna_1
```

### Convenciones de Nomenclatura

**Tablas y Columnas:**
```sql
-- ✅ BIEN: snake_case
organization_code
created_date
short_call_rate

-- ❌ MAL: camelCase o PascalCase
organizationCode
createdDate
ShortCallRate
```

**CTEs:**
```sql
-- ✅ BIEN: Descriptivo, snake_case
WITH current_hour_metrics AS (...)
WITH baseline_30d_avg AS (...)

-- ❌ MAL: Abreviaciones crípticas
WITH chm AS (...)
WITH b30 AS (...)
```

**Aliases:**
```sql
-- ✅ BIEN: Consistente con convenciones del proyecto
T_rate        -- Today
Y_rate        -- Yesterday
LW_rate       -- Last Week
30D_AVG_rate  -- 30-Day Average

-- ❌ MAL: Inconsistente o confuso
today_rate
yesterday_value
lw_r
```

### Formato y Estilo

**Indentación:**
```sql
-- ✅ BIEN: 2 espacios
SELECT
  organization_code,
  COUNT(*) AS total_calls
FROM ai_calls_detail
WHERE
  created_date >= CURRENT_DATE() - INTERVAL 7 DAY
  AND country = 'PE'
GROUP BY organization_code

-- ❌ MAL: Tabs o 4 espacios (inconsistente)
SELECT
    organization_code,
    COUNT(*) AS total_calls
FROM ai_calls_detail
```

**Keywords:**
```sql
-- ✅ BIEN: MAYÚSCULAS para keywords SQL
SELECT, FROM, WHERE, GROUP BY, HAVING, ORDER BY
COUNT, SUM, AVG, CASE, WHEN, THEN, END

-- ❌ MAL: Minúsculas para keywords
select, from, where, count
```

**Joins y Condiciones:**
```sql
-- ✅ BIEN: Explícito y legible
FROM current_hour c
INNER JOIN baseline b
  ON c.organization_code = b.organization_code
  AND c.country = b.country
  AND EXTRACT(HOUR FROM c.created_hour) = b.hour_of_day

-- ❌ MAL: Todo en una línea
FROM current_hour c INNER JOIN baseline b ON c.organization_code = b.organization_code AND c.country = b.country
```

### Comentarios

**Cuándo comentar:**
- Lógica compleja o no obvia
- Cálculos matemáticos (ej: desviación estándar)
- Decisiones de negocio (ej: umbrales)
- Workarounds temporales

```sql
-- ✅ BIEN: Explica el "por qué"
-- Calculamos sigma_deviation para detectar anomalías estadísticas
-- 2σ indica que el valor está fuera del 95% de la distribución normal
CASE 
  WHEN base.stddev_short_call_rate_30d > 0 
  THEN ROUND((curr.short_call_rate - base.avg_short_call_rate_30d) / base.stddev_short_call_rate_30d, 2)
  ELSE 0
END AS sigma_deviation

-- ❌ MAL: Repite lo obvio
-- Selecciona organization_code
SELECT organization_code
```

### Optimización

**Buenas prácticas:**
```sql
-- ✅ Filtra temprano
WITH filtered_data AS (
  SELECT *
  FROM ai_calls_detail
  WHERE created_date >= CURRENT_DATE() - INTERVAL 30 DAY  -- Filtro aquí
)

-- ❌ Filtra tarde
WITH all_data AS (
  SELECT *
  FROM ai_calls_detail  -- Carga todo
)
SELECT *
FROM all_data
WHERE created_date >= CURRENT_DATE() - INTERVAL 30 DAY  -- Filtro muy tarde
```

```sql
-- ✅ Usa NULLIF para evitar división por cero
ROUND(good_calls::float / NULLIF(completed_calls, 0), 4)

-- ❌ Asume que nunca será cero
ROUND(good_calls::float / completed_calls, 4)  -- ERROR si completed_calls = 0
```

---

## 📚 Estándares de Documentación

### Documentación Técnica (DOCUMENTATION.md)

**Estructura requerida:**

1. **Índice** con links a secciones
2. **Descripción General** del dashboard
3. **Variables de Salida** (tabla con todas las columnas)
4. **Alert Severity Levels** (si aplica)
5. **Cómo Funciona Internamente** (paso a paso)
6. **Ejemplos Prácticos** con datos reales
7. **Términos Clave** (glosario)
8. **Uso y Configuración**

**Formato de tablas:**
```markdown
| Variable | Tipo | Descripción |
|----------|------|-------------|
| `datetime` | TIMESTAMP | Marca de tiempo de la alerta |
| `T_rate` | FLOAT | Today Rate - Ratio actual (0-1) |
```

### Resumen Ejecutivo (EXECUTIVE_SUMMARY.md)

**Características:**
- ✅ Lenguaje no técnico
- ✅ Analogías y ejemplos del mundo real
- ✅ Enfoque en valor de negocio
- ✅ Casos de uso prácticos
- ✅ Checklists de acción

**Evitar:**
- ❌ Jerga técnica excesiva
- ❌ Queries SQL
- ❌ Detalles de implementación
- ❌ Fórmulas matemáticas complejas

### README por Dashboard

**Secciones requeridas:**

```markdown
# Dashboard Name

## 🎯 Propósito
[1-2 párrafos explicando para qué sirve]

## 📊 Queries Disponibles
[Lista de queries con descripción breve]

## 📚 Documentación
- [Documentación Técnica](./DOCUMENTATION.md)
- [Resumen Ejecutivo](./EXECUTIVE_SUMMARY.md)

## 🚀 Quick Start
[Pasos para usar el dashboard]

## 🔗 Links
[Metabase, dependencies, etc.]
```

---

## 🔍 Proceso de Pull Request

### Checklist Pre-PR

Antes de crear tu PR, verifica:

- [ ] El query corre correctamente en staging
- [ ] Probaste con datos reales (al menos 1 semana)
- [ ] Actualizaste el CHANGELOG del dashboard
- [ ] Actualizaste documentación técnica si aplica
- [ ] Actualizaste resumen ejecutivo si aplica
- [ ] Agregaste comentarios en el código
- [ ] Seguiste el style guide
- [ ] No hay hardcoded credentials o datos sensibles
- [ ] El query es eficiente (< 30 segundos idealmente)

### Template de Pull Request

```markdown
## 📝 Descripción
[Describe qué cambia y por qué]

## 🎯 Tipo de Cambio
- [ ] Bug fix
- [ ] Nueva feature
- [ ] Documentación
- [ ] Refactor
- [ ] Otro: ___

## 🧪 Testing
[Cómo probaste los cambios]

- Período probado: [fecha inicio] a [fecha fin]
- Organizaciones probadas: [lista]
- Resultados: [describe validación]

## 📸 Screenshots
[Capturas de Metabase, si aplica]

## 📚 Checklist
- [ ] Código sigue el style guide
- [ ] Documentación actualizada
- [ ] CHANGELOG actualizado
- [ ] Probado en staging
- [ ] Sin breaking changes (o documentados)

## 🔗 Links Relacionados
- Issue: #123
- Confluence: [link]
- Slack thread: [link]
```

### Revisión de PR

**Como autor:**
- Responde a comentarios en <24 horas
- Resuelve conversaciones cuando hagas cambios
- Pide clarificación si no entiendes un comentario

**Como reviewer:**
- Revisa en <48 horas
- Sé constructivo y específico
- Aprueba solo si cumple todos los estándares
- Haz preguntas si algo no es claro

---

## 🧪 Testing y Validación

### Tests Obligatorios

**1. Syntax Check:**
```sql
-- Corre el query en SQL editor primero
-- Verifica que no hay errores de sintaxis
```

**2. Data Validation:**
```sql
-- Valida que los resultados tienen sentido
-- Compara con período anterior conocido
-- Verifica edge cases (sin datos, un solo registro, etc.)
```

**3. Performance Check:**
```sql
-- Mide tiempo de ejecución
-- Debe ser < 30 segundos idealmente
-- Si > 1 minuto, optimiza o documenta por qué
```

### Test Cases Recomendados

Para alertas:
```sql
-- Test 1: Caso normal (FINE)
-- Test 2: Caso WARNING
-- Test 3: Caso CRITICAL
-- Test 4: Caso INSUFFICIENT_DATA
-- Test 5: Edge case (organización nueva, sin datos históricos)
```

---

## 💬 Mensajes de Commit

### Formato

```
<tipo>(scope): <descripción corta>

<descripción detallada opcional>

<footer opcional>
```

### Tipos

- `feat`: Nueva feature
- `fix`: Bug fix
- `docs`: Cambios en documentación
- `refactor`: Refactor sin cambio de funcionalidad
- `perf`: Mejora de performance
- `test`: Agregar o modificar tests
- `chore`: Mantenimiento (ej: actualizar dependencies)

### Ejemplos

```bash
# ✅ BIEN: Descriptivo y claro
feat(alerts): add alert_6 for response time anomalies
fix(alerts): correct threshold in alert_2 from 0.80 to 0.70
docs(alerts): add executive summary with business context
refactor(calls): optimize view_3 query using CTEs

# ❌ MAL: Vago o sin contexto
fix: bug
update alerts
changes
```

### Scopes Comunes

- `alerts`: Dashboard de alertas
- `calls`: Dashboard de calls
- `revenue`: Dashboard de revenue
- `whatsapp`: Dashboard de WhatsApp
- `docs`: Documentación general
- `repo`: Cambios en estructura del repositorio

---

## 🆘 Ayuda y Soporte

### ¿Tienes dudas?

1. **Revisa esta guía** completa
2. **Consulta el README** del dashboard
3. **Pregunta al owner** del dashboard (ver README principal)
4. **Slack #ai-data-team** para dudas generales

### ¿Encontraste un problema en esta guía?

¡Contribuye! Esta guía también acepta mejoras.

---

**Última actualización:** Diciembre 2025  
**Versión:** 1.0  
**Mantenido por:** AI Data Team - AI Squad


# Changelog - Alerts Dashboard

Historial de cambios específico del dashboard de alertas.

---

## [1.0.0] - 2025-12-22

### 🎉 Initial Release - Production Ready

#### Added

**Alertas implementadas:**
- ✅ **Alert 1:** Hourly Quality Degradation
  - Comparación simple Week-over-Week
  - Umbrales: WARNING <90%, CRITICAL <70%
  - Horario: 6 AM - 11 PM
  - Mínimo 20 completed calls requeridos

- ✅ **Alert 2:** Daily Quality Degradation  
  - Dual baseline: Yesterday + 30-Day Average
  - Lógica AND: Requiere degradación en AMBAS baselines
  - Umbrales: WARNING <90%, CRITICAL <70% (en ambas)
  - Mínimo 50 completed calls requeridos, 20 días de histórico

- ✅ **Alert 3:** Daily Volume Drop
  - Dual baseline: Last week same day + Same-weekday 30-day average
  - Lógica AND: Requiere caída en AMBAS baselines
  - Umbrales: WARNING <90%, CRITICAL <70% (en ambas)
  - Solo alerta después de 1:00 PM
  - Mínimo 3 días del mismo día de semana requeridos

- ✅ **Alert 4:** Short Call Rate Spike
  - Detección estadística con desviación estándar
  - Umbrales: WARNING >μ+2σ, CRITICAL >μ+3σ o >P95*1.2
  - Usa `alerts_baseline_stats` para estadísticas pre-calculadas
  - Mínimo 10 completed calls requeridos

- ✅ **Alert 5:** Call Duration Anomaly
  - Detección bidireccional (TOO_SHORT y TOO_LONG)
  - Umbrales: WARNING |μ-current|>2σ, CRITICAL |μ-current|>3σ
  - Usa `alerts_baseline_stats` para estadísticas pre-calculadas
  - Mínimo 10 completed calls requeridos

**Vistas métricas (sin filtros):**
- ✅ normal_alert_1.sql - Métricas de Alert 1 sin filtrar
- ✅ normal_alert_2.sql - Métricas de Alert 2 sin filtrar
- ✅ normal_alert_3.sql - Métricas de Alert 3 sin filtrar
- ✅ normal_alert_4.sql - Métricas de Alert 4 (últimos 7 días)
- ✅ normal_alert_5.sql - Métricas de Alert 5 (últimos 7 días)

**Visualizaciones adicionales:**
- ✅ view_6_hourly_distribution_avg.sql - Distribución horaria promedio
- ✅ view_7_daily_hourly_heatmap.sql - Heatmap simple
- ✅ view_8_daily_hourly_detailed.sql - Detalle con métricas completas
- ✅ view_9_daily_hourly_blocks.sql - Visualización en bloques para stacked bar chart

**Documentación:**
- ✅ ALERTS_DOCUMENTATION.md - Documentación técnica completa (1,303 líneas)
- ✅ ALERTS_EXECUTIVE_SUMMARY.md - Resumen ejecutivo para stakeholders (462 líneas)
- ✅ README.md - Índice y guía del dashboard
- ✅ METABASE_HEATMAP_SETUP.md - Instrucciones de configuración
- ✅ TEST_README.md - Guía de testing

**Testing:**
- ✅ TEST_alert_logic.sql - Tests con datos simulados
- ✅ TEST_alert_with_real_data.sql - Validación con datos reales
- ✅ QUICK_CHECK.sql - Validación rápida

#### Technical Details

**Convenciones de nomenclatura estandarizadas:**
- `T` = Today (hoy/hora actual)
- `Y` = Yesterday (ayer)
- `LW` = Last Week (semana pasada)
- `30D_AVG` = 30-Day Average (promedio 30 días)
- `σ` = Sigma (desviación estándar)

**Severity levels estandarizados:**
- 🟢 FINE: ≥90% del baseline (o ≤2σ para estadísticas)
- 🟡 WARNING: 70-90% del baseline (o >2σ para estadísticas)
- 🔴 CRITICAL: <70% del baseline (o >3σ para estadísticas)
- ⚪ INSUFFICIENT_DATA: Muestra insuficiente (varía por alerta)

**Compatibilidad StarRocks:**
- Reemplazado `COUNT_IF()` con `SUM(CASE WHEN ... THEN 1 ELSE 0 END)`
- Reemplazado `::FLOAT` con `CAST(... AS FLOAT)`
- Reemplazado `PERCENTILE_CONT` con `percentile_approx()`
- Reemplazado `DATEADD` con `CURRENT_DATE() - INTERVAL ... DAY`
- Reemplazado `||` con `CONCAT()` para concatenación de strings

---

## Development History

### 2025-12-22 - Finalización de Documentación
**Changed:**
- Acortadas descripciones en tablas de Alert Severity Levels para mejor renderizado
- Mejorado formato de todas las tablas en markdown

**Fixed:**
- Corrección de umbrales CRITICAL de Alert 2 de 80% a 70% en toda la documentación
- Consistencia en todos los archivos sobre umbrales

### 2025-12-22 - Umbral de Datos Ajustado
**Changed:**
- Alert 4 y 5: Reducido umbral de INSUFFICIENT_DATA de 20 calls a 10 calls
- Eliminado check de `has_sufficient_baseline_data = FALSE`
- Razón: Hacer alertas menos restrictivas para detección temprana

### 2025-12-22 - Separación de Vistas
**Added:**
- normal_alert_4.sql - Vista métricas para Alert 4
- normal_alert_5.sql - Vista métricas para Alert 5

**Changed:**
- alert_4.sql ahora contiene solo Alert View (CRITICAL/WARNING con mensaje)
- alert_5.sql ahora contiene solo Alert View (CRITICAL/WARNING con mensaje)
- normal_alert_4 y normal_alert_5 usan `CURRENT_TIMESTAMP()` y período de 7 días

### 2025-12-22 - Documentación Ejecutiva
**Added:**
- ALERTS_EXECUTIVE_SUMMARY.md con lenguaje no técnico
- Analogías del mundo real (termómetro, doctor, cronómetro)
- 3 casos de uso reales completos
- Checklists de acción rápida
- Explicación simple de conceptos estadísticos (σ, percentiles)

### 2025-12-22 - Dual Baseline para Alert 3
**Added:**
- Segunda baseline: Promedio del mismo día de semana últimos 30 días
- Columnas: `30D_AVG_Calls`, `T_v_30D_ratio`
- Filtro por `DAYOFWEEK()` para comparar solo mismo día de semana

**Changed:**
- Lógica de severidad ahora requiere caída en AMBAS baselines (AND)
- Umbral INSUFFICIENT_DATA ajustado a 3 días (de 20)
- Alert message menciona ambas baselines

**Rationale:**
- Compara "apples-to-apples" (Lunes vs Lunes, no Lunes vs Viernes)
- Reduce falsos positivos por patrones semanales

### 2025-12-22 - Dual Baseline para Alert 2
**Added:**
- Segunda baseline: Promedio de TODOS los últimos 30 días (no solo mismo día de semana)
- Columnas: `30D_AVG_rate`, `T_v_30D_ratio`

**Changed:**
- Lógica de severidad ahora requiere caída en AMBAS baselines (AND)
- Alert message menciona ambas baselines

**Rationale:**
- Confirmación dual reduce significativamente falsos positivos
- Si solo cae vs ayer, podría ser que ayer fue excepcional
- Si cae en ambas, el problema es real

### 2025-12-22 - Estandarización de Nomenclatura
**Changed:**
- `today_*` → `T_*`
- `yesterday_*` → `Y_*`
- `last_week_*` → `LW_*`
- `baseline_30d_avg` → `30D_AVG_*`
- `today_vs_yesterday` → `T_v_Y_ratio`
- `today_vs_last_week` → `T_v_LW_ratio`

**Rationale:**
- Consistencia en todos los queries
- Más conciso para visualización en Metabase
- Siguiendo convenciones de la industria

### 2025-12-22 - Separación de Vistas por Alert
**Changed:**
- Cada alert_*.sql ahora contiene DOS vistas:
  - VIEW 1: Metrics View (información completa sin filtros)
  - VIEW 2: Alert View (solo CRITICAL/WARNING con mensaje)

**Rationale:**
- Flexibilidad en Metabase
- Vista completa para análisis histórico
- Vista filtrada para monitoreo activo

### 2025-12-21 - Corrección de Compatibilidad StarRocks
**Fixed:**
- Alert 1: Sintaxis StarRocks para agregaciones y casts
- Alert 2: Sintaxis StarRocks para agregaciones y casts
- Alert 3: Sintaxis StarRocks para agregaciones y casts
- alerts_baseline_stats: Sintaxis StarRocks completa

**Technical:**
- `COUNT_IF()` → `SUM(CASE WHEN ... THEN 1 ELSE 0 END)`
- `::FLOAT` → `CAST(... AS FLOAT)`
- String concatenation con `CONCAT()` en lugar de `||`

### 2025-12-20 - Implementación Inicial
**Added:**
- Alert 1, 2, 3 con lógica de threshold fija
- Alert 4, 5 con detección estadística
- Modelo dbt `alerts_baseline_stats`
- Tests básicos

---

## Migration Notes

### Migrando de queries antiguos a v1.0.0:

**Cambios breaking:**
- Los archivos `alert_*.sql` ahora solo muestran CRITICAL/WARNING
- Para vista completa, usar `normal_alert_*.sql`
- Nombres de columnas cambiaron (ver estandarización arriba)

**Queries deprecados:**
- `ai_calls_aggregated.sql` (eliminado, usar `ai_calls_detail` directamente)
- `calls_quality_metrics.sql` (eliminado, volumen bajo hace innecesaria la agregación)

**Nuevas dependencias:**
- `alerts_baseline_stats` materialized view requerida para Alert 4 y 5

---

## Future Roadmap

### Planned for Q1 2026
- [ ] Alert 6: Response Time Anomaly
- [ ] Integración Slack notifications
- [ ] Dashboard de historical alert trends
- [ ] Automated testing en CI/CD

### Under Consideration
- [ ] ML-based anomaly detection
- [ ] Auto-tuning de umbrales basado en feedback
- [ ] Predicción de alertas (forecast)
- [ ] Root cause analysis automático

---

**Última actualización:** 2025-12-22  
**Versión actual:** 1.0.0  
**Mantenido por:** AI Data Team - AI Squad


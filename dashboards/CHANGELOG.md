# 📋 Changelog - AI Dashboards Repository

Todos los cambios notables en este repositorio serán documentados en este archivo.

El formato está basado en [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
y este proyecto adhiere a [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [Unreleased]

### Planificado
- Documentación completa de Calls Dashboard
- Reorganización de Revenue Dashboard
- Creación de WhatsApp Dashboard structure
- Templates reutilizables para nuevos dashboards

---

## [1.0.0] - 2025-12-22

### 🎉 Inicial Release - Estructura del Repositorio

#### Added
- **Estructura del repositorio** completa con carpetas organizadas
- **README.md principal** con índice de todos los dashboards
- **CONTRIBUTING.md** con guías de contribución y estándares
- **CHANGELOG.md** (este archivo) para tracking de cambios

#### Dashboards

**Alerts Dashboard [COMPLETO]:**
- ✅ Documentación técnica completa (`ALERTS_DOCUMENTATION.md`)
- ✅ Resumen ejecutivo para stakeholders (`ALERTS_EXECUTIVE_SUMMARY.md`)
- ✅ 5 alertas automáticas (alert_1 a alert_5)
- ✅ 5 vistas métricas (normal_alert_1 a normal_alert_5)
- ✅ 4 visualizaciones adicionales (view_6 a view_9)
- ✅ Tests y validación incluidos
- ✅ Configuración de Metabase documentada

**Calls Dashboard [PARCIAL]:**
- ⚠️ 11 queries implementadas pero sin documentación completa
- 🔴 Requiere: README.md, DOCUMENTATION.md, EXECUTIVE_SUMMARY.md

**Revenue Dashboard [PENDIENTE]:**
- 🔴 Queries dispersas, necesita reorganización
- 🔴 Crear carpeta `revenue/` y migrar archivos

**WhatsApp Dashboard [PENDIENTE]:**
- 🔴 Query individual, necesita estructura completa
- 🔴 Crear carpeta `whatsapp/` y documentar

---

## Alerts Dashboard - Changelog Detallado

Ver [alerts/CHANGELOG.md](./alerts/CHANGELOG.md) para historial completo del dashboard de alertas.

### Highlights de Alerts v1.0.0:

- **Alert 1:** Hourly Quality Degradation (WoW comparison)
- **Alert 2:** Daily Quality Degradation (Dual baseline: Yesterday + 30D avg)
- **Alert 3:** Daily Volume Drop (Dual baseline: Last week + Same-weekday 30D)
- **Alert 4:** Short Call Rate Spike (Statistical detection with 2σ/3σ thresholds)
- **Alert 5:** Call Duration Anomaly (Bidirectional statistical detection)

**Umbrales estandarizados:**
- 🟢 FINE: ≥ 90% del baseline
- 🟡 WARNING: 70-90% del baseline
- 🔴 CRITICAL: < 70% del baseline
- ⚪ INSUFFICIENT_DATA: Muestra insuficiente (varía por alerta)

---

## [Unreleased] - Próximos Cambios Planeados

### To Do - Q1 2026

#### Alta Prioridad
- [ ] Documentar Calls Dashboard completamente
- [ ] Crear estructura para Revenue Dashboard
- [ ] Crear estructura para WhatsApp Dashboard
- [ ] Implementar templates en `_templates/`

#### Media Prioridad
- [ ] Crear SQL Style Guide en `_shared/`
- [ ] Documentar best practices de Metabase
- [ ] Implementar automated tests para queries críticos
- [ ] Sistema de alertas vía Slack/Email

#### Baja Prioridad
- [ ] Dashboard de Customer Satisfaction
- [ ] Integración con dbt docs
- [ ] Performance benchmarking automático

---

## Tipos de Cambios

- `Added`: Nueva funcionalidad
- `Changed`: Cambios en funcionalidad existente
- `Deprecated`: Funcionalidad que será removida
- `Removed`: Funcionalidad removida
- `Fixed`: Bug fixes
- `Security`: Cambios relacionados con seguridad

---

## Notas para Contribuidores

### Cómo actualizar este CHANGELOG:

1. **Para cambios en un dashboard específico:** Actualiza el CHANGELOG del dashboard
2. **Para cambios en la estructura del repo:** Actualiza este archivo
3. **Para releases:** Marca la versión y fecha
4. **Para breaking changes:** Documenta migración requerida

### Formato de entrada:

```markdown
### [Tipo]
- **Descripción corta**: Explicación detallada de 1-2 líneas
  - Sub-item si es necesario
  - Otro sub-item
```

---

**Última actualización:** 2025-12-22  
**Mantenido por:** AI Data Team - AI Squad


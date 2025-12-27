# 📊 AI Team - Dashboard Repository

> Repositorio centralizado de dashboards, queries y documentación para el equipo de AI

## 🎯 Propósito

Este repositorio contiene todos los dashboards, consultas SQL y documentación relacionada con los productos de IA. Está diseñado para:

- ✅ **Centralizar** toda la lógica de visualización y alertas
- ✅ **Documentar** cada dashboard con contexto técnico y ejecutivo
- ✅ **Facilitar** el onboarding de nuevos miembros del equipo
- ✅ **Mantener** un histórico de cambios y versiones
- ✅ **Estandarizar** la estructura de queries y documentación

---

## 📁 Estructura del Repositorio

```
QUERIES/dashboards/
│
├── README.md                          # Este archivo - Índice principal
├── CONTRIBUTING.md                    # Guía de contribución
├── CHANGELOG.md                       # Histórico de cambios importantes
│
├── alerts/                            # Dashboard de Alertas de Calidad
│   ├── README.md                      # Índice y guía del dashboard
│   ├── ALERTS_DOCUMENTATION.md        # Documentación técnica detallada
│   ├── ALERTS_EXECUTIVE_SUMMARY.md    # Resumen ejecutivo (no técnico)
│   ├── CHANGELOG.md                   # Cambios específicos del dashboard
│   ├── ARCHITECTURE.md                # Arquitectura y dependencias
│   │
│   ├── queries/                       # Queries SQL organizadas
│   │   ├── alerts/                    # Alertas (solo CRITICAL/WARNING)
│   │   │   ├── alert_1_*.sql
│   │   │   ├── alert_2_*.sql
│   │   │   └── ...
│   │   ├── metrics/                   # Vistas métricas (sin filtros)
│   │   │   ├── normal_alert_1.sql
│   │   │   └── ...
│   │   └── visualizations/            # Queries de visualización
│   │       ├── view_6_*.sql
│   │       └── ...
│   │
│   ├── metabase/                      # Configuración específica de Metabase
│   │   ├── METABASE_HEATMAP_SETUP.md
│   │   └── dashboard_config.json      # Exportación de configuración
│   │
│   └── tests/                         # Tests y validación
│       ├── TEST_README.md
│       ├── TEST_alert_logic.sql
│       └── QUICK_CHECK.sql
│
├── calls/                             # Dashboard de Calls (a documentar)
│   ├── README.md
│   └── queries/
│
├── revenue/                           # Dashboard de Revenue (a documentar)
│   ├── README.md
│   └── queries/
│
├── whatsapp/                          # Dashboard de WhatsApp (a documentar)
│   ├── README.md
│   └── queries/
│
├── _templates/                        # Plantillas reutilizables
│   ├── dashboard_README_template.md
│   ├── query_template.sql
│   └── documentation_template.md
│
└── _shared/                           # Recursos compartidos
    ├── sql_style_guide.md
    ├── metabase_best_practices.md
    └── common_queries/
```

---

## 📊 Dashboards Disponibles

### 1. 🚨 [Alerts Dashboard](./alerts/README.md) - **COMPLETO** ✅
**Propósito:** Sistema de alertas automáticas para monitoreo de calidad y volumen de llamadas de IA.

**Estado:** Producción  
**Última actualización:** Diciembre 2025  
**Documentación:**
- [Documentación Técnica](./alerts/ALERTS_DOCUMENTATION.md) - Para desarrolladores
- [Resumen Ejecutivo](./alerts/ALERTS_EXECUTIVE_SUMMARY.md) - Para stakeholders

**Queries principales:**
- 5 alertas automáticas (alert_1 a alert_5)
- 5 vistas métricas (normal_alert_1 a normal_alert_5)
- 4 visualizaciones (view_6 a view_9)

**Owner:** Data Engineering Team  
**Contacto:** [Tu equipo aquí]

---

### 2. 📞 [Calls Dashboard](./calls/README.md) - **POR DOCUMENTAR** 🟡
**Propósito:** Análisis detallado de métricas de llamadas.

**Estado:** Producción  
**Última actualización:** [Fecha]  
**Queries principales:** 11 vistas (view_1 a view_11)

**⚠️ Acción requerida:** Documentar arquitectura y casos de uso

---

### 3. 💰 Revenue Dashboard - **POR ORGANIZAR** 🔴
**Propósito:** Análisis de ingresos generados por llamadas.

**Estado:** [Por definir]  
**Queries principales:** Dispersas en `/dashboads/alr_dshb_revenue*.sql`

**⚠️ Acción requerida:** Crear carpeta `revenue/` y migrar queries

---

### 4. 💬 WhatsApp Dashboard - **POR ORGANIZAR** 🔴
**Propósito:** Métricas de comunicaciones vía WhatsApp.

**Estado:** [Por definir]  
**Queries principales:** `/dashboads/alr_dshb_whatsapp.sql`

**⚠️ Acción requeridad:** Crear carpeta `whatsapp/` y documentar

---

## 🚀 Quick Start

### Para nuevos miembros del equipo:

1. **Lee este README** - Entenderás la estructura general
2. **Explora el [Alerts Dashboard](./alerts/README.md)** - Es el ejemplo mejor documentado
3. **Revisa [CONTRIBUTING.md](./CONTRIBUTING.md)** - Aprende cómo contribuir
4. **Lee [SQL Style Guide](./_shared/sql_style_guide.md)** - Estándares de código

### Para agregar un nuevo dashboard:

1. Crea una carpeta con el nombre del dashboard (ej: `customer_satisfaction/`)
2. Copia la plantilla: `cp _templates/dashboard_README_template.md customer_satisfaction/README.md`
3. Organiza tus queries en subcarpetas: `queries/alerts/`, `queries/metrics/`, etc.
4. Documenta técnicamente en `DOCUMENTATION.md`
5. Crea un resumen ejecutivo en `EXECUTIVE_SUMMARY.md`
6. Agrega entrada en este README
7. Actualiza [CHANGELOG.md](./CHANGELOG.md)

### Para modificar un dashboard existente:

1. Lee la documentación del dashboard (ej: `alerts/README.md`)
2. Haz tus cambios en las queries
3. Actualiza la documentación si es necesario
4. Agrega entrada en `CHANGELOG.md` del dashboard
5. Haz commit con mensaje descriptivo

---

## 📚 Convenciones y Estándares

### Nomenclatura de Archivos

**Queries de Alertas:**
```
alert_[numero]_[nombre_descriptivo].sql
Ejemplo: alert_1_hourly_quality_degradation.sql
```

**Queries de Métricas/Vistas:**
```
[tipo]_[nombre_descriptivo].sql
Ejemplo: normal_alert_1.sql, view_6_hourly_distribution.sql
```

**Documentación:**
```
[TIPO]_[NOMBRE].md (siempre en MAYÚSCULAS)
Ejemplo: DOCUMENTATION.md, README.md, CHANGELOG.md
```

### Estructura de un Query SQL

Todos los queries deben incluir:

```sql
-- ==============================================================================
-- [Nombre del Query]
-- ==============================================================================
-- [Descripción breve del propósito]
-- 
-- Última actualización: [Fecha]
-- Owner: [Tu nombre/equipo]
-- 
-- Dependencias:
-- - Tabla/Vista 1
-- - Tabla/Vista 2
-- 
-- Filtros de Metabase:
-- - {{organization_name}}
-- - {{countries}}
-- ==============================================================================

[Query SQL aquí]
```

### Documentación Requerida por Dashboard

Todo dashboard **DEBE** incluir:

1. ✅ **README.md** - Índice y guía rápida
2. ✅ **DOCUMENTATION.md** - Documentación técnica completa
3. ✅ **EXECUTIVE_SUMMARY.md** - Resumen para stakeholders (opcional pero recomendado)
4. ✅ **CHANGELOG.md** - Histórico de cambios

Opcionalmente puede incluir:
- **ARCHITECTURE.md** - Arquitectura de datos y dependencias
- **METABASE_*.md** - Instrucciones específicas de configuración
- **TEST_*.sql** - Queries de prueba y validación

---

## 🔄 Workflow de Cambios

### 1. Para cambios menores (bug fixes, ajustes):
```bash
1. Modifica el query
2. Prueba en Metabase/SQL editor
3. Actualiza CHANGELOG.md del dashboard
4. Commit: "fix(alerts): correct threshold in alert_2"
```

### 2. Para cambios mayores (nueva feature, refactor):
```bash
1. Crea branch: git checkout -b feature/new-alert-6
2. Implementa cambios
3. Actualiza documentación técnica
4. Actualiza resumen ejecutivo si aplica
5. Agrega entrada detallada en CHANGELOG.md
6. Commit: "feat(alerts): add alert_6 for duration spikes"
7. Pull request para revisión
```

### 3. Para nuevos dashboards:
```bash
1. Crea estructura de carpetas usando plantillas
2. Implementa queries
3. Documenta completamente (README, DOCS, SUMMARY)
4. Agrega entrada en este README principal
5. Actualiza CHANGELOG.md principal
6. Pull request para revisión del equipo
```

---

## 👥 Ownership y Responsabilidades

| Dashboard | Owner | Backup | Última Revisión |
|-----------|-------|--------|-----------------|
| Alerts | Data Engineering Team | [Backup] | Dic 2025 |
| Calls | [Por asignar] | [Por asignar] | [Fecha] |
| Revenue | [Por asignar] | [Por asignar] | [Fecha] |
| WhatsApp | [Por asignar] | [Por asignar] | [Fecha] |

**Responsabilidades del Owner:**
- ✅ Mantener documentación actualizada
- ✅ Revisar y aprobar cambios
- ✅ Responder preguntas del equipo
- ✅ Revisar métricas y alertas regularmente
- ✅ Coordinar con stakeholders

---

## 🔗 Links Útiles

### Documentación Externa
- [Metabase Docs](https://www.metabase.com/docs/)
- [StarRocks SQL Reference](https://docs.starrocks.io/docs/sql-reference/sql-statements/table_bucket_part_index/CREATE_TABLE/)
- [dbt Best Practices](https://docs.getdbt.com/guides/best-practices)

### Recursos Internos
- [Wiki del Equipo de AI](#) - Documentación general
- [Confluence - AI Dashboards](#) - Decisiones de arquitectura
- [Jira - Dashboard Tasks](#) - Backlog y roadmap
- [Slack #ai-data-team](#) - Canal del equipo

### Herramientas
- [Metabase - Production](https://metabase.yourcompany.com)
- [Metabase - Staging](https://metabase-staging.yourcompany.com)
- [StarRocks Console](https://starrocks.yourcompany.com)

---

## 📈 Roadmap

### Q1 2025 ✅ COMPLETADO
- [x] Documentación completa de Alerts Dashboard
- [x] Separación de alertas (alert_*) y métricas (normal_alert_*)
- [x] Implementación de detección estadística (Alert 4 y 5)
- [x] Resumen ejecutivo para stakeholders

### Q2 2025 🎯 EN PROGRESO
- [ ] Documentar Calls Dashboard
- [ ] Reorganizar Revenue Dashboard
- [ ] Crear estructura para WhatsApp Dashboard
- [ ] Implementar templates reutilizables

### Q3 2025 📋 PLANIFICADO
- [ ] Sistema de alertas vía Slack/Email
- [ ] Dashboard de Customer Satisfaction
- [ ] Integración con dbt para queries
- [ ] Automated testing para queries críticos

---

## 🆘 Soporte y Contacto

### ¿Tienes preguntas?

1. **Sobre un dashboard específico:** Revisa su README y documentación
2. **Sobre la estructura:** Lee este README y [CONTRIBUTING.md](./CONTRIBUTING.md)
3. **Técnicas/bugs:** Abre un issue en el repositorio o contacta al owner del dashboard
4. **Urgente:** Contacta a Data Engineering Team en Slack #ai-data-team

### Contribuir

¿Encontraste un bug? ¿Tienes una mejora?  
Lee nuestra [Guía de Contribución](./CONTRIBUTING.md) y ¡envía un PR!

---

**Última actualización:** Diciembre 2025  
**Versión del repositorio:** 1.0  
**Mantenido por:** Data Engineering Team - AI Squad


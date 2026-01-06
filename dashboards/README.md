# 📊 AI Team - Dashboard Repository

> Repositorio centralizado de dashboards, queries y documentación para el equipo de AI

---

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
dashboards/
│
├── README.md                          # Este archivo - Índice principal
├── CONTRIBUTING.md                    # Guía de contribución
├── CHANGELOG.md                       # Histórico de cambios importantes
│
├── alerts/                            # Dashboard de Alertas ✅
│   ├── README.md
│   ├── ALERTS_TECHNICAL_DOCUMENTATION.md
│   ├── ALERTS_EXECUTIVE_SUMMARY.md
│   └── queries/
│       ├── charts/
│       ├── alerts/
│       │   └── sub_alerts/
│       └── metrics/
│           ├── current_summary/
│           └── hourly_summary/
│
└── revenue/                           # Dashboard de Revenue ✅
    ├── README.md
    ├── REVENUE_TECHNICAL_DOCUMENTATION.md
    └── queries/
        ├── current_month/
        └── tot_insights/
```

---

## 📊 Dashboards Disponibles

### 1. 🚨 [Alerts Dashboard](./alerts/README.md) — ✅ COMPLETO

**Propósito:** Sistema de alertas automáticas para monitoreo de calidad y volumen de llamadas de IA.

| Atributo | Valor |
|----------|-------|
| **Estado** | Producción |
| **Última actualización** | Diciembre 2025 |
| **Owner** | AI Data Team - AI Squad |

**Documentación:**
- [README](./alerts/README.md) — Índice y guía rápida
- [Documentación Técnica](./alerts/ALERTS_TECHNICAL_DOCUMENTATION.md) — Para desarrolladores
- [Resumen Ejecutivo](./alerts/ALERTS_EXECUTIVE_SUMMARY.md) — Para stakeholders

**Contenido:**
- 5 alertas principales con 15 sub-alertas
- 3 tabs: Charts, Alerts, Metrics
- Sistema de consenso para reducir falsos positivos

---

### 2. 💰 [Revenue Dashboard](./revenue/README.md) — ✅ COMPLETO

**Propósito:** Análisis de ingresos generados por NOVA (llamadas y WhatsApp) con comparaciones temporales.

| Atributo | Valor |
|----------|-------|
| **Estado** | Producción |
| **Última actualización** | Enero 2026 |
| **Owner** | AI Data Team - AI Squad |

**Documentación:**
- [README](./revenue/README.md) — Índice y guía rápida
- [Documentación Técnica](./revenue/REVENUE_TECHNICAL_DOCUMENTATION.md) — Para desarrolladores

**Contenido:**
- 17 queries organizadas en 2 tabs
- Tab 1: Current Month (KPIs, comparaciones, breakdowns)
- Tab 2: Tot Insights (análisis histórico)
- Billability configurable por organización

---

## 🚧 Dashboards en Desarrollo

> ⚠️ **Los siguientes dashboards están en proceso de desarrollo y NO se encuentran actualmente en este repositorio.**

| Dashboard | Descripción | Estado | ETA |
|-----------|-------------|--------|-----|
| 📞 **Calls Dashboard** | Análisis detallado de métricas de llamadas | 🔨 En desarrollo | Q1 2026 |
| 💬 **WhatsApp Dashboard** | Métricas de comunicaciones vía WhatsApp | 🔨 En desarrollo | Q1 2026 |
| 🤖 **Aida Dashboard** | Dashboard del agente Aida | 📋 Planificado | Q1 2026 |
| 🤖 **Roberto Dashboard** | Dashboard del agente Roberto | 📋 Planificado | Q1 2026 |

Una vez completados, estos dashboards serán agregados al repositorio siguiendo la estructura estándar definida en [CONTRIBUTING.md](./CONTRIBUTING.md).

---

## 🚀 Quick Start

### Para nuevos miembros del equipo:

1. **Lee este README** — Entenderás la estructura general
2. **Explora el [Alerts Dashboard](./alerts/README.md)** — Es el ejemplo mejor documentado
3. **Revisa [CONTRIBUTING.md](./CONTRIBUTING.md)** — Aprende cómo contribuir

### Para consultar un dashboard existente:

1. Navega a la carpeta del dashboard (`alerts/` o `revenue/`)
2. Lee el `README.md` para una visión general
3. Consulta la documentación técnica para detalles de implementación
4. Revisa las queries en la subcarpeta `queries/`

### Para agregar un nuevo dashboard:

1. Crea una carpeta con el nombre del dashboard
2. Incluye como mínimo:
   - `README.md` — Índice y guía rápida
   - `*_TECHNICAL_DOCUMENTATION.md` — Documentación técnica
   - `queries/` — Carpeta con las queries SQL organizadas
3. Actualiza este README principal
4. Actualiza [CHANGELOG.md](./CHANGELOG.md)

---

## 👥 Ownership y Responsabilidades

| Dashboard | Owner | Estado | Última Revisión |
|-----------|-------|--------|-----------------|
| Alerts | AI Data Team - AI Squad | ✅ Completo | Dic 2025 |
| Revenue | AI Data Team - AI Squad | ✅ Completo | Ene 2026 |
| Calls | AI Data Team - AI Squad | 🔨 En desarrollo | — |
| WhatsApp | AI Data Team - AI Squad | 🔨 En desarrollo | — |
| Aida | AI Data Team - AI Squad | 📋 Planificado | — |
| Roberto | AI Data Team - AI Squad | 📋 Planificado | — |

**Responsabilidades del Owner:**
- ✅ Mantener documentación actualizada
- ✅ Revisar y aprobar cambios
- ✅ Responder preguntas del equipo
- ✅ Coordinar con stakeholders

---

## 🔗 Links Útiles

### Recursos Internos
- [CONTRIBUTING.md](./CONTRIBUTING.md) — Guía de contribución
- [CHANGELOG.md](./CHANGELOG.md) — Histórico de cambios

### Herramientas
- Metabase — Visualización de dashboards
- StarRocks — Base de datos analítica
- dbt — Transformación de datos

---

## 🆘 Soporte y Contacto

### ¿Tienes preguntas?

1. **Sobre un dashboard específico:** Revisa su README y documentación técnica
2. **Sobre la estructura del repo:** Lee este README y [CONTRIBUTING.md](./CONTRIBUTING.md)
3. **Bugs o mejoras:** Abre un issue en el repositorio
4. **Urgente:** Contacta al equipo en Slack `#ai-data-team`

### Contribuir

¿Encontraste un error? ¿Tienes una mejora? Lee [CONTRIBUTING.md](./CONTRIBUTING.md) para saber cómo contribuir.

---

**Última actualización:** Enero 2026  
**Versión:** 1.1  
**Mantenido por:** AI Data Team - AI Squad

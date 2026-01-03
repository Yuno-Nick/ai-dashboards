# 💰 Revenue Dashboard

> **Versión:** 1.1  
> **Última actualización:** Enero 2026  
> **Owner:** Data Engineering Team - AI Squad  
> **Estado:** ✅ Producción

---

## 🎯 Propósito

El Revenue Dashboard proporciona una vista completa de los ingresos generados por NOVA, el agente de IA para recuperación de pagos. Permite analizar el revenue por múltiples dimensiones temporales y organizacionales.

### ¿Qué Responde Este Dashboard?

| Pregunta de Negocio | Sección/Query |
|---------------------|---------------|
| ¿Cuánto revenue hemos generado este mes? | Current Month → MTD Revenue |
| ¿Cómo vamos vs el mes anterior? | Current Month → MoM Rate |
| ¿Cuál es el revenue por organización? | Current Month → Revenue All Orgs |
| ¿Qué producto genera más revenue? | Current Month → Calls vs WhatsApp |
| ¿Cuál es la tendencia histórica? | Tot Insights → Monthly/Quarterly |

---

## 📁 Estructura de Archivos

```
dashboards/revenue/
│
├── README.md                              # Este archivo
├── REVENUE_TECHNICAL_DOCUMENTATION.md     # Documentación técnica completa
│
└── queries/
    │
    ├── tot_insights/                      # Análisis histórico completo
    │   ├── 1_total_revenue.sql            # Revenue total (con filtro de fecha)
    │   ├── 2_daily_revenue_chart.sql      # Tendencia diaria
    │   ├── 3_monthly_revenue.sql          # Revenue mensual + MoM %
    │   ├── 4_quarterly_revenue.sql        # Revenue trimestral + QoQ %
    │   └── 5_weekly_revenue.sql           # Revenue semanal + WoW %
    │
    └── current_month/                     # Métricas del mes actual
        ├── 1_month_to_date_revenue.sql    # Revenue MTD
        ├── 2_month_to_date_communication.sql  # Comunicaciones MTD
        ├── 3_communication_billable_rate.sql  # Tasa facturable %
        ├── 4_year_over_year_rate.sql      # YoY %
        ├── 5_month_over_month_rate.sql    # MoM % (to-date comparison)
        ├── 6_quarter_over_quarter.sql     # QoQ % (to-date comparison)
        ├── 7_mom_trend_chart.sql          # Tendencia MoM por día
        ├── 8_qoq_trend_chart.sql          # Tendencia QoQ por día
        ├── 9_revenue_all_organization.sql # Breakdown por organización
        ├── 10_calls_quality_count.sql     # Calls por clasificación
        ├── 11_calls_vs_whatsapp.sql       # Comparativo de productos
        └── 12_general_product_chart.sql   # Resumen general por producto
```

---

## 📊 Estructura del Dashboard (2 Tabs)

### Tab 1: Current Month (Mes Actual)

**Propósito:** Vista ejecutiva del rendimiento del mes en curso con comparaciones temporales.

| Sección | Queries | Descripción |
|---------|---------|-------------|
| **KPIs Principales** | 1, 2, 3 | Revenue MTD, Comunicaciones, Tasa Facturable |
| **Comparaciones Temporales** | 4, 5, 6 | YoY %, MoM %, QoQ % |
| **Tendencias** | 7, 8 | Gráficos de progreso vs períodos anteriores |
| **Breakdowns** | 9, 10, 11, 12 | Por organización, clasificación, producto |

### Tab 2: Tot Insights (Histórico Completo)

**Propósito:** Análisis histórico con filtros de fecha flexibles.

| Query | Métrica | Granularidad |
|-------|---------|--------------|
| 1_total_revenue | Revenue total | Agregado |
| 2_daily_revenue_chart | Revenue + Comunicaciones | Diaria |
| 3_monthly_revenue | Revenue + MoM % | Mensual |
| 4_quarterly_revenue | Revenue + QoQ % | Trimestral |
| 5_weekly_revenue | Revenue + WoW % | Semanal |

---

## 🔧 Fuente de Datos

### Tabla Principal

```
ai_revenue_mart (Materialized View)
├── Refresh: ASYNC cada 5 minutos
├── Granularidad: 1 fila por comunicación (llamada o mensaje WhatsApp)
└── Fuentes upstream:
    ├── ai_calls_detail      # Detalle de llamadas
    ├── ai_messages_detail   # Detalle de WhatsApp
    └── nova_costs (seed)    # Pricing + reglas de billability
```

### Modelo de Pricing

| Producto | Tipo de Cobro | Fórmula |
|----------|---------------|---------|
| **PHONE_CALL** | Por minuto | `minutes × unit_cost` |
| **WHATSAPP_MESSAGE** | Conversación + Mensajes | `conversation_cost + (messages × unit_cost)` |

### Billability Configurable por Organización

La tabla `nova_costs` define qué clasificaciones de llamadas son facturables para cada organización:

| Flag | Descripción | Ejemplo |
|------|-------------|---------|
| `bill_good_calls` | Cobra por llamadas good_calls | Rappi: ✅ |
| `bill_short_calls` | Cobra por llamadas short_calls | Rappi: ❌, Intcomex: ✅ |
| `bill_completed` | Cobra por llamadas completed | Rappi: ❌, Intcomex: ✅ |

---

## 🎛️ Filtros Disponibles

Todos los queries soportan los siguientes filtros de Metabase:

| Filtro | Variable | Descripción |
|--------|----------|-------------|
| Fecha | `{{revenue_date}}` | Rango de fechas (solo en tot_insights) |
| Organización | `{{organization_name}}` | Filtrar por merchant |
| País | `{{country}}` | Filtrar por país (AR, BR, PE, MX, CO, CL) |
| Producto | `{{product}}` | PHONE_CALL o WHATSAPP_MESSAGE |

---

## 📈 Métricas Clave

### Clasificaciones de Llamadas

| Clasificación | Descripción | Billable por defecto |
|---------------|-------------|----------------------|
| `good_calls` | Llamada completada, transcripción ≥1000 chars, sin voicemail | Configurable |
| `short_calls` | Llamada completada, transcripción <1000 chars | Configurable |
| `completed` | Llamada completada sin transcripción válida | Configurable |
| `voicemail` | Fue a buzón de voz | ❌ No |
| `failed` | Llamada fallida | ❌ No |
| `no-answer` | No contestaron | ❌ No |

### Organizaciones Activas

| Organización | Países | Productos | Billability |
|--------------|--------|-----------|-------------|
| Rappi | AR, BR, PE, CL, CO, MX | PHONE_CALL, WHATSAPP | Solo good_calls |
| Intcomex | MX | PHONE_CALL | good + short + completed |
| Viva Aerobus | CO | PHONE_CALL | good + short |
| ZigFun | BR | WHATSAPP | Todos los mensajes |
| Peru Rail | PE | WHATSAPP | Solo conversación |

---

## 🚀 Quick Start

### Para analizar el revenue del mes actual:

1. Ir a **Tab 1: Current Month**
2. Revisar KPIs principales (Revenue MTD, MoM %)
3. Filtrar por organización si se requiere detalle
4. Usar gráficos de tendencia para ver progreso diario

### Para análisis histórico:

1. Ir a **Tab 2: Tot Insights**
2. Seleccionar rango de fechas con `{{revenue_date}}`
3. Elegir granularidad: Daily, Weekly, Monthly, Quarterly
4. Aplicar filtros de organización/país según necesidad

---

## 🔗 Documentación Relacionada

- [Documentación Técnica Completa](./REVENUE_TECHNICAL_DOCUMENTATION.md)
- [Alerts Dashboard](../alerts/README.md)
- [Guía de Contribución](../CONTRIBUTING.md)

---

## 📝 Changelog

| Versión | Fecha | Cambios |
|---------|-------|---------|
| 1.1 | Enero 2026 | Actualización con billability configurable por organización, nuevo modelo ai_messages_detail |
| 1.0 | Enero 2026 | Release inicial con 17 queries organizadas en 2 tabs |

---

## 🆘 Soporte

**¿Preguntas sobre este dashboard?**

1. Revisa la [Documentación Técnica](./REVENUE_TECHNICAL_DOCUMENTATION.md)
2. Contacta al equipo en Slack: `#ai-data-team`
3. Abre un issue en el repositorio

---

**Mantenido por:** Data Engineering Team - AI Squad

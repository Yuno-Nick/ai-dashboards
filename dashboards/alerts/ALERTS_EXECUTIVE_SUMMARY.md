# 📊 Guía Ejecutiva de Alertas - AI Calls Dashboard

## 🎯 Objetivo del Sistema de Alertas

Este sistema monitorea automáticamente la calidad y volumen de las llamadas de IA, alertándote cuando algo no está funcionando correctamente. Piensa en ello como un **sistema de alarma temprana** que te avisa antes de que los problemas se conviertan en crisis.

---

## 📞 ¿Cómo Medimos la Calidad de las Llamadas?

Antes de entender las alertas, es importante entender **qué significa "calidad"** en nuestro sistema.

### 🎭 Los 5 Tipos de Llamadas

Cada llamada se clasifica automáticamente en uno de estos 5 tipos:

#### 1. ✅ **Good Calls (Llamadas Buenas)** - ¡Esto es lo que queremos!

**Criterios:**
- ✅ Llamada se completó exitosamente
- ✅ Conversación sustancial (≥1000 caracteres en transcripción ≈ 150-200 palabras)
- ✅ **NO** fue un buzón de voz

**Ejemplo:**
```
Usuario: "Hola, llamo porque tengo un pago pendiente"
Bot: "Entiendo, déjame ayudarte. ¿Podrías confirmar tu número de documento?"
Usuario: "Sí, es 12345678"
Bot: "Perfecto, veo tu cuenta. Tienes un saldo de $150..."
[... conversación continúa ...]
Duración: 2.5 minutos
Transcripción: 1,200 caracteres
✅ Clasificación: GOOD CALL
```

---

#### 2. 🟡 **Short Calls (Llamadas Cortas)** - Conectó pero fue muy breve

**Criterios:**
- ⚠️ Llamada se completó
- ⚠️ Conversación muy breve (<1000 caracteres)
- ⚠️ Usuario probablemente colgó rápido

**Ejemplo:**
```
Usuario: "¿Quién habla?"
Bot: "Hola, soy el asistente virtual de Yuno"
Usuario: "No me interesa" *cuelga*
Duración: 15 segundos
Transcripción: 180 caracteres
🟡 Clasificación: SHORT CALL
```

**¿Por qué pasan?**
- Usuario confundido o frustrado
- Problemas de audio/conexión
- Usuario ocupado y no puede hablar
- Bot no entendió bien al inicio

---

#### 3. 🔴 **Voicemail (Buzones de Voz)** - Máquina contestó, no persona

**Criterios:**
- 📞 Llamada técnicamente "completada"
- 🤖 Pero conectó con un contestador automático
- 🔍 Se detecta por keywords en la transcripción

**Keywords que detectamos:**
- "Presiona la tecla numeral"
- "Grabe su mensaje después del tono"
- "Buzón de voz"
- "Contestador"
- "Por favor deja tu mensaje"

**Ejemplo:**
```
Contestador: "Ha llamado al 555-1234. Por favor grabe su mensaje 
después del tono. Para finalizar, presione numeral"
[Bot deja mensaje]
🔴 Clasificación: VOICEMAIL
```

**Importante:** Los voicemails **NO se incluyen** en el cálculo de calidad porque no son conversaciones reales.

---

#### 4. ❌ **Failed Calls (Llamadas Fallidas)** - No conectó

**Criterios:**
- ❌ Llamada no se completó
- ❌ No hubo conexión

**Ejemplos:**
- "Busy" - Línea ocupada
- "No-answer" - Nadie contestó
- "Declined" - Usuario rechazó la llamada
- "Failed" - Error técnico

**Importante:** Las llamadas fallidas **NO se incluyen** en el cálculo de calidad porque nunca hubo oportunidad de conversación.

---

#### 5. ⚪ **Completed (Sin datos)** - Edge case raro

**Criterios:**
- ⚪ Estado técnico "completed"
- ⚪ Pero sin transcripción o datos insuficientes

**Nota:** Este caso es muy raro y generalmente indica un problema técnico de logging.

---

### 🎯 La Fórmula de Calidad (Quality Rate)

**Fórmula simple:**

```
Quality Rate = Good Calls ÷ Completed Calls

Donde:
Completed Calls = Good Calls + Short Calls + Completed (sin voicemail ni failed)
```

**¿Por qué excluimos voicemail y failed?**
- **Voicemail:** No es una conversación real con humano
- **Failed:** Nunca hubo oportunidad de conversación

Solo medimos calidad sobre llamadas que **tuvieron chance de ser buenas**.

---

### 📊 Ejemplo Práctico Completo

Imaginemos un día típico con 200 llamadas:

| Tipo | Cantidad | ¿Cuenta para calidad? |
|------|----------|----------------------|
| ✅ Good Calls | **80** | ✅ SÍ (numerador) |
| 🟡 Short Calls | **15** | ✅ SÍ (denominador) |
| ⚪ Completed | **5** | ✅ SÍ (denominador) |
| 🔴 Voicemail | **50** | ❌ NO |
| ❌ Failed | **50** | ❌ NO |
| **Total** | **200** | |

**Cálculo de Quality Rate:**
```
Completed Calls = 80 + 15 + 5 = 100 llamadas
Quality Rate = 80 ÷ 100 = 0.80 (80%)
```

**Interpretación:**
> "De cada 100 llamadas que conectaron con personas, 80 fueron conversaciones exitosas"

---

### 🎨 Visualización Simple

```
📞 200 Llamadas Totales
│
├─ 100 Llamadas que NO cuentan para calidad
│  ├─ 50 Voicemails 🔴 (máquinas)
│  └─ 50 Failed ❌ (no conectaron)
│
└─ 100 Llamadas que SÍ cuentan para calidad
   ├─ 80 Good Calls ✅ (80% calidad) ← ¡Lo que queremos maximizar!
   ├─ 15 Short Calls 🟡 (15%)
   └─ 5 Completed ⚪ (5%)

📊 Quality Rate = 80% ✅
```

---

### 🎯 Metas de Calidad

**Benchmarks típicos:**
- 🟢 **Excelente:** >85% quality rate
- 🟡 **Aceptable:** 70-85% quality rate
- 🔴 **Problema:** <70% quality rate

**¿Por qué 80-85% es realista?**
- Siempre habrá usuarios que cuelgan rápido
- Problemas ocasionales de red son normales
- No todos los usuarios están disponibles para hablar largamente

---

### 💡 Lo Que las Alertas Monitorean

Ahora que entiendes cómo se mide la calidad, las alertas te avisan cuando:

1. **Alertas 1 & 2:** Tu quality rate (good_calls ÷ completed_calls) **cae** significativamente
2. **Alert 3:** El volumen total de llamadas **cae** significativamente
3. **Alert 4:** El porcentaje de short_calls **aumenta** anormalmente
4. **Alert 5:** La duración promedio de las llamadas es **anormal** (muy corta o muy larga)

---

## 🚨 Las 5 Alertas Principales

### 1️⃣ Alert 1: "La Calidad de Esta Hora Cayó Respecto a la Semana Pasada"

**¿Qué monitorea?**  
Compara la calidad de las llamadas de **esta hora** con la **misma hora de la semana pasada**.

**Ejemplo práctico:**
```
🕐 Hoy Lunes 5:00 PM:
   - 150 llamadas completadas
   - 120 fueron buenas (80% de calidad)

🕐 Lunes pasado 5:00 PM:
   - 170 llamadas completadas
   - 160 fueron buenas (94% de calidad)

📉 Resultado: 80% ÷ 94% = 85% (caída del 15%)
```

**Interpretación:**
- 🟢 **FINE:** Si la calidad de hoy es al menos 90% de la semana pasada → Todo bien
- 🟡 **WARNING:** Si cae entre 70-90% → Algo está pasando, revisa
- 🔴 **CRITICAL:** Si cae por debajo del 70% → ¡Problema serio! Investiga ya

**¿Por qué es útil?**  
Detecta problemas que ocurren a la misma hora cada semana (ej: actualizaciones, picos de tráfico).

---

### 2️⃣ Alert 2: "La Calidad de Hoy Es Peor que Ayer Y Que el Promedio del Mes"

**¿Qué monitorea?**  
Valida que la calidad de hoy sea consistentemente baja comparando con **DOS referencias**:
- Ayer mismo momento
- Promedio de los últimos 30 días

**Ejemplo práctico:**
```
📅 Hoy Martes hasta 3:00 PM:
   - 380 llamadas completadas
   - 300 fueron buenas (79% de calidad)

📅 Ayer Lunes hasta 3:00 PM:
   - 400 llamadas completadas
   - 360 fueron buenas (90% de calidad)

📊 Promedio últimos 30 días hasta 3:00 PM:
   - 88% de calidad promedio

📉 Resultado:
   - Hoy vs Ayer: 79% ÷ 90% = 88% (caída del 12%)
   - Hoy vs Promedio: 79% ÷ 88% = 90% (caída del 10%)
```

**Interpretación:**
- 🟢 **FINE:** Si está bien en al menos uno de los dos → Puede ser variabilidad normal
- 🟡 **WARNING:** Si cae 10-30% en **AMBOS** → Problema confirmado
- 🔴 **CRITICAL:** Si cae más del 30% en **AMBOS** → ¡Emergencia!

**¿Por qué usa DOS comparaciones?**  
Para evitar falsas alarmas. Si solo cae respecto a ayer, podría ser que ayer fue un día excepcional. Si cae en ambas comparaciones, el problema es real.

---

### 3️⃣ Alert 3: "El Volumen de Llamadas de Hoy Es Muy Bajo"

**¿Qué monitorea?**  
Compara el número de llamadas de hoy con **DOS referencias**:
- Mismo día de la semana pasada
- Promedio de los últimos Lunes/Martes/etc. (depende del día actual)

**Ejemplo práctico:**
```
📞 Hoy Lunes hasta 5:00 PM:
   - 181 llamadas

📞 Lunes pasado hasta 5:00 PM:
   - 204 llamadas

📊 Promedio de los últimos 4 Lunes hasta 5:00 PM:
   - 218 llamadas

📉 Resultado:
   - Hoy vs Semana Pasada: 181 ÷ 204 = 89% (caída del 11%)
   - Hoy vs Promedio Lunes: 181 ÷ 218 = 83% (caída del 17%)
```

**Interpretación:**
- 🟢 **FINE:** Al menos uno de los dos está bien → Variación normal
- 🟡 **WARNING:** Ambos caen 10-30% → Problema de volumen detectado
- 🔴 **CRITICAL:** Ambos caen más del 30% → ¡Caída severa!

**¿Por qué compara con el mismo día de la semana?**  
Porque los Lunes suelen tener más volumen que los Viernes. Compara "manzanas con manzanas".

**Posibles causas:**
- ❌ Problema técnico (servidor caído, integración rota)
- ❌ Problema de negocio (campaña terminó, clientes sin servicio)
- ❌ Problema con proveedores de telefonía

---

## 🎯 Alertas Avanzadas (4 y 5): Detección Inteligente de Anomalías

Las alertas 4 y 5 son diferentes: **aprenden del comportamiento histórico** y detectan cuando algo está "fuera de lo normal" usando matemáticas, no solo comparaciones simples.

---

### 4️⃣ Alert 4: "Hay Demasiadas Llamadas Cortas (Spike)" 🚀

**¿Qué monitorea?**  
Detecta cuando el porcentaje de llamadas cortas aumenta **anormalmente** respecto al patrón histórico de esa misma hora.

**¿Qué es una "llamada corta"?**  
Llamadas que se completan pero duran muy poco tiempo (ej: <30 segundos). Suelen indicar problemas de calidad, conexión, o usuarios frustrados que cuelgan rápido.

**Cómo funciona (simplificado):**

Imagina que tienes un termómetro que mide "cuántas llamadas cortas tienes":
- **Línea base (promedio histórico):** 12% de llamadas son cortas a las 4 PM
- **Rango normal:** Entre 8% y 16% (el termómetro tiene un margen)
- **Alerta:** Si el termómetro sube por encima de 16%, algo anormal está pasando

**Ejemplo práctico:**

```
🕐 Hoy Miércoles 4:00 PM:
   - 180 llamadas completadas
   - 40 fueron llamadas cortas (22.2%)

📊 Histórico de los últimos 30 días a las 4 PM:
   - Promedio: 12% de llamadas cortas
   - Rango normal: 8% - 16%
   - Percentil 95: 18%

🔍 Análisis:
   22.2% vs 12% promedio = +10.2 puntos porcentuales
   Esto es 2.5 veces la desviación estándar (2.5σ)
```

**Interpretación:**
- 🟢 **FINE:** Entre 8-16% → Normal, dentro del patrón histórico
- 🟡 **WARNING:** 16-20% → Anomalía detectada (2 desviaciones estándar)
- 🔴 **CRITICAL:** >20% → Anomalía extrema (3 desviaciones estándar)

**¿Qué significa "2.5σ" en lenguaje simple?**

Piensa en σ (sigma) como una **medida de qué tan raro es algo**:
- **1σ:** Sucede ~32% del tiempo (bastante común)
- **2σ:** Sucede ~5% del tiempo (poco común, merece atención)
- **3σ:** Sucede ~0.3% del tiempo (extremadamente raro, ¡alerta roja!)

Si estás en 2.5σ, significa que lo que está pasando hoy **sucede menos del 1% del tiempo históricamente**. Es estadísticamente raro.

**Analogía del mundo real:**

Imagina que mides la temperatura de tu casa todos los días a las 4 PM:
- Promedio: 22°C
- Rango normal: 20°C - 24°C
- Hoy marca 28°C ← ¡Eso es muy raro! Algo pasó (ventana abierta, calefacción rota, etc.)

Lo mismo pasa con las llamadas cortas: si están muy por encima de lo normal, **algo cambió**.

**Posibles causas de un spike de llamadas cortas:**
- 🔥 **Problemas técnicos:** Calidad de audio mala, desconexiones frecuentes
- 🔥 **Problemas de red:** Latencia alta, pérdida de paquetes
- 🔥 **Cambios en el bot:** Nueva versión con bugs, flujo confuso
- 🔥 **Problemas externos:** Proveedor de telefonía con issues

**Valor para el negocio:**

En lugar de decir "hoy tenemos 22% de llamadas cortas vs 12% promedio", la alerta te dice:
> "Esto es 2.5 sigma, sucede menos del 1% del tiempo. ¡Algo definitivamente cambió!"

---

### 5️⃣ Alert 5: "La Duración de las Llamadas Es Anormal" ⏱️

**¿Qué monitorea?**  
Detecta cuando las llamadas duran **mucho más** o **mucho menos** de lo normal para esa hora del día.

**¿Por qué es importante?**

- **Llamadas muy cortas:** Usuarios frustrados, problemas técnicos, bot confuso
- **Llamadas muy largas:** Bot en loop, casos no manejados, usuarios perdidos

**Cómo funciona (simplificado):**

Piensa en un cronómetro que mide cuánto dura cada llamada en promedio:
- **Promedio histórico:** 3 minutos (180 segundos) a las 10 AM
- **Rango normal:** 2.4 - 3.6 minutos (con margen de ±35 segundos)
- **Alerta:** Si el cronómetro marca fuera de ese rango, algo anormal está pasando

**Diferencia clave con Alert 4:**

Alert 5 es **bidireccional** - detecta problemas en **AMBAS direcciones**:
- ⬇️ **TOO_SHORT:** Llamadas anormalmente cortas
- ⬆️ **TOO_LONG:** Llamadas anormalmente largas

**Ejemplo práctico 1: Llamadas TOO_SHORT**

```
🕐 Hoy Jueves 10:00 AM:
   - 130 llamadas completadas
   - Duración promedio: 87 segundos (~1.4 minutos)

📊 Histórico de los últimos 30 días a las 10 AM:
   - Promedio: 180 segundos (3 minutos)
   - Rango normal: 110 - 250 segundos
   - Desviación estándar: 35 segundos

🔍 Análisis:
   87 segundos vs 180 promedio = -93 segundos de diferencia
   Esto es -2.67 desviaciones estándar (-2.67σ)
```

**Interpretación:**
- 🟢 **FINE:** 110-250 segundos → Normal
- 🟡 **WARNING:** <110 o >250 segundos → Anomalía detectada
- 🔴 **CRITICAL:** <75 o >285 segundos → Anomalía extrema

**¿Qué significa este resultado?**

Hoy las llamadas están durando **-2.67σ menos** que lo normal. En lenguaje simple:
> "Las llamadas de hoy son tan cortas que esto sucede menos del 1% del tiempo históricamente"

**Posibles causas de llamadas TOO_SHORT:**
- 🔥 **Problemas de calidad:** Audio malo, desconexiones
- 🔥 **Bot no funciona bien:** Usuarios cuelgan rápido por frustración
- 🔥 **Problemas de red:** Llamadas se caen antes de tiempo
- 🔥 **Cambio en el flujo:** Nueva versión del bot tiene bugs

**Ejemplo práctico 2: Llamadas TOO_LONG**

```
🕐 Hoy Viernes 2:00 PM:
   - 170 llamadas completadas
   - Duración promedio: 260 segundos (~4.3 minutos)

📊 Histórico de los últimos 30 días a las 2 PM:
   - Promedio: 170 segundos (~2.8 minutos)
   - Rango normal: 114 - 226 segundos
   - Desviación estándar: 28 segundos

🔍 Análisis:
   260 segundos vs 170 promedio = +90 segundos de diferencia
   Esto es +3.21 desviaciones estándar (+3.21σ)
```

**Interpretación:**
- 🔴 **CRITICAL:** +3.21σ por encima del promedio → Anomalía extrema

**¿Qué significa este resultado?**

Las llamadas están durando **+3.21σ más** que lo normal. En lenguaje simple:
> "Las llamadas de hoy son tan largas que esto sucede menos del 0.3% del tiempo. ¡Algo definitivamente está mal!"

**Posibles causas de llamadas TOO_LONG:**
- 🔥 **Bot en loop infinito:** Se repite sin poder avanzar
- 🔥 **Casos no manejados:** Usuario queda atrapado sin salida
- 🔥 **Lógica de finalización rota:** Bot no sabe cuándo terminar
- 🔥 **Consultas muy complejas:** Usuarios con problemas difíciles de resolver

---

## 🎯 Analogía Simple: Sistema de Alertas como un Doctor

Piensa en las 5 alertas como **diferentes tipos de chequeos médicos**:

### Alertas 1, 2, 3: "Chequeo de Rutina" 🩺
- Comparan tu estado actual con referencias conocidas
- "Tu presión está más alta que la semana pasada"
- "Tu temperatura es más baja que ayer Y que tu promedio"
- **Fáciles de entender:** Comparaciones directas

### Alertas 4, 5: "Análisis de Laboratorio Avanzado" 🔬
- Analizan patrones complejos en tus resultados
- "Tus glóbulos blancos están 2.5σ por encima de tu rango personal histórico"
- "Tu nivel de glucosa está en el percentil 95 de tu distribución"
- **Más sofisticadas:** Usan estadísticas para detectar anomalías sutiles

**¿Por qué necesitas ambos tipos?**

- **Alertas simples (1,2,3):** Detectan cambios obvios y rápidos
- **Alertas estadísticas (4,5):** Detectan anomalías sutiles que las alertas simples podrían perder

---

## 📊 Tabla Comparativa Rápida

| Alerta | ¿Qué Mide? | Método | ¿Cuándo Alerta? | Mejor Para |
|--------|------------|--------|-----------------|------------|
| **1** | Calidad horaria | Comparación simple vs semana pasada | Caída >10% | Problemas recurrentes semanales |
| **2** | Calidad diaria | Doble validación (ayer + promedio) | Caída >10% en AMBOS | Problemas de calidad persistentes |
| **3** | Volumen diario | Doble validación (semana + promedio) | Caída >10% en AMBOS | Caídas de tráfico |
| **4** | Short calls | Detección estadística (sigma) | >2σ por encima | Problemas de calidad/desconexiones |
| **5** | Duración | Detección bidireccional (sigma) | >2σ en cualquier dirección | Bots rotos, loops, casos edge |

---

## 🚀 Casos de Uso Reales

### Caso 1: "El bot dejó de funcionar después del deploy"

**Síntomas:**
- 🔴 **Alert 5 CRITICAL:** Duración promedio cayó de 180s a 45s (-3.8σ)
- 🔴 **Alert 4 CRITICAL:** Short calls subieron de 12% a 35% (+5.7σ)
- 🟡 **Alert 1 WARNING:** Calidad horaria cayó 18%

**Interpretación:**
Las llamadas son muy cortas Y hay muchas llamadas cortas. Esto indica que:
- Los usuarios cuelgan muy rápido (frustración)
- El bot probablemente tiene un bug crítico
- La nueva versión rompió algo importante

**Acción recomendada:**
1. Revisar el último deploy
2. Verificar logs de errores
3. Considerar rollback urgente

---

### Caso 2: "Problema intermitente de red"

**Síntomas:**
- 🟡 **Alert 4 WARNING:** Short calls en 18% vs 12% promedio (+2.1σ)
- 🟢 **Alert 5 FINE:** Duración promedio normal
- 🟢 **Alert 1 FINE:** Calidad horaria estable

**Interpretación:**
Hay más llamadas cortas de lo normal, pero la duración promedio es normal. Esto sugiere:
- Algunas llamadas se están cayendo
- Pero cuando funcionan, duran lo esperado
- Problema probablemente de conectividad, no del bot

**Acción recomendada:**
1. Revisar métricas de red
2. Verificar proveedor de telefonía
3. Revisar regiones afectadas

---

### Caso 3: "Bot en loop infinito"

**Síntomas:**
- 🔴 **Alert 5 CRITICAL:** Duración promedio subió a 320s vs 180s (+5.0σ) - TOO_LONG
- 🟢 **Alert 4 FINE:** Short calls normales
- 🟡 **Alert 1 WARNING:** Calidad cayó por usuarios frustrados

**Interpretación:**
Las llamadas duran mucho más de lo normal. Los usuarios no cuelgan rápido (no son short calls), pero se quedan atrapados. Esto indica:
- El bot está atrapando usuarios en un loop
- Hay un caso edge no manejado
- La lógica de finalización está rota

**Acción recomendada:**
1. Revisar logs de conversaciones largas
2. Identificar patrón común en llamadas >5 minutos
3. Agregar escape routes o timeout

---

## 💡 Tips para Interpretar las Alertas

### 1. **Alertas múltiples simultáneas = Problema serio**
Si 2-3 alertas disparan al mismo tiempo, el problema es real y requiere atención inmediata.

### 2. **Una sola alerta = Investigar, pero no pánico**
Podría ser variabilidad normal o un problema menor.

### 3. **Alertas 4 y 5 son tus mejores amigas para detectar problemas sutiles**
Mientras las alertas 1,2,3 detectan caídas obvias, las 4 y 5 detectan problemas que podrían pasar desapercibidos.

### 4. **Revisa el contexto:**
- ¿Hubo un deploy reciente?
- ¿Cambió algo en infraestructura?
- ¿Es fin de mes / viernes / hora pico?

### 5. **Usa las alertas históricas para identificar patrones**
Si Alert 1 dispara todos los lunes a las 5 PM, probablemente hay un patrón semanal que debes investigar.

---

## 🎓 Glosario de Términos Simples

| Término | Explicación Simple |
|---------|-------------------|
| **Baseline** | Valor de referencia histórico contra el cual comparamos |
| **Sigma (σ)** | Medida de qué tan "raro" es un valor. >2σ = muy raro |
| **Percentil 95 (P95)** | El 95% de los valores históricos están por debajo de este número |
| **Short calls** | Llamadas completadas pero muy cortas (<30s), suelen indicar problemas |
| **Quality rate** | % de llamadas buenas (largas) vs todas las llamadas completadas |
| **Dual baseline** | Compara contra 2 referencias para confirmar que el problema es real |
| **TOO_SHORT** | Llamadas anormalmente cortas (Alert 5) |
| **TOO_LONG** | Llamadas anormalmente largas (Alert 5) |

---

## 📈 Cómo Usar Este Sistema Eficazmente

### 1. **Monitoreo Diario (5 minutos)**
- Revisa dashboard de alertas en la mañana
- Identifica alertas CRITICAL o WARNING
- Prioriza según severidad

### 2. **Investigación (15-30 minutos)**
- Para alertas CRITICAL: investiga inmediatamente
- Para alertas WARNING: revisa en próximas 2 horas
- Usa las métricas adicionales para entender la causa

### 3. **Seguimiento (ongoing)**
- Documenta la causa raíz cuando la encuentres
- Crea procesos para prevenir recurrencias
- Ajusta umbrales si hay falsos positivos frecuentes

### 4. **Reuniones Semanales**
- Revisa patrones de alertas de la semana
- Identifica problemas recurrentes
- Define acciones preventivas

---

## ✅ Checklist de Acción Rápida

Cuando recibas una alerta, sigue estos pasos:

### Para Alertas 1, 2, 3 (Calidad/Volumen):
- [ ] ¿Cuándo empezó a caer? (timestamp exacto)
- [ ] ¿Afecta a todas las organizaciones o solo algunas?
- [ ] ¿Hubo cambios recientes? (deploys, configuración)
- [ ] ¿Los logs muestran errores?

### Para Alert 4 (Short Call Spike):
- [ ] ¿Cuántas llamadas cortas adicionales hay? (número absoluto)
- [ ] ¿Qué organizaciones están afectadas?
- [ ] ¿Hay errores de audio/conexión en los logs?
- [ ] ¿Cambió algo en el proveedor de telefonía?

### Para Alert 5 (Call Duration Anomaly):
- [ ] ¿Es TOO_SHORT o TOO_LONG?
- [ ] Si TOO_SHORT: ¿Por qué cuelgan rápido?
- [ ] Si TOO_LONG: ¿En qué parte del flujo se atoran?
- [ ] ¿Puedes reproducir el problema?

---

**Última actualización:** Diciembre 2025  
**Versión:** 1.0 Executive Summary  
**Contacto:** AI Data Team - AI Squad

Para documentación técnica detallada, consulta: `ALERTS_DOCUMENTATION.md`


# Progreso del proyecto — Observabilidad (P8)

## Enunciado

**Objetivo**: Instrumentar una aplicación web Spring Boot con métricas (Actuator + Micrometer), integrarla con Prometheus, diseñar paneles en Grafana y definir alertas.

---

## Parte 1 — Instrumentación con métricas ✅

### 1.1 Exponer Actuator

**Añadido al `pom.xml`:**
```xml
<dependency>
    <groupId>org.springframework.boot</groupId>
    <artifactId>spring-boot-starter-actuator</artifactId>
</dependency>
<dependency>
    <groupId>io.micrometer</groupId>
    <artifactId>micrometer-registry-prometheus</artifactId>
</dependency>
```

**Configurado en `application.properties`:**
```properties
management.endpoints.web.exposure.include=*
management.endpoint.health.show-details=always
management.endpoint.prometheus.enabled=true
management.prometheus.metrics.export.enabled=true
management.metrics.tags.application=books
```

**Endpoints disponibles:**
- `GET /actuator/health` — Estado de la aplicación
- `GET /actuator/metrics` — Listado de métricas disponibles
- `GET /actuator/prometheus` — Métricas en formato Prometheus

### 1.2 Métrica personalizada @Timed

**Archivo:** `src/main/java/com/uma/example/springuma/controller/ImagenController.java`

Añadida la anotación `@Timed` al endpoint de predicción:
```java
@Timed(value = "predict.latency", description = "Tiempo de respuesta de predicción",
       percentiles = {0.5, 0.95, 0.99})
@GetMapping("/imagen/predict/{id}")
public ResponseEntity<?> getImagenPrediction(@PathVariable("id") Long id) { ... }
```

Esto genera la métrica `predict_latency_seconds` con:
- `predict_latency_seconds_sum`
- `predict_latency_seconds_count`
- `predict_latency_seconds_max`
- Percentiles: 0.5, 0.95, 0.99

**Verificación:**
```bash
curl http://localhost:8080/actuator/prometheus | grep predict
```

### 1.3 Bug corregido — Package scanning de MetricsConfig

**Problema:** `MetricsConfig.java` estaba en `com.uma.example.demo.utils`, pero Spring Boot escanea desde `com.uma.example.springuma` y no alcanza paquetes hermanos. El bean `TimedAspect` nunca se creaba y `@Timed` se ignoraba silenciosamente.

**Solución:** Se movió a `com.uma.example.springuma.config`:
- `src/main/java/com/uma/example/springuma/config/MetricsConfig.java`
- `src/main/java/com/uma/example/springuma/config/BooksMetrics.java`

El paquete `com.uma.example.demo` se eliminó por completo al quedar vacío.

### 1.4 Métricas por defecto visibles en `/actuator/prometheus`

```
jvm_memory_used_bytes{area="heap"}
jvm_memory_used_bytes{area="nonheap"}
jvm_memory_max_bytes
jvm_memory_committed_bytes
jvm_gc_pause_seconds
jvm_threads_live_threads
hikaricp_connections_active
http_server_requests_seconds_count
http_server_requests_seconds_sum
predict_latency_seconds_count        # <-- @Timed
predict_latency_seconds_sum          # <-- @Timed
predict_latency_seconds_max          # <-- @Timed
predict_latency_seconds{quantile=}   # <-- @Timed (percentiles)
process_cpu_usage
system_cpu_usage
...
```

---

## Parte 2 — Dockerización e integración con Prometheus ✅ (Pasos 3-6)

### 2.1 Paso 3 — Construcción de imagen Docker

**Ejecutado:**
```bash
docker build -t springuma:1.0 .
```

**Dockerfile — Cambios:**
- `EXPOSE 8080` → `EXPOSE 8081` (coherente con puerto de la app)
- Build multi-stage: Maven (builder) → Eclipse Temurin JRE (runtime)
- Usuario no-root `spring:spring` para seguridad

### 2.2 Paso 4 — Integración en docker-compose.yml

**Cambios:**
- Descomentado servicio `books` → renombrado a `springuma` (para coherencia con nombre real)
- `image: springuma:1.0`
- `container_name: app-springuma-medics`
- `ports: - "8081:8081"`
- `networks: - monitoring`

### 2.3 Paso 5 — Configuración de Prometheus

**prometheus.yml — Cambios:**
- Descomentado job `spring-boot-books` → renombrado a `spring-boot-medics`
- `metrics_path: /actuator/prometheus`
- `targets: ['springuma:8081']`
- Permite scraping automático de métricas de la app cada 15 segundos

### 2.4 application.properties — Puerto y Histograma

**Cambios:**
- Añadido `server.port=8081` (línea 11) - evita conflicto con cAdvisor
- Añadido `management.metrics.distribution.percentiles-histogram.predict.latency=true` (línea 52) - habilita histogram buckets para P95

### 2.5 Paso 6 — Grafana Provisioning

**Creada estructura `grafana/provisioning/`:**

```
grafana/provisioning/
  datasources/
    datasource.yml          ← Datasource Prometheus (http://prometheus:9090)
  dashboards/
    dashboard.yml           ← Provider para carga automática
    system-monitoring.json  ← Dashboard con 4 paneles
```

**Dashboard System Monitoring — 4 Paneles:**
| # | Panel | Métrica | Estado |
|---|-------|---------|--------|
| 1 | Tiempo medio respuesta global | `http_server_requests_seconds` | ✅ Funcionando |
| 2 | Memoria heap usada | `jvm_memory_used_bytes{area="heap"}` | ✅ Funcionando |
| 3 | Latencia media predicción | `predict_latency_seconds` (sum/count) | ✅ Funcionando |
| 4 | P95 latencia predicción | `predict_latency_seconds_bucket` | ⏳ Requiere rebuild |

### 2.6 Paso 7 — docker-compose up

**Ejecutado:**
```bash
docker-compose down
docker-compose up -d
```

**Servicios levantados:**
- ✅ prometheus (9090)
- ✅ grafana (3000)
- ✅ springuma (8081)
- ✅ node-exporter (9100)
- ✅ cadvisor (8080)

**Verificación:**
- ✅ Prometheus scraping: `http://localhost:9090/targets` → spring-boot-medics **UP**
- ✅ Grafana dashboard: `http://localhost:3000` → System Monitoring visible

---

## Parte 2 — Diseño de métricas para Grafana ⏳ (Paso 6 en progreso)

### Pendiente
- Crear estructura `grafana/provisioning/`
- Datasource apuntando a Prometheus
- Dashboard JSON con 4 paneles:
  1. **Tiempo medio de respuesta global** — `http_server_requests_seconds`
  2. **Memoria usada (heap)** — `jvm_memory_used_bytes{area="heap"}`
  3. **Latencia media de predicción** — `predict_latency_seconds`
  4. **P95 latencia de predicción** — `predict_latency_seconds`

---

## Parte 3 — Definición de alertas ⏳

### Pendiente
- Actualizar `alerts.yml` con reglas de Prometheus:
  1. HighPredictionLatency — `> 0.5s` durante 1 minuto
  2. HighMemoryUsage — heap > 30%
  3. ServiceDown — `up == 0` durante 1 minuto
- Configurar `alertmanager.yml`
- Descomentar alerting en `prometheus.yml`
- Añadir servicio app al `docker-compose.yml`

---

## Archivos modificados/creados

### Parte 1 — Instrumentación

| Archivo | Cambio |
|---------|--------|
| `pom.xml` | Añadidas dependencias `actuator` + `micrometer-registry-prometheus` |
| `application.properties` | Añadida configuración de Actuator y Prometheus |
| `ImagenController.java` | Añadido `@Timed` al endpoint `/imagen/predict/{id}` |
| `springuma/config/MetricsConfig.java` | **Creado** — bean `TimedAspect` (movido de `demo.utils`) |
| `springuma/config/BooksMetrics.java` | **Creado** — contador personalizado (movido de `demo.utils`) |
| `demo/utils/` | **Eliminado** — paquete no escaneado por Spring |
| `enunciado.txt` | **Añadido** — enunciado de la práctica |
| `PROGRESS.md` | **Creado** — este documento |
| `.gitignore` | Añadidas líneas `database.mv.db` y `database.trace.db` |
| `database.mv.db` | **Eliminado** — archivo binario generado en tiempo de ejecución |

### Parte 2 — Dockerización (Pasos 3-5)

| Archivo | Cambio |
|---------|--------|
| `application.properties` | **Modificado** — Añadido `server.port=8081` (línea 11) |
| `Dockerfile` | **Modificado** — `EXPOSE 8080` → `EXPOSE 8081` |
| `docker-compose.yml` | **Modificado** — Descomentado/adaptado servicio `springuma` (era `books`) |
| `prometheus.yml` | **Modificado** — Descomentado/adaptado job `spring-boot-medics` (era `spring-boot-books`) |
| Imagen Docker | **Creada** — `docker build -t springuma:1.0 .` (multi-stage: Maven + Eclipse Temurin) |

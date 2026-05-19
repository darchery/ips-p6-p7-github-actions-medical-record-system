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

## Parte 3 — Definición de alertas ✅ (Paso 7)

### 3.1 Archivo `alerts.yml` — Reglas de alerta

**Estructura:** 2 grupos de reglas
- **Grupo `containers`** (existente):
  - HighMemoryUsage: `(container_memory_usage_bytes / container_spec_memory_limit_bytes) * 100 > 20` por 2m
  - HighCPUUsage: `rate(container_cpu_usage_seconds_total[5m]) > 0.85` por 5m

- **Grupo `spring-boot`** (nuevo):
  - **HighPredictionLatency**: `predict_latency_seconds_sum / predict_latency_seconds_count > 0.5` por 1m
    - Severity: warning
    - Detecta latencia media de predicción > 0.5s
  - **HighMemoryUsage_SpringBoot**: `(jvm_memory_used_bytes{area="heap"} / jvm_memory_max_bytes{area="heap"}) * 100 > 30` por 1m
    - Severity: critical
    - Detecta uso de heap JVM > 30%
  - **ServiceDown**: `up{job="spring-boot-medics"} == 0` por 1m
    - Severity: critical
    - Detecta si el servicio no responde (up == 0)

### 3.2 Archivo `alertmanager.yml` — Gestor de alertas

**Configuración básica:**
- `global.resolve_timeout: 1m` — tiempo para declarar alerta como resuelta
- `route.receiver: "null-receiver"` — las alertas no se envían a ningún lado (registro local)
- `receivers: - name: "null-receiver"` — receptor vacío para la práctica

### 3.3 Archivo `prometheus.yml` — Configuración de alerting

**Descomentadas secciones:**
```yaml
alerting:
  alertmanagers:
    - static_configs:
        - targets:
            - alertmanager:9093

rule_files:
  - "/etc/prometheus/alerts.yml"
```

### 3.4 Archivo `docker-compose.yml` — Integración

**Cambios realizados:**
- Descomentado volumen `./alerts.yml:/etc/prometheus/alerts.yml` en servicio `prometheus` (línea 11)
  - Permite a Prometheus cargar las reglas de alerta desde el archivo local
- Descomentado servicio `alertmanager`:
  - `image: prom/alertmanager:v0.28.0`
  - `container_name: alertmanager`
  - `ports: - "9093:9093"`
  - `volumes: - ./alertmanager.yml:/etc/alertmanager/alertmanager.yml`
  - `networks: - monitoring`

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

### Parte 2.5 — Grafana Provisioning (Paso 6)

| Archivo | Cambio |
|---------|--------|
| `application.properties` | **Modificado** — Añadido `management.metrics.distribution.percentiles-histogram.predict.latency=true` (línea 52) |
| `docker-compose.yml` | **Modificado** — Renombrado servicio `books:` → `springuma:` (línea 68) |
| `grafana/provisioning/datasources/datasource.yml` | **Creado** — Datasource Prometheus |
| `grafana/provisioning/dashboards/dashboard.yml` | **Creado** — Provider de dashboards |
| `grafana/provisioning/dashboards/system-monitoring.json` | **Creado** — Dashboard con 4 paneles |

### Parte 3 — Alertas (Paso 7)

| Archivo | Cambio |
|---------|--------|
| `alerts.yml` | **Modificado** — Añadido grupo `spring-boot` con 3 reglas (HighPredictionLatency, HighMemoryUsage_SpringBoot, ServiceDown) |
| `prometheus.yml` | **Modificado** — Descomentadas secciones `alerting:` y `rule_files:` |
| `docker-compose.yml` | **Modificado** — Descomentado volumen alerts.yml en prometheus + descomentado servicio alertmanager |
| `alertmanager.yml` | ✅ Ya existía con receiver "null-receiver" |

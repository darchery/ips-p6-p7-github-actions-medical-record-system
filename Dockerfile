# ---- Build stage ----
FROM maven:3.9.9-eclipse-temurin-21 AS builder
WORKDIR /app

# Laverage Docker cache by first copying only the pom.xml and downloading dependencies
COPY pom.xml .
RUN mvn dependency:resolve-plugins dependency:go-offline -B

# Build the application without running tests to speed up the process. Tests can be run in a separate stage if needed.
COPY src ./src
RUN mvn clean package -DskipTests -B

# ---- Runtime stage ----
# We use a smaller JRE image for the runtime stage to reduce the final image size. Eclipse Temurin is a good choice for Java applications.
FROM eclipse-temurin:21-jre-jammy

# Create a non-root user to run the application for better security. Spring is just an example username.
RUN addgroup --system spring && adduser --system spring --ingroup spring
USER spring:spring

WORKDIR /app

# Copy the built JAR file from the builder stage. Assuming the JAR is named app.jar, adjust if your build produces a different name.
COPY --from=builder /app/target/*.jar app.jar

# Expose the port that the Spring Boot application will run on. By default, Spring Boot runs on port 8080, but adjust if your application uses a different port.
EXPOSE 8081

# Options for running the application in a container. The -XX:+UseContainerSupport flag allows the JVM to recognize the container's memory limits, which is important for performance and stability.
ENTRYPOINT ["java", "-XX:+UseContainerSupport", "-jar", "app.jar"]
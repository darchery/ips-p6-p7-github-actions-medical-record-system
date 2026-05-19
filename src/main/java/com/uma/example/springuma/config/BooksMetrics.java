package com.uma.example.springuma.config;

import org.springframework.stereotype.Component;

import io.micrometer.core.instrument.Counter;
import io.micrometer.core.instrument.MeterRegistry;

@Component
public class BooksMetrics {

private final Counter personaCounter;

  public BooksMetrics(MeterRegistry registry) {
    this.personaCounter = Counter.builder("personas.save.total")
        .register(registry);
  }

  /*
   * Increments the persona save counter.
   */
  public void incrementPersonas() {
    personaCounter.increment();
  }
}

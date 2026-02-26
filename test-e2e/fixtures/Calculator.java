package io.gravitee.test.calculator;

/**
 * Simple arithmetic calculator for plugin E2E testing.
 * INTENTIONALLY MISSING: subtract(int a, int b)
 * That method is the target of the APIM-100 test ticket.
 */
public class Calculator {

    public int add(int a, int b) {
        return a + b;
    }

    public int multiply(int a, int b) {
        return a * b;
    }
}

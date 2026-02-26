package io.gravitee.test.calculator;

import org.junit.jupiter.api.Test;
import static org.junit.jupiter.api.Assertions.*;

/**
 * Existing tests — cover add and multiply.
 * CalculatorSubtractTest will be created by /implement-task during E2E recording.
 */
class CalculatorTest {

    private final Calculator calculator = new Calculator();

    @Test
    void add_returnsSum() {
        assertEquals(5, calculator.add(2, 3));
    }

    @Test
    void add_handlesNegative() {
        assertEquals(-1, calculator.add(2, -3));
    }

    @Test
    void multiply_returnsProduct() {
        assertEquals(6, calculator.multiply(2, 3));
    }

    @Test
    void multiply_byZero_returnsZero() {
        assertEquals(0, calculator.multiply(5, 0));
    }
}

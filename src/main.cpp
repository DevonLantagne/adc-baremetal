/*
STM32L476RG ADC Polling Example
Reads analog input on PA0 (Arduino A0) via ADC1 Channel 5
Outputs readings to Serial as byte stream.
*/

#include <Arduino.h>        // Arduino framework for its serial API
#include <stm32l476xx.h>    // CMSIS headers (register/bit names) for ADC

// App Config
#define BAUD_RATE   115200
#define ADC_CHANNEL 5       // PA0 maps to ADC channel 5
#define ADC_PIN     0       // PA0 is pin 0 on GPIOA
#define SAMP_TIME   0       // ADC sampling time bitval (18.7.6)
#define SAMP_RATE   100      // Approx delay between samples in ms
#define PIN_SAMPLE  D3      // PIN to measure time for conversions
#define PIN_SERIAL  D4      // PIN to measure time for serial transmissions
#define SAMP_PERIOD 1000000/SAMP_RATE  // units of us

// ADC Demo Functions
void adc_init(void);
uint16_t adc_read(uint8_t channel);

/////////////////////////////////////////////////////////////////////
// Main Application
/////////////////////////////////////////////////////////////////////

int main(void){
    // Setup
    init();                     // Arduino Initialization
    Serial.begin(BAUD_RATE);    // configure UART

    // Configure GPIO pin
    RCC->AHB2ENR |= RCC_AHB2ENR_GPIOAEN;    // Enable GPIOA clock
    GPIOA->MODER |= (3U << (ADC_PIN * 2));  // Set PA_0 (A0) as analog (MODER = 0b11 for analog mode)
    GPIOA->ASCR |= (1U << ADC_PIN);         // Connect PA_0 to ADC (ASCR = 1 to connect pin to ADC)

    // Configure ADC1 module
    adc_init();

    // Configure Digital Pins
    pinMode(PIN_SAMPLE, OUTPUT);
    pinMode(PIN_SERIAL, OUTPUT);

    // App Loop Variables
    uint16_t sample;    // To hold our sampled data

    // Main Loop
    while (1){
        // Read ADC value
        sample = adc_read(ADC_CHANNEL);
        // Send frame header (0xAA) followed by 2 bytes of data (LSB first - little endian)
        digitalWrite(PIN_SERIAL, HIGH);
        Serial.write(0xAA);
        Serial.write(0xAA);
        Serial.write((uint8_t)(sample & 0xFF)); // Send low byte
        Serial.write((uint8_t)(sample >> 8));   // Send high byte
        digitalWrite(PIN_SERIAL, LOW);
        delayMicroseconds(SAMP_PERIOD);
    }
}

/////////////////////////////////////////////////////////////////////
// ADC Initialization
/////////////////////////////////////////////////////////////////////

void adc_init(void){
    // Reset and Clock Control (RCC)
    // AHB2ENR = AHB2 Peripheral Clock Enable Register
    RCC->AHB2ENR |= RCC_AHB2ENR_ADCEN;      // Enable ADC Clock
    // Peripherals Independent Clock Configuration Register (RCC_CCIPR)
    RCC->CCIPR |=  RCC_CCIPR_ADCSEL;        // ADC will use system clock 

    // ADC common prescaler: divide system clock by 8
    ADC123_COMMON->CCR &= ~ADC_CCR_PRESC;
    ADC123_COMMON->CCR |=  ADC_CCR_PRESC_2;

    // ADC Control Register (ADC_CR)
    // Disable ADC before configuration
    // "ADEN" = ADC Enabled
    if (ADC1->CR & ADC_CR_ADEN) {
        ADC1->CR |= ADC_CR_ADDIS; // Start "power-down" procedure for ADC
        while (ADC1->CR & ADC_CR_ADEN); // Wait for ADC module to be disabled
    }
    // Begin startup procedure (18.4.6)
    ADC1->CR &= ~ADC_CR_DEEPPWD;        // Disable Deep Power Down mode
    ADC1->CR |= ADC_CR_ADVREGEN;        // Enable ADC internal regulator
    // Wait ~20 us for calibration (datasheet requirement)
    // Clock is 80 MHz (12.5ns period). ~5 cycles per loop. ~60us delay.
    for (volatile uint16_t i = 0; i < 1000; i++);
    // Calibrate the ADC
    ADC1->CR |= ADC_CR_ADCAL;           // write 1 to start calibration
    while (ADC1->CR & ADC_CR_ADCAL);    // will be zero when calibration complete

    // ADC Configuration Register (ADC_CFGR)
    ADC1->CFGR &= ~ADC_CFGR_CONT;       // Single conversion mode
    ADC1->CFGR &= ~ADC_CFGR_RES;        // 12-bit resolution

    // Channel sampling time
    ADC1->SMPR1 &= ~(7U << (ADC_CHANNEL * 3));          // Clear all bits to lowest (2.5 cycles)
    ADC1->SMPR1 |=  (SAMP_TIME << (ADC_CHANNEL * 3));   // Set to increase clock cycles

    // ADC Regular Sequence Register 1 (ADC_SQR1)
    ADC1->SQR1 &= ~ADC_SQR1_L;              // 1 conversion in regular sequence

    // Enable ADC (back to ADC Control Register ADC_CR)
    ADC1->CR |= ADC_CR_ADEN;
    while (!(ADC1->ISR & ADC_ISR_ADRDY));   // ADC Ready bit is in the ISR register
}

/////////////////////////////////////////////////////////////////////
// ADC Polling Implementation
/////////////////////////////////////////////////////////////////////

uint16_t adc_read(uint8_t channel){
    digitalWrite(PIN_SAMPLE, HIGH);

    // Set the channel in SQR1
    ADC1->SQR1 &= ~(0x1FU << 6);
    ADC1->SQR1 |= (channel << 6);
    
    ADC1->ISR |= ADC_ISR_EOC;           // Clear old flags
    ADC1->CR |= ADC_CR_ADSTART;         // Start conversion
    while (!(ADC1->ISR & ADC_ISR_EOC)); // Wait for End of Conversion
    
    digitalWrite(PIN_SAMPLE, LOW);

    return (uint16_t)ADC1->DR;          // Return data
}

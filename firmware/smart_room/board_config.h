#pragma once

#include <cstdint>
#include "board_policy.hpp"

// Deliberately disabled until the photographed hardware and power/boot behavior
// are approved on an isolated low-voltage bench. Do not enable a mains load.
// A switch is only a documented operator assertion, never proof of wiring safety.
constexpr bool HARDWARE_REVIEWED = false;
constexpr bool ENABLE_OLED = false;
constexpr bool ENABLE_IR_RECEIVE = false;
constexpr bool ENABLE_IR_TRANSMIT = false;
constexpr bool ENABLE_RELAY = false;
constexpr bool ENABLE_CAMERA = true;

constexpr int OLED_SDA = 13;
constexpr int OLED_SCL = 14;
constexpr uint8_t OLED_ADDRESS = 0x3c;  // Conditional SSD1306 128x64 hypothesis.
constexpr int IR_TX_PIN = 4;           // Also the board's white flash LED.
constexpr int IR_RX_PIN = 2;           // Disconnect signal before bootloader use.
constexpr int RELAY_PIN = 15;
constexpr bool RELAY_ACTIVE_LOW = true;  // Not confirmed; change requires wiring review.
constexpr uint32_t UART_BAUD = 921600;

static_assert(HARDWARE_REVIEWED || !(ENABLE_OLED || ENABLE_IR_RECEIVE || ENABLE_IR_TRANSMIT || ENABLE_RELAY),
              "Hardware review required before enabling peripherals");
static_assert(!ENABLE_OLED || (room::board::auxiliaryPin(OLED_SDA) && room::board::auxiliaryPin(OLED_SCL)),
              "OLED pins are reserved or unsupported on AI-Thinker ESP32-CAM");
static_assert(!ENABLE_IR_RECEIVE || room::board::auxiliaryPin(IR_RX_PIN),
              "IR receiver pin is reserved or unsupported on AI-Thinker ESP32-CAM");
static_assert(!ENABLE_IR_TRANSMIT || room::board::transmitterPin(IR_TX_PIN),
              "IR transmitter pin is reserved or unsupported on AI-Thinker ESP32-CAM");
static_assert(!ENABLE_RELAY || room::board::auxiliaryPin(RELAY_PIN),
              "Relay pin is reserved or unsupported on AI-Thinker ESP32-CAM");
constexpr std::array<room::board::Pin, 5> PERIPHERAL_PINS = {{
    {OLED_SDA, ENABLE_OLED}, {OLED_SCL, ENABLE_OLED}, {IR_RX_PIN, ENABLE_IR_RECEIVE},
    {IR_TX_PIN, ENABLE_IR_TRANSMIT}, {RELAY_PIN, ENABLE_RELAY},
}};
static_assert(room::board::distinct(PERIPHERAL_PINS), "Enabled peripheral pins must be distinct");

constexpr const char *SERVICE_UUID = "6f875ca0-24ad-47e0-a36f-50f38e4d9301";
constexpr const char *COMMAND_UUID = "6f875ca0-24ad-47e0-a36f-50f38e4d9302";
constexpr const char *EVENT_UUID = "6f875ca0-24ad-47e0-a36f-50f38e4d9303";

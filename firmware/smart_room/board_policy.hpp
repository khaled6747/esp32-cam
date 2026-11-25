#pragma once

#include <array>

// Conservative policy for the AI-Thinker ESP32-CAM + PSRAM + USB camera build.
// This is not an electrical approval. GPIO2/15 are boot straps and still need
// reset/power-cycle review; GPIO4 is permitted only for the IR transmitter
// because it also controls the built-in flash LED. microSD is not supported.
namespace room {
namespace board {

constexpr bool auxiliaryPin(int pin) {
  return pin == 2 || pin == 13 || pin == 14 || pin == 15;
}

constexpr bool transmitterPin(int pin) {
  return pin == 4 || auxiliaryPin(pin);
}

struct Pin {
  int gpio;
  bool enabled;
};

constexpr bool distinct(const std::array<Pin, 5> &pins) {
  for (unsigned i = 0; i < pins.size(); ++i) {
    for (unsigned j = i + 1; j < pins.size(); ++j) {
      if (pins[i].enabled && pins[j].enabled && pins[i].gpio == pins[j].gpio) return false;
    }
  }
  return true;
}

}  // namespace board
}  // namespace room

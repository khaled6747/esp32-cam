#pragma once

// Narrow, inert I/O fixtures for the actual command/status/USB dispatcher slice.
// No Arduino HAL, radio, serial port, flash, GPIO or physical IR is called.
#include <ArduinoJson.h>
#include <algorithm>
#include <array>
#include <atomic>
#include <cstdint>
#include <cstring>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>
#include "../firmware/smart_room/auth_core.hpp"
#include "../firmware/smart_room/command_fields.hpp"
#include "../firmware/smart_room/room_core.hpp"

using String = std::string;

namespace smart {

constexpr uint16_t NO_CONNECTION = 0xffff;
constexpr int ESP_OK = 0, MBEDTLS_MD_SHA256 = 0;
struct Link { uint16_t id = 1; uint32_t generation = 1; bool secure = true; };
struct Capture { bool bluetooth; std::string json; };
struct mbedtls_md_info_t {};
struct esp_ble_bond_dev_t { uint8_t bd_addr[6]{}; };

room::Engine engine;
room::AuthenticationGate auth;
room::RequestSequence requests, usb_requests;
room::ControlAssembler<768> control;
room::LineAssembler<768> lines;
std::vector<Capture> captures;
Link fixture_link;
int link_mux = 0;
bool security_owner_exists = false;
void portENTER_CRITICAL(int *) {}
void portEXIT_CRITICAL(int *) {}
uint32_t now = 0, current_generation = 1, pairing_at = 0, last_frame = 0, last_sequence = 0, learning_at = 0;
unsigned storage_writes = 0, disconnect_requests = 0, receiver_starts = 0, provider_calls = 0, random_round = 0;
bool provider_available = true, provider_context_verified = false;
bool ENABLE_RELAY = false, ENABLE_IR_TRANSMIT = false, ENABLE_IR_RECEIVE = false;
bool owner_exists = true, preferences_ready = true, learning = false, camera_ready = true;
std::atomic<bool> ble_ready{true};
std::atomic<uint32_t> tx_errors{0};
uint8_t last_sent_slot = 0, ir_fault_slot = 0;
const char *ir_fault = "none";
std::array<uint8_t,32> owner_key{}, expected_hmac{};
std::array<char,13> device_id{};
std::array<char,17> boot_id{};
std::array<char,33> host_session{};
room::SlotMeta learning_meta;
std::string expected_context;
int bond_count = 0, bond_removal_result = ESP_OK;

struct Display {
  bool available = true;
  bool ready() const { return available; }
} oled;
struct Receiver {
  void disableIRIn() {}
  void enableIRIn() { ++receiver_starts; }
  void resume() {}
} receiver;
struct Storage {
  bool available = true, failing = false;
  std::array<bool,17> present{};
  std::array<room::SlotMeta,17> records{};
  bool ready() const { return available; }
  bool has(uint8_t slot) const { return slot >= 1 && slot <= 16 && present[slot]; }
  const room::SlotMeta &meta(uint8_t slot) const { return records.at(slot); }
  bool eraseConfirmed(uint8_t slot) {
    if (!available || failing || slot < 1 || slot > 16) return false;
    ++storage_writes; present[slot] = false; return true;
  }
  bool initializeConfirmed() {
    if (failing) return false;
    if (!available) ++storage_writes;
    available = true; return true;
  }
} slots;
struct PreferenceStore {
  bool failing = false;
  size_t putBytes(const char *, const uint8_t *, size_t size) {
    ++storage_writes; return failing ? 0 : size;
  }
  size_t putString(const char *, const String &value) {
    ++storage_writes; return failing ? 0 : value.length();
  }
  bool remove(const char *) { ++storage_writes; return !failing; }
} preferences;

uint32_t millis() { return now; }
Link readLink() { return fixture_link; }
void disconnect(uint16_t id) {
  if (id != NO_CONNECTION) { ++disconnect_requests; fixture_link.secure = false; }
}
void esp_fill_random(uint8_t *destination, size_t size) {
  for (size_t i = 0; i < size; ++i) destination[i] = static_cast<uint8_t>(i + (size == 32 ? 16 : 0) + random_round);
  if (size == 32) ++random_round;
}
const mbedtls_md_info_t *mbedtls_md_info_from_type(int) {
  static const mbedtls_md_info_t info{}; return provider_available ? &info : nullptr;
}
int mbedtls_md_hmac(const mbedtls_md_info_t *, const uint8_t *key, size_t key_size,
                    const uint8_t *text, size_t text_size, uint8_t *output) {
  ++provider_calls;
  if (key_size != 32 || std::string(reinterpret_cast<const char *>(text), text_size) != expected_context) return -1;
  for (unsigned i = 0; i < 32; ++i) if (key[i] != i) return -1;
  // Python supplies the independent hashlib HMAC result. This is a provider
  // fixture, NOT execution or certification of ESP32's mbedTLS implementation.
  provider_context_verified = true; std::memcpy(output, expected_hmac.data(), 32); return 0;
}
void mbedtls_platform_zeroize(void *data, size_t size) {
  volatile auto *bytes = static_cast<volatile uint8_t *>(data);
  while (size--) *bytes++ = 0;
}
int esp_ble_get_bond_device_num() { return bond_count; }
int esp_ble_get_bond_device_list(int *count, esp_ble_bond_dev_t *) { return *count >= 0 ? ESP_OK : -1; }
int esp_ble_remove_bond_device(const uint8_t *) { return bond_removal_result; }

bool send(JsonDocument &document, bool bluetooth) {
  std::string encoded; const size_t size = measureJson(document);
  if (size > 4095 || serializeJson(document,encoded) != size || captures.size() >= 64)
    throw std::runtime_error("Fixture event bound");
  captures.push_back({bluetooth,encoded}); return true;
}
void ack(uint32_t id, bool ok, const char *code, bool bluetooth = true) {
  JsonDocument reply; reply["v"] = 1; reply["type"] = "ack"; reply["id"] = id;
  if (!bluetooth && host_session[0]) reply["session"] = host_session.data();
  reply["ok"] = ok; reply["code"] = code; send(reply,bluetooth);
}

inline bool option(JsonObjectConst object, const char *name, bool fallback) {
  if (!object[name].isNull() && !object[name].is<bool>()) throw std::runtime_error("Fixture boolean type");
  return object[name].isNull() ? fallback : object[name].as<bool>();
}
void initialize(JsonObjectConst fixture) {
  if (fixture.isNull() || fixture.size() > 12 || !fixture["expected_context"].is<const char *>()
      || !fixture["expected_hmac"].is<const char *>()) throw std::runtime_error("Fixture envelope");
  expected_context = fixture["expected_context"].as<const char *>();
  if (expected_context.size() > 191 || !room::parseHex(fixture["expected_hmac"].as<const char *>(),32,expected_hmac.data()))
    throw std::runtime_error("Fixture oracle bound");
  engine = room::Engine(); auth.reset(); requests.reset(); usb_requests.reset(); lines.reset(); control.reset();
  fixture_link = Link{}; captures.clear(); slots = Storage{}; preferences = PreferenceStore{};
  now = pairing_at = last_frame = last_sequence = learning_at = 0;
  current_generation = 1; last_sent_slot = ir_fault_slot = 0; ir_fault = "none";
  storage_writes = disconnect_requests = receiver_starts = provider_calls = random_round = 0;
  provider_context_verified = false; learning = false;
  for (unsigned i = 0; i < 32; ++i) owner_key[i] = static_cast<uint8_t>(i);
  std::strcpy(device_id.data(),"f024f91080a4"); std::strcpy(boot_id.data(),"0202020202020202"); host_session.fill(0);
  owner_exists = option(fixture,"owned",true); preferences_ready = option(fixture,"preferences_ready",true);
  provider_available = option(fixture,"provider_available",true); oled.available = option(fixture,"oled_ready",true);
  preferences.failing = option(fixture,"storage_failure",false); slots.failing = preferences.failing;
  slots.available = option(fixture,"storage_ready",true);
  ENABLE_RELAY = ENABLE_IR_TRANSMIT = ENABLE_IR_RECEIVE = option(fixture,"simulate_enabled",false);
  bond_count = fixture["bond_count"].is<int>() ? fixture["bond_count"].as<int>() : 0;
  bond_removal_result = option(fixture,"bond_failure",false) ? -1 : ESP_OK;
  if (fixture["slots"].is<JsonArrayConst>()) {
    JsonArrayConst values = fixture["slots"].as<JsonArrayConst>();
    if (values.size() > 16) throw std::runtime_error("Fixture slot count");
    for (auto value : values) {
      if (!value.is<unsigned>() || value.as<unsigned>() < 1 || value.as<unsigned>() > 16) throw std::runtime_error("Fixture slot range");
      const auto slot = value.as<uint8_t>(); slots.present[slot] = true;
      auto &meta = slots.records[slot]; meta.slot = slot; meta.pulse_count = 17; meta.mode = 1;
      meta.sleep = slot == 4; std::strcpy(meta.label.data(),"fixture");
    }
  }
}

}  // namespace smart

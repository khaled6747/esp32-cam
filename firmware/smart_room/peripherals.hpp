#pragma once

#include <Arduino.h>
#include <LittleFS.h>
#include <Wire.h>
#include <array>
#include "board_config.h"
#include "wire.hpp"

// Only fixed, validated slot paths can reach LittleFS. An interrupted write keeps
// the previous valid .bak. Mount failure never silently formats storage.
class SlotStore {
 public:
  bool begin() { mounted_ = LittleFS.begin(false); if (mounted_) scan(); return mounted_; }
  bool ready() const { return mounted_; }
  bool initializeConfirmed() {
    if (mounted_) return true;
    if (!LittleFS.format()) return false;
    return begin();
  }
  bool has(uint8_t slot) const { return slot >= 1 && slot <= 16 && present_[slot - 1]; }
  const room::SlotMeta &meta(uint8_t slot) const { return metadata_[slot - 1]; }
  uint32_t mask() const {
    uint32_t mask = 0; for (uint8_t i = 1; i <= 16; ++i) if (has(i)) mask |= 1U << i; return mask;
  }
  bool load(uint8_t slot, room::RecordedSlot &out) {
    if (!mounted_ || slot < 1 || slot > 16) return false;
    return readPath(path(slot, ".bin"), slot, out) || readPath(path(slot, ".bak"), slot, out);
  }
  bool save(const room::RecordedSlot &record) {
    if (!mounted_ || !room::validSlot(record)) return false;
    const uint8_t slot = record.meta.slot;
    const size_t size = room::encodeSlot(record, bytes_.data(), bytes_.size());
    File file = LittleFS.open("/ir.pending", "w");
    if (!file) return false;
    const bool written = file.write(bytes_.data(), size) == size;
    file.flush(); file.close();
    room::RecordedSlot verified;
    if (!written || !readPath("/ir.pending", slot, verified)) return false;
    const String primary = path(slot, ".bin"), backup = path(slot, ".bak");
    if (LittleFS.exists(primary)) {
      if (readPath(primary, slot, verified)) {
        if (LittleFS.exists(backup) && !LittleFS.remove(backup)) return false;
        if (!LittleFS.rename(primary, backup)) return false;
      } else if (!LittleFS.remove(primary)) {
        return false;  // Keep a valid backup if the primary was corrupt.
      }
    }
    if (!LittleFS.rename("/ir.pending", primary) || !readPath(primary, slot, verified)) return false;
    metadata_[slot - 1] = verified.meta; present_[slot - 1] = true;
    return true;
  }
  bool eraseConfirmed(uint8_t slot) {
    if (!mounted_ || slot < 1 || slot > 16) return false;
    for (const char *suffix : {".bin", ".bak"}) {
      const String file = path(slot, suffix);
      if (LittleFS.exists(file) && !LittleFS.remove(file)) return false;
    }
    present_[slot - 1] = false; return true;
  }
 private:
  static String path(uint8_t slot, const char *suffix) {
    char name[24]; snprintf(name, sizeof(name), "/ir%02u%s", slot, suffix); return String(name);
  }
  bool readPath(const String &name, uint8_t slot, room::RecordedSlot &out) {
    File file = LittleFS.open(name, "r");
    if (!file || file.size() > bytes_.size() || file.size() < room::SLOT_HEADER_SIZE) return false;
    const size_t size = file.size(); const bool read = file.read(bytes_.data(), size) == size;
    file.close();
    return read && room::decodeSlot(bytes_.data(), size, out) && out.meta.slot == slot;
  }
  void scan() {
    room::RecordedSlot record;
    for (uint8_t i = 1; i <= 16; ++i) {
      present_[i - 1] = load(i, record);
      if (present_[i - 1]) metadata_[i - 1] = record.meta;
    }
  }
  bool mounted_ = false;
  std::array<bool, 16> present_{};
  std::array<room::SlotMeta, 16> metadata_{};
  std::array<uint8_t, room::MAX_SLOT_BYTES> bytes_{};
};

// Small project-local SSD1306 renderer; ASCII font patterns are declared here.
// The controller, dimensions and address are conditional hardware hypotheses.
class RoomOled {
 public:
  bool begin() {
    if (!ENABLE_OLED) return false;
    Wire.begin(OLED_SDA, OLED_SCL, 100000); Wire.setTimeOut(50);
    Wire.beginTransmission(OLED_ADDRESS);
    if (Wire.endTransmission() != 0) return false;
    const uint8_t init[] = {0xae,0xd5,0x80,0xa8,0x3f,0xd3,0,0x40,0x8d,0x14,0x20,0,
                           0xa1,0xc8,0xda,0x12,0x81,0x7f,0xd9,0xf1,0xdb,0x40,0xa4,0xa6,0xaf};
    ready_ = command(init, sizeof(init)); return ready_;
  }
  bool ready() const { return ready_; }
  void clear() { buffer_.fill(0); }
  void text(unsigned row, unsigned column, const char *text, unsigned scale = 1) {
    if (!text || !scale || scale > 2) return;
    unsigned x = column * 6, y = row * 8;
    for (unsigned i = 0; text[i] && i < 21 && x < 128; ++i, x += 6 * scale) {
      char c = text[i]; if (c >= 'a' && c <= 'z') c -= 'a' - 'A';
      const uint8_t *rows = glyph(c);
      for (unsigned dy = 0; dy < 7; ++dy) for (unsigned dx = 0; dx < 5; ++dx) {
        const bool on = rows && (rows[dy] & (1U << (4 - dx)));
        if (on) for (unsigned sy = 0; sy < scale; ++sy) for (unsigned sx = 0; sx < scale; ++sx)
          pixel(x + dx * scale + sx, y + dy * scale + sy);
      }
    }
  }
  void flush() {
    if (!ready_) return;
    const uint8_t position[] = {0x21, 0, 127, 0x22, 0, 7};
    if (!command(position, sizeof(position))) { ready_ = false; return; }
    for (size_t offset = 0; offset < buffer_.size(); offset += 16) {
      Wire.beginTransmission(OLED_ADDRESS); Wire.write(0x40);
      Wire.write(buffer_.data() + offset, 16);
      if (Wire.endTransmission() != 0) { ready_ = false; return; }
    }
  }
 private:
  bool command(const uint8_t *bytes, size_t length) {
    for (size_t i = 0; i < length; ++i) {
      Wire.beginTransmission(OLED_ADDRESS); Wire.write(0); Wire.write(bytes[i]);
      if (Wire.endTransmission() != 0) return false;
    }
    return true;
  }
  void pixel(unsigned x, unsigned y) {
    if (x < 128 && y < 64) buffer_[x + (y / 8) * 128] |= 1U << (y % 8);
  }
  static const uint8_t *glyph(char c) {
    static const uint8_t letters[36][7] = {
      {14,17,17,31,17,17,17},{30,17,17,30,17,17,30},{14,17,16,16,16,17,14},
      {30,17,17,17,17,17,30},{31,16,16,30,16,16,31},{31,16,16,30,16,16,16},
      {14,17,16,23,17,17,15},{17,17,17,31,17,17,17},{14,4,4,4,4,4,14},
      {7,2,2,2,18,18,12},{17,18,20,24,20,18,17},{16,16,16,16,16,16,31},
      {17,27,21,21,17,17,17},{17,25,25,21,19,19,17},{14,17,17,17,17,17,14},
      {30,17,17,30,16,16,16},{14,17,17,17,21,18,13},{30,17,17,30,20,18,17},
      {15,16,16,14,1,1,30},{31,4,4,4,4,4,4},{17,17,17,17,17,17,14},
      {17,17,17,17,17,10,4},{17,17,17,21,21,27,17},{17,17,10,4,10,17,17},
      {17,17,10,4,4,4,4},{31,1,2,4,8,16,31},
      {14,17,19,21,25,17,14},{4,12,4,4,4,4,14},{14,17,1,2,4,8,31},
      {30,1,1,14,1,1,30},{2,6,10,18,31,2,2},{31,16,16,30,1,1,30},
      {14,16,16,30,17,17,14},{31,1,2,4,8,8,8},{14,17,17,14,17,17,14},{14,17,17,15,1,1,14}
    };
    static const uint8_t dash[7] = {0,0,0,31,0,0,0};
    static const uint8_t colon[7] = {0,4,4,0,4,4,0};
    if (c >= 'A' && c <= 'Z') return letters[c - 'A'];
    if (c >= '0' && c <= '9') return letters[26 + c - '0'];
    if (c == '-') return dash; if (c == ':') return colon; return nullptr;
  }
  bool ready_ = false;
  std::array<uint8_t, 1024> buffer_{};
};

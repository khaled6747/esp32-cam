#pragma once

#include <array>
#include <cstddef>
#include <cstdint>
#include <cstring>

namespace room {

inline uint16_t crc16(const uint8_t *data, size_t size) {
  uint16_t crc = 0xffff;
  for (size_t i = 0; i < size; ++i) {
    crc ^= static_cast<uint16_t>(data[i]) << 8;
    for (unsigned bit = 0; bit < 8; ++bit)
      crc = (crc & 0x8000) ? static_cast<uint16_t>((crc << 1) ^ 0x1021)
                          : static_cast<uint16_t>(crc << 1);
  }
  return crc;
}

inline uint32_t crc32(const uint8_t *data, size_t size) {
  uint32_t crc = 0xffffffffU;
  for (size_t i = 0; i < size; ++i) {
    crc ^= data[i];
    for (unsigned bit = 0; bit < 8; ++bit)
      crc = (crc >> 1) ^ ((crc & 1) ? 0xedb88320U : 0);
  }
  return ~crc;
}

inline uint16_t le16(const uint8_t *p) { return static_cast<uint16_t>(p[0] | (p[1] << 8)); }
inline uint32_t le32(const uint8_t *p) {
  return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8)
       | (static_cast<uint32_t>(p[2]) << 16) | (static_cast<uint32_t>(p[3]) << 24);
}
inline void put16(uint8_t *p, uint16_t n) { p[0] = n & 255; p[1] = n >> 8; }
inline void put32(uint8_t *p, uint32_t n) {
  for (unsigned i = 0; i < 4; ++i) p[i] = static_cast<uint8_t>(n >> (8 * i));
}

// USB control is C3 3C + uint32 length + uint16 CCITT-FALSE + JSON.
// Camera JPEGs remain A5 5A with the existing header/body contract.
template <size_t Capacity> class ControlAssembler {
 public:
  bool feed(uint8_t byte, uint32_t now) {
    if (used_ && static_cast<uint32_t>(now - last_at_) > 2000) reset();
    last_at_ = now;
    if (used_ == 0) { if (byte == 0xc3) header_[used_++] = byte; return false; }
    if (used_ == 1) {
      if (byte == 0x3c) { header_[used_++] = byte; }
      else { used_ = byte == 0xc3 ? 1 : 0; }
      return false;
    }
    if (used_ < 8) {
      header_[used_++] = byte;
      if (used_ == 8) {
        length_ = le32(header_.data() + 2);
        if (!length_ || length_ > Capacity) { ++errors_; reset(); }
      }
      return false;
    }
    data_[used_++ - 8] = byte;
    if (used_ != length_ + 8) return false;
    const bool valid = crc16(data_.data(), length_) == le16(header_.data() + 6);
    completed_ = valid ? length_ : 0;
    if (!valid) ++errors_;
    used_ = 0; length_ = 0;
    if (valid) data_[completed_] = 0;
    return valid;
  }
  const char *data() const { return reinterpret_cast<const char *>(data_.data()); }
  size_t size() const { return completed_; }
  uint32_t errors() const { return errors_; }
  void reset() { used_ = 0; length_ = 0; completed_ = 0; }
 private:
  std::array<uint8_t, 8> header_{};
  std::array<uint8_t, Capacity + 1> data_{};
  size_t used_ = 0, length_ = 0, completed_ = 0;
  uint32_t last_at_ = 0, errors_ = 0;
};

template <size_t Capacity> class LineAssembler {
 public:
  bool feed(uint8_t byte, uint32_t now) {
    if (used_ && static_cast<uint32_t>(now - last_at_) > 5000) {
      used_ = 0; dropping_ = true; ++errors_;
    }
    last_at_ = now;
    if (byte == '\n') {
      if (dropping_) { dropping_ = false; used_ = 0; return false; }
      if (!used_) return false;
      completed_ = used_; data_[used_] = 0; used_ = 0; return true;
    }
    if (dropping_) return false;
    if (used_ >= Capacity || byte == 0) { dropping_ = true; used_ = 0; ++errors_; return false; }
    data_[used_++] = static_cast<char>(byte);
    return false;
  }
  const char *data() const { return data_.data(); }
  size_t size() const { return completed_; }
  uint32_t errors() const { return errors_; }
  void reset() { used_ = 0; completed_ = 0; dropping_ = false; }
 private:
  std::array<char, Capacity + 1> data_{};
  size_t used_ = 0, completed_ = 0;
  uint32_t last_at_ = 0, errors_ = 0;
  bool dropping_ = false;
};

constexpr size_t MAX_IR_PULSES = 1024;
constexpr size_t SLOT_HEADER_SIZE = 72;
constexpr size_t MAX_SLOT_BYTES = SLOT_HEADER_SIZE + MAX_IR_PULSES * 2;

struct SlotMeta {
  uint8_t slot = 0, temperature = 26, fan = 0, mode = 0;
  bool power = true, sleep = false;
  uint16_t carrier_hz = 38000, pulse_count = 0;
  std::array<char, 48> label{};
};

struct RecordedSlot {
  SlotMeta meta;
  std::array<uint16_t, MAX_IR_PULSES> pulses{};
};

inline bool validMeta(const SlotMeta &m) {
  if (!m.slot || m.slot > 16 || m.temperature < 16 || m.temperature > 30
      || m.fan > 3 || m.mode > 4 || !m.label[0] || m.label.back() != 0) return false;
  if (m.carrier_hz != 36000 && m.carrier_hz != 38000
      && m.carrier_hz != 40000 && m.carrier_hz != 56000) return false;
  for (const char ch : m.label) if (ch && static_cast<uint8_t>(ch) < 32) return false;
  return true;
}

inline bool validSlot(const RecordedSlot &s) {
  if (!validMeta(s.meta) || s.meta.pulse_count < 16 || s.meta.pulse_count > MAX_IR_PULSES) return false;
  if (!s.pulses[0] || !s.pulses[s.meta.pulse_count - 1]) return false;
  uint32_t total = 0;
  for (uint16_t i = 0; i < s.meta.pulse_count; ++i) total += s.pulses[i];
  return total >= 1000 && total <= 2000000;
}

inline size_t encodeSlot(const RecordedSlot &s, uint8_t *out, size_t capacity) {
  const size_t size = SLOT_HEADER_SIZE + s.meta.pulse_count * 2;
  if (!validSlot(s) || capacity < size) return 0;
  std::memset(out, 0, size);
  std::memcpy(out, "SIR1", 4); out[4] = 1; out[5] = s.meta.slot;
  out[6] = (s.meta.power ? 1 : 0) | (s.meta.sleep ? 2 : 0);
  out[7] = s.meta.temperature; out[8] = s.meta.fan; out[9] = s.meta.mode;
  put16(out + 10, s.meta.carrier_hz); put16(out + 12, s.meta.pulse_count);
  std::memcpy(out + 16, s.meta.label.data(), s.meta.label.size());
  for (uint16_t i = 0; i < s.meta.pulse_count; ++i) put16(out + SLOT_HEADER_SIZE + i * 2, s.pulses[i]);
  put32(out + 64, crc32(out + SLOT_HEADER_SIZE, s.meta.pulse_count * 2));
  put32(out + 68, crc32(out, 68));
  return size;
}

inline bool decodeSlot(const uint8_t *bytes, size_t size, RecordedSlot &out) {
  if (size < SLOT_HEADER_SIZE || size > MAX_SLOT_BYTES || std::memcmp(bytes, "SIR1", 4)
      || bytes[4] != 1 || bytes[14] || bytes[15] || bytes[6] > 3) return false;
  const uint16_t count = le16(bytes + 12);
  if (count > MAX_IR_PULSES || size != SLOT_HEADER_SIZE + count * 2
      || le32(bytes + 68) != crc32(bytes, 68)
      || le32(bytes + 64) != crc32(bytes + SLOT_HEADER_SIZE, count * 2)) return false;
  RecordedSlot candidate;
  candidate.meta.slot = bytes[5]; candidate.meta.power = bytes[6] & 1; candidate.meta.sleep = bytes[6] & 2;
  candidate.meta.temperature = bytes[7]; candidate.meta.fan = bytes[8]; candidate.meta.mode = bytes[9];
  candidate.meta.carrier_hz = le16(bytes + 10); candidate.meta.pulse_count = count;
  std::memcpy(candidate.meta.label.data(), bytes + 16, candidate.meta.label.size());
  for (uint16_t i = 0; i < count; ++i) candidate.pulses[i] = le16(bytes + SLOT_HEADER_SIZE + i * 2);
  if (!validSlot(candidate)) return false;
  out = candidate;
  return true;
}

inline bool parseHex(const char *text, size_t bytes, uint8_t *out) {
  if (!text || std::strlen(text) != bytes * 2) return false;
  const auto digit = [](char c) -> int {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
  };
  for (size_t i = 0; i < bytes; ++i) {
    const int high = digit(text[i * 2]), low = digit(text[i * 2 + 1]);
    if (high < 0 || low < 0) return false;
    out[i] = static_cast<uint8_t>((high << 4) | low);
  }
  return true;
}

inline bool equalSecret(const uint8_t *a, const uint8_t *b, size_t size) {
  uint8_t mismatch = 0;
  for (size_t i = 0; i < size; ++i) mismatch |= a[i] ^ b[i];
  return mismatch == 0;
}

}  // namespace room

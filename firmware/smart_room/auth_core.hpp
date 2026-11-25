#pragma once
#include "wire.hpp"
#include <cstdio>

namespace room {
class AuthenticationGate {
 public:
  void begin(const uint8_t *session, const uint8_t *nonce, uint32_t now) {
    hex(session, 16, session_.data()); hex(nonce, 32, challenge_.data());
    at_ = now; active_ = true; authorized_ = false;
  }
  void reset() { session_.fill(0); challenge_.fill(0); active_ = false; authorized_ = false; }
  const char *session() const { return session_.data(); }
  const char *challenge() const { return challenge_.data(); }
  size_t context(const char *device, char *out, size_t capacity) const {
    uint8_t id[6]{};
    if (!device || !parseHex(device, 6, id) || !session_[0] || !out || !capacity) return 0;
    const int n = std::snprintf(out, capacity, "smart-room/v1|%s|%s|%s", device, session(), challenge());
    return n > 0 && static_cast<size_t>(n) < capacity ? static_cast<size_t>(n) : 0;
  }
  // The provider supplies a successfully calculated HMAC-SHA256. This policy
  // module does not implement cryptography or silently accept a provider failure.
  bool prove(const char *session, const char *proof, const uint8_t *expected, uint32_t now) {
    if (!matches(session) || !active_) return false;
    active_ = false;  // One use even on malformed/incorrect proofs.
    uint8_t received[32]{};
    authorized_ = static_cast<uint32_t>(now - at_) <= 30000 && expected
        && parseHex(proof, 32, received) && equalSecret(received, expected, 32);
    return authorized_;
  }
  bool claim(const char *session, uint32_t now, bool encrypted_window_allowed) {
    if (!encrypted_window_allowed || !matches(session) || !active_
        || static_cast<uint32_t>(now - at_) > 30000) return false;
    active_ = false; authorized_ = true; return true;
  }
  bool authorized(const char *session) const { return authorized_ && matches(session); }
 private:
  bool matches(const char *value) const {
    return session_[0] && value && std::strlen(value) == 32 && std::strcmp(value, session()) == 0;
  }
  static void hex(const uint8_t *bytes, size_t size, char *out) {
    constexpr const char *digits = "0123456789abcdef";
    for (size_t i = 0; i < size; ++i) { out[i * 2] = digits[bytes[i] >> 4]; out[i * 2 + 1] = digits[bytes[i] & 15]; }
    out[size * 2] = 0;
  }
  std::array<char, 33> session_{};
  std::array<char, 65> challenge_{};
  uint32_t at_ = 0;
  bool active_ = false, authorized_ = false;
};

inline bool validUtf8(const char *text, size_t size) {
  for (size_t i = 0; i < size;) {
    const auto a = static_cast<uint8_t>(text[i++]);
    if (a < 0x80) { if (!a) return false; continue; }
    unsigned count; uint32_t code;
    if (a >= 0xc2 && a <= 0xdf) { count = 1; code = a & 31; }
    else if (a >= 0xe0 && a <= 0xef) { count = 2; code = a & 15; }
    else if (a >= 0xf0 && a <= 0xf4) { count = 3; code = a & 7; }
    else return false;
    if (i + count > size) return false;
    for (unsigned j = 0; j < count; ++j) {
      const auto b = static_cast<uint8_t>(text[i++]);
      if ((b & 0xc0) != 0x80) return false;
      code = (code << 6) | (b & 63);
    }
    if ((count == 1 && code < 0x80) || (count == 2 && code < 0x800)
        || (count == 3 && code < 0x10000) || code > 0x10ffff || (code >= 0xd800 && code <= 0xdfff)) return false;
  }
  return true;
}

// Commands are a flat, scalar-only JSON object, <=768 UTF-8 bytes, <=32 plain
// ASCII keys. Reject duplicates, escaped keys, nesting and trailing junk before
// ArduinoJson can normalize an ambiguous command. Values are validated again by
// the typed operation schema; the guard is not authorization.
inline bool flatCommand(const char *text, size_t size) {
  if (!text || !size || size > 768 || !validUtf8(text, size)) return false;
  size_t pos = 0, keys = 0;
  std::array<std::array<char, 25>, 32> names{};
  const auto whitespace = [&] {
    while (pos < size && (text[pos] == ' ' || text[pos] == '\r' || text[pos] == '\n' || text[pos] == '\t')) ++pos;
  };
  const auto take = [&](char c) { if (pos >= size || text[pos] != c) return false; ++pos; return true; };
  const auto hexDigit = [](char c) -> int {
    if (c >= '0' && c <= '9') return c - '0';
    if (c >= 'a' && c <= 'f') return c - 'a' + 10;
    if (c >= 'A' && c <= 'F') return c - 'A' + 10;
    return -1;
  };
  const auto unicode = [&](uint16_t &code) {
    if (pos + 4 > size) return false;
    code = 0;
    for (unsigned i = 0; i < 4; ++i) {
      const int digit = hexDigit(text[pos++]); if (digit < 0) return false;
      code = static_cast<uint16_t>((code << 4) | digit);
    }
    return true;
  };
  whitespace(); if (!take('{')) return false; whitespace();
  while (pos < size) {
    if (keys == names.size() || !take('"')) return false;
    size_t length = 0;
    while (pos < size && text[pos] != '"') {
      const char c = text[pos++];
      if (length >= 24 || (!(c >= 'a' && c <= 'z') && !(length && ((c >= '0' && c <= '9') || c == '_')))) return false;
      names[keys][length++] = c;
    }
    if (!length || !take('"')) return false;
    for (size_t i = 0; i < keys; ++i) if (names[i] == names[keys]) return false;
    ++keys; whitespace(); if (!take(':')) return false; whitespace();
    if (pos >= size) return false;
    if (text[pos] == '"') {
      ++pos; bool closed = false;
      while (pos < size) {
        const auto c = static_cast<uint8_t>(text[pos++]);
        if (c == '"') { closed = true; break; }
        if (c < 32) return false;
        if (c == '\\') {
          if (pos >= size) return false;
          const char escape = text[pos++];
          if (escape == 'u') {
            uint16_t code;
            if (!unicode(code) || !code) return false;  // C-string truncation is never a valid field.
            if (code >= 0xd800 && code <= 0xdbff) {
              if (pos + 6 > size || text[pos] != '\\' || text[pos + 1] != 'u') return false;
              pos += 2; uint16_t low;
              if (!unicode(low) || low < 0xdc00 || low > 0xdfff) return false;
            } else if (code >= 0xdc00 && code <= 0xdfff) return false;
          } else if (escape != '"' && escape != '\\' && escape != '/' && escape != 'b'
                     && escape != 'f' && escape != 'n' && escape != 'r' && escape != 't') return false;
        }
      }
      if (!closed) return false;
    } else if (size - pos >= 4 && std::memcmp(text + pos, "true", 4) == 0) {
      pos += 4;
    } else if (size - pos >= 5 && std::memcmp(text + pos, "false", 5) == 0) {
      pos += 5;
    } else {
      if (text[pos] == '-') ++pos;
      if (pos >= size || text[pos] < '0' || text[pos] > '9') return false;
      if (text[pos] == '0') ++pos;
      else while (pos < size && text[pos] >= '0' && text[pos] <= '9') ++pos;
    }
    whitespace();
    if (take('}')) { whitespace(); return pos == size; }
    if (!take(',')) return false;
    whitespace();
  }
  return false;
}
}  // namespace room

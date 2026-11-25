#include "../firmware/smart_room/wire.hpp"
#include <array>
#include <functional>
#include <iostream>
#include <stdexcept>
#include <vector>

static void check(bool condition, const char *message) { if (!condition) throw std::runtime_error(message); }
static std::vector<uint8_t> packet(const char *text) {
  const size_t n = std::strlen(text); std::vector<uint8_t> out(n + 8);
  out[0] = 0xc3; out[1] = 0x3c; room::put32(out.data() + 2, static_cast<uint32_t>(n));
  room::put16(out.data() + 6, room::crc16(reinterpret_cast<const uint8_t *>(text), n));
  std::memcpy(out.data() + 8, text, n); return out;
}
int main() {
  unsigned passed = 0, failed = 0;
  auto test = [&](const char *name, const std::function<void()> &f) {
    try { f(); ++passed; std::cout << "PASS " << name << '\n'; }
    catch (const std::exception &e) { ++failed; std::cout << "FAIL " << name << ": " << e.what() << '\n'; }
  };
  test("standard CRC check vectors", [] {
    const auto *data = reinterpret_cast<const uint8_t *>("123456789");
    check(room::crc16(data, 9) == 0x29b1 && room::crc32(data, 9) == 0xcbf43926, "CRC oracle mismatch");
  });
  test("control bytes split arbitrarily and boot noise skipped", [] {
    room::ControlAssembler<128> reader; unsigned complete = 0;
    for (uint8_t b : std::vector<uint8_t>{0, 5, 0xc3, 0xc3}) reader.feed(b, 0);
    for (uint8_t b : packet("{\"v\":1}")) complete += reader.feed(b, 1);
    check(complete == 1 && std::strcmp(reader.data(), "{\"v\":1}") == 0, "valid control lost");
  });
  test("corrupt CRC is rejected and next complete message recovers", [] {
    room::ControlAssembler<128> reader; auto broken = packet("{}"); broken[6] ^= 1;
    unsigned complete = 0; for (uint8_t b : broken) complete += reader.feed(b, 0);
    check(!complete && reader.errors() == 1, "bad CRC accepted");
    for (uint8_t b : packet("{}")) complete += reader.feed(b, 1);
    check(complete == 1, "recovery failed");
  });
  test("oversized declared control length cannot allocate or execute", [] {
    room::ControlAssembler<32> reader; auto bytes = packet("{}"); room::put32(bytes.data() + 2, 1000000);
    for (size_t i = 0; i < 8; ++i) check(!reader.feed(bytes[i], 0), "oversize completed");
    check(reader.errors() == 1, "oversize not reported");
  });
  test("partial BLE input is completed once, not per write", [] {
    room::LineAssembler<32> reader; unsigned complete = 0;
    for (char c : std::string("{\"id\":1}\n")) complete += reader.feed(c, 0);
    check(complete == 1 && std::strcmp(reader.data(), "{\"id\":1}") == 0, "fragment completion wrong");
  });
  test("BLE overflow discards whole line and recovers only at delimiter", [] {
    room::LineAssembler<8> reader; unsigned complete = 0;
    for (char c : std::string("too-long-{}\n{}\n")) complete += reader.feed(c, 0);
    check(complete == 1 && reader.errors() == 1 && std::strcmp(reader.data(), "{}") == 0, "truncated suffix executed");
  });
  test("expired partial line cannot execute its suffix", [] {
    room::LineAssembler<32> reader; reader.feed('{', 0); reader.feed('}', 6000);
    check(!reader.feed('\n', 6000) && reader.errors() == 1, "expired partial completed");
    reader.feed('{', 7000); reader.feed('}', 7000); check(reader.feed('\n', 7000), "new line blocked");
  });
  test("slot encoding is bounded, portable and corruption-detecting", [] {
    room::RecordedSlot original; original.meta.slot = 4; original.meta.pulse_count = 17;
    std::strcpy(original.meta.label.data(), "SLEEP 26 AUTO");
    for (unsigned i = 0; i < original.meta.pulse_count; ++i) original.pulses[i] = 500;
    std::array<uint8_t, room::MAX_SLOT_BYTES> bytes{};
    const size_t n = room::encodeSlot(original, bytes.data(), bytes.size());
    check(n == 106 && bytes[12] == 17 && bytes[13] == 0, "portable header wrong");
    room::RecordedSlot decoded; check(room::decodeSlot(bytes.data(), n, decoded), "valid slot rejected");
    check(decoded.meta.slot == 4 && decoded.pulses[0] == 500, "slot did not roundtrip");
    bytes[80] ^= 1; check(!room::decodeSlot(bytes.data(), n, decoded), "corrupt raw payload accepted");
    check(decoded.pulses[0] == 500, "failed decode mutated prior record");
  });
  test("noise duration and oversized pulses cannot become learned slot", [] {
    room::RecordedSlot s; s.meta.slot = 1; std::strcpy(s.meta.label.data(), "quiet"); s.meta.pulse_count = 2;
    check(!room::validSlot(s), "noise accepted"); s.meta.pulse_count = 1025;
    check(!room::validSlot(s), "out-of-bounds accepted");
    s.meta.pulse_count = 100; s.pulses.fill(65000); check(!room::validSlot(s), "unbounded transmission accepted");
  });
  test("hex and fixed-size secret comparison reject malformed proofs", [] {
    uint8_t a[2]{}, b[2]{0x0a, 0xff};
    check(room::parseHex("0aff", 2, a) && room::equalSecret(a, b, 2), "valid proof rejected");
    check(!room::parseHex("0af", 2, a) && !room::parseHex("0agf", 2, a), "malformed hex accepted");
    b[1] ^= 1; check(!room::equalSecret(a, b, 2), "incorrect proof accepted");
  });
  std::cout << "RESULT " << passed << " passed, " << failed << " failed\n"; return failed ? 1 : 0;
}

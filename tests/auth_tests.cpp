#include "../firmware/smart_room/auth_core.hpp"
#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>

static void check(bool ok, const char *reason) { if (!ok) throw std::runtime_error(reason); }
static void challenge(room::AuthenticationGate &gate, uint32_t now = 0) {
  uint8_t session[16]{}, nonce[32]{};
  for (unsigned i = 0; i < 16; ++i) session[i] = static_cast<uint8_t>(i);
  for (unsigned i = 0; i < 32; ++i) nonce[i] = static_cast<uint8_t>(i + 16);
  gate.begin(session, nonce, now);
}
static const char *proof = "0000000000000000000000000000000000000000000000000000000000000000";
int main() {
  unsigned pass = 0, fail = 0;
  auto test = [&](const char *name, const std::function<void()> &body) {
    try { body(); ++pass; std::cout << "PASS " << name << '\n'; }
    catch (const std::exception &e) { ++fail; std::cout << "FAIL " << name << ": " << e.what() << '\n'; }
  };
  test("HMAC context binds protocol device session and challenge", [] {
    room::AuthenticationGate g; challenge(g); char text[192]{};
    const std::string expected = "smart-room/v1|f024f91080a4|000102030405060708090a0b0c0d0e0f|101112131415161718191a1b1c1d1e1f202122232425262728292a2b2c2d2e2f";
    check(g.context("f024f91080a4", text, sizeof(text)) == expected.size() && text == expected, "cross-language context differs");
  });
  test("only a valid one-use proof authorizes commands", [] {
    room::AuthenticationGate g; challenge(g); uint8_t expected[32]{};
    const std::string session = g.session(); check(!g.authorized(session.c_str()), "pre-auth controls allowed");
    check(g.prove(session.c_str(), proof, expected, 1) && g.authorized(session.c_str()), "valid proof failed");
    check(!g.prove(session.c_str(), proof, expected, 2), "proof reused");
  });
  test("incorrect proof consumes challenge without authorizing", [] {
    room::AuthenticationGate g; challenge(g); uint8_t expected[32]{}; expected[0] = 1;
    const std::string session = g.session();
    check(!g.prove(session.c_str(), proof, expected, 1), "wrong proof allowed"); expected[0] = 0;
    check(!g.prove(session.c_str(), proof, expected, 2) && !g.authorized(session.c_str()), "challenge reused after failure");
  });
  test("expired or previous-link proofs cannot authorize", [] {
    room::AuthenticationGate g; challenge(g); uint8_t expected[32]{};
    check(!g.prove("previous-session", proof, expected, 1), "old link admitted");
    check(!g.prove(g.session(), proof, expected, 30001), "expired challenge admitted");
  });
  test("claim requires encrypted-window authorization and matching session", [] {
    room::AuthenticationGate g; challenge(g);
    check(!g.claim(g.session(), 1, false), "closed pairing window admitted claim");
    check(!g.claim("wrong", 2, true), "wrong claim session admitted");
    check(g.claim(g.session(), 3, true) && g.authorized(g.session()), "approved claim rejected");
  });
  test("disconnect and new challenges remove authentication", [] {
    room::AuthenticationGate g; challenge(g); g.claim(g.session(), 1, true);
    const std::string old = g.session(); g.reset(); check(!g.authorized(old.c_str()), "disconnect retained rights");
    challenge(g, 10); check(!g.authorized(g.session()), "new challenge retained rights");
  });
  test("flat command accepts strings bools and integer fields only", [] {
    const std::string text = " {\"v\":1,\"op\":\"learn\",\"power\":true,\"label\":\"A \\\"B\\\" \\u0627\"} \n";
    check(room::flatCommand(text.c_str(), text.size()), "valid flat command rejected");
  });
  test("duplicate escaped nested and trailing command input is rejected", [] {
    for (const std::string text : {"{\"v\":1,\"v\":1}","{\"\\u0076\":1}","{\"v\":1,\"bad\":{}}", "{\"v\":1}junk", "{\"v\":1.0}", "{\"v\":true false}"})
      check(!room::flatCommand(text.c_str(), text.size()), "ambiguous command admitted");
  });
  test("escaped null cannot truncate an operation session proof or label", [] {
    for (const std::string text : {"{\"v\":1,\"op\":\"hello\\u0000extra\"}",
                                  "{\"v\":1,\"session\":\"0011\\u0000hidden\"}",
                                  "{\"v\":1,\"label\":\"valid\\u0000hidden\"}"})
      check(!room::flatCommand(text.c_str(), text.size()), "escaped null was normalized into a shorter C string");
  });
  test("unicode escapes require complete surrogate pairs", [] {
    for (const std::string text : {"{\"v\":1,\"label\":\"\\ud800\"}",
                                  "{\"v\":1,\"label\":\"\\udc00\"}",
                                  "{\"v\":1,\"label\":\"\\ud800\\u0061\"}"})
      check(!room::flatCommand(text.c_str(), text.size()), "invalid Unicode escape admitted");
    const std::string valid = "{\"v\":1,\"label\":\"\\ud83d\\ude00\"}";
    check(room::flatCommand(valid.c_str(), valid.size()), "complete Unicode pair rejected");
  });
  std::cout << "RESULT " << pass << " passed, " << fail << " failed\n"; return fail ? 1 : 0;
}

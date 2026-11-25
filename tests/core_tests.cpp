#include "../firmware/smart_room/room_core.hpp"

#include <functional>
#include <iostream>
#include <stdexcept>
#include <string>

using room::Engine;
using room::Mode;
using room::Presence;
using room::Scene;

static void require(bool condition, const char *message) {
  if (!condition) throw std::runtime_error(message);
}

static room::Config fastConfig() {
  room::Config c;
  c.ttl_ms = 1000; c.empty_ms = 10000; c.settle_ms = 1000;
  c.manual_ms = 60000; c.ir_gap_ms = 5000;
  return c;
}

static void freshFor(Engine &e, int count, uint32_t start, uint32_t duration,
                     uint32_t &sequence) {
  for (uint32_t offset = 0; offset <= duration; offset += 500) {
    require(e.observe(++sequence, count, 0, start + offset), "fresh observation rejected");
    e.tick(start + offset);
  }
}

int main() {
  unsigned passed = 0, failed = 0;
  auto test = [&](const char *name, const std::function<void()> &body) {
    try { body(); ++passed; std::cout << "PASS " << name << '\n'; }
    catch (const std::exception &e) { ++failed; std::cout << "FAIL " << name << ": " << e.what() << '\n'; }
  };

  test("boot is unknown, not zero", [] {
    Engine e; const auto s = e.tick(0);
    require(s.people == -1 && s.presence == Presence::Unknown && !s.lights && s.ir_slot == 0, "unsafe boot snapshot");
  });
  test("fresh visible people turn requested lights on", [] {
    Engine e(fastConfig()); require(e.observe(1, 2, 0, 0), "observation rejected");
    const auto s = e.tick(0);
    require(s.people == 2 && s.presence == Presence::Occupied && s.lights, "people did not illuminate");
  });
  test("analyzed frame age participates in freshness", [] {
    Engine e(fastConfig()); e.observe(1, 2, 900, 1000);
    require(e.tick(1050).people == 2, "still-fresh result lost");
    require(e.tick(1101).people == -1, "expired source still counted");
  });
  test("old and repeated sequence numbers are rejected", [] {
    Engine e(fastConfig()); require(e.observe(10, 2, 0, 0), "first rejected");
    require(!e.observe(9, 0, 0, 1) && !e.observe(10, 0, 0, 2), "stale sequence accepted");
    require(e.tick(2).people == 2, "old zero replaced current people");
  });
  test("invalid counts and ages are rejected", [] {
    Engine e(fastConfig());
    require(!e.observe(1, -2, 0, 0) && !e.observe(1, 101, 0, 0), "invalid count accepted");
    require(!e.observe(1, 0, 1001, 0), "expired observation accepted");
  });
  test("unknown does not automatically switch occupied room off", [] {
    Engine e(fastConfig()); e.observe(1, 1, 0, 0); e.tick(0);
    require(e.observe(2, -1, 0, 500), "explicit unknown rejected");
    const auto s = e.tick(20000);
    require(s.people == -1 && s.lights && s.ir_slot == 0, "unknown became empty-room command");
  });
  test("zero must remain continuously fresh for the grace period", [] {
    Engine e(fastConfig()); uint32_t seq = 0;
    freshFor(e, 1, 0, 1000, seq); freshFor(e, 0, 1500, 9500, seq);
    require(e.tick(11000).lights, "lights switched off before 10-second grace");
    e.observe(++seq, 0, 0, 11500); const auto s = e.tick(11500);
    require(!s.lights && s.scene == Scene::Sleep && s.ir_slot == 4, "continuous empty room did not select sleep");
  });
  test("a source gap resets the empty grace", [] {
    Engine e(fastConfig()); uint32_t seq = 0;
    freshFor(e, 1, 0, 1000, seq); freshFor(e, 0, 1500, 5000, seq);
    e.tick(8000); e.observe(++seq, 0, 0, 20000);
    require(e.tick(20000).lights, "stale gap counted as continuous emptiness");
  });
  test("a gap is noticed even without an intervening tick", [] {
    Engine e(fastConfig()); uint32_t seq = 0;
    freshFor(e, 1, 0, 1000, seq); freshFor(e, 0, 1500, 5000, seq);
    e.observe(++seq, 0, 0, 20000);
    require(e.tick(20000).lights, "new observation concealed stale gap");
  });
  test("positive observation breaks empty continuity even between ticks", [] {
    Engine e(fastConfig()); uint32_t seq = 0;
    freshFor(e, 1, 0, 1000, seq); freshFor(e, 0, 1500, 9000, seq);
    e.observe(++seq, 1, 0, 11000); e.observe(++seq, 0, 0, 11500);
    const auto s = e.tick(11500);
    require(s.lights && s.empty_remaining_ms == 10000, "intervening person hidden by batched input");
  });
  test("an intervening band breaks debounce even between ticks", [] {
    Engine e(fastConfig()); e.observe(1, 2, 0, 0); e.tick(0);
    e.observe(2, 5, 0, 500); e.observe(3, 2, 0, 1000);
    require(e.tick(1000).ir_slot == 0, "batched band noise satisfied continuous debounce");
  });
  test("returning people cancel empty-room sleep", [] {
    Engine e(fastConfig()); uint32_t seq = 0;
    freshFor(e, 0, 0, 10000, seq); require(!e.tick(10000).lights, "empty room on");
    e.observe(++seq, 1, 0, 10500); require(e.tick(10500).lights, "returning people did not request lights");
  });
  test("bands select saved quiet normal and busy scenes after debounce", [] {
    Engine e(fastConfig()); uint32_t seq = 0;
    freshFor(e, 2, 0, 1000, seq); require(e.tick(1000).ir_slot == 1, "quiet band wrong");
    freshFor(e, 3, 1500, 1000, seq); require(e.tick(2500).ir_slot == 2, "normal band wrong");
    freshFor(e, 5, 3000, 1000, seq); require(e.tick(4000).ir_slot == 3, "busy band wrong");
  });
  test("single-frame band noise does not immediately send another scene", [] {
    Engine e(fastConfig()); uint32_t seq = 0;
    freshFor(e, 2, 0, 1000, seq); e.observe(++seq, 5, 0, 1500);
    require(e.tick(1500).ir_slot == 1, "band noise changed AC immediately");
    e.observe(++seq, 2, 0, 2000); require(e.tick(2000).ir_slot == 1, "return to band failed");
  });
  test("manual lighting overrides occupancy until explicit lease expires", [] {
    Engine e(fastConfig()); require(e.manualLights(false, 0), "manual command rejected");
    e.observe(1, 4, 0, 1000); require(!e.tick(1000).lights && e.tick(1000).mode == Mode::Manual, "auto defeated manual");
    e.observe(2, 4, 0, 60000); require(e.tick(60000).lights && e.tick(60000).mode == Mode::Auto, "lease did not expire");
  });
  test("sleep is explicit and works without a pretend sleep classifier", [] {
    Engine e(fastConfig()); require(e.setMode(Mode::Sleep, 0, 60000), "sleep rejected");
    const auto s = e.tick(100);
    require(s.mode == Mode::Sleep && !s.lights && s.ir_slot == 4 && s.people == -1, "explicit sleep missing");
  });
  test("manual AC chooses only the explicit saved slot", [] {
    Engine e(fastConfig()); require(e.manualIr(7, 0), "manual IR rejected");
    e.observe(1, 9, 0, 1000); require(e.tick(1000).ir_slot == 7, "automatic band overrode manual IR");
    require(!e.manualIr(0, 2000) && !e.manualIr(17, 2000), "invalid slot accepted");
  });
  test("missing learned IR has no send action", [] {
    Engine e(fastConfig()); e.manualIr(7, 0);
    require(e.pendingIr(0, 0) == 0, "unlearned slot sent");
    require(e.pendingIr(0, 1U << 7) == 7, "learned slot unavailable");
  });
  test("IR rate limit and no duplicate repeated-frame transmission", [] {
    Engine e(fastConfig()); e.manualIr(7, 0);
    require(e.pendingIr(0, 1U << 7) == 7, "first IR missing"); e.noteIrSent(7, 0);
    require(e.pendingIr(10000, 1U << 7) == 0, "same slot repeatedly sent");
    e.manualIr(8, 1000);
    require(e.pendingIr(4999, 1U << 8) == 0 && e.pendingIr(5000, 1U << 8) == 8, "IR interval ignored");
  });
  test("relearning the selected slot invalidates prior waveform acknowledgment", [] {
    Engine e(fastConfig()); e.manualIr(7, 0); e.noteIrSent(7, 0); e.invalidateSent(7);
    require(!e.sentCurrent(7), "invalidated waveform still reported sent");
    require(e.pendingIr(5000, 1U << 7) == 7, "new waveform suppressed as old");
  });
  test("same-slot explicit repeat stays queued during the IR cooldown", [] {
    Engine e(fastConfig()); e.manualIr(7, 0); e.noteIrSent(7, 0);
    require(e.sentCurrent(7), "completed pulse emission not retained");
    e.manualIr(7, 1000); e.invalidateSent(7);
    require(!e.sentCurrent(7) && e.pendingIr(1000, 1U << 7) == 0, "cooldown is falsely a sent acknowledgment");
    require(e.pendingIr(5000, 1U << 7) == 7, "repeat missing after cooldown");
    e.noteIrSent(7, 5000); require(e.sentCurrent(7), "repeat completion not retained");
  });
  test("millis wraparound preserves TTL and manual lease", [] {
    Engine e(fastConfig()); const uint32_t start = 0xfffffff0U;
    e.manualLights(true, start, 60000); e.observe(1, 1, 0, start);
    require(e.tick(32).people == 1 && e.tick(32).mode == Mode::Manual, "wrap broke fresh/manual state");
    require(e.tick(2000).people == -1, "wrap prevented expiry");
  });
  test("sensor session reset rejects retained count without losing last lights", [] {
    Engine e(fastConfig()); e.observe(100, 1, 0, 0); e.tick(0); e.resetSensor();
    require(e.tick(1).people == -1 && e.tick(1).lights, "session reset changed outputs or retained count");
    require(e.observe(1, 2, 0, 2), "new session sequence rejected");
  });
  test("invalid configuration is transactional", [] {
    Engine e(fastConfig()); auto c = fastConfig(); c.empty_ms = 1;
    require(!e.configure(c) && e.config().empty_ms == 10000, "unsafe grace accepted");
    c = fastConfig(); c.quiet_max = c.normal_max; require(!e.configure(c), "overlapping bands accepted");
    c = fastConfig(); c.sleep_slot = 17; require(!e.configure(c), "invalid profile accepted");
    c = fastConfig(); c.quiet_max = 1; require(e.configure(c) && e.config().quiet_max == 1, "valid config rejected");
  });
  test("one active phone at a time, with identity-aware disconnect", [] {
    room::ExclusiveConnection link;
    require(link.connect(10) && link.owns(10), "first connection rejected");
    require(!link.connect(11) && !link.owns(11), "second connection admitted");
    link.disconnect(11); require(link.owns(10), "rejected peer disconnected owner");
    link.disconnect(10); require(link.connect(11), "new connection after release rejected");
  });
  test("request identifiers reject duplicate and out-of-order execution", [] {
    room::RequestSequence seq;
    require(seq.accept(1) && !seq.accept(1) && !seq.accept(0), "duplicate request accepted");
    require(seq.accept(3) && !seq.accept(2), "old request accepted");
    seq.reset(); require(seq.accept(1), "new session cannot start fresh");
  });
  std::cout << "RESULT " << passed << " passed, " << failed << " failed\n";
  return failed ? 1 : 0;
}

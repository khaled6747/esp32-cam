#pragma once

#include <cstdint>

namespace room {

enum class Mode { Auto, Manual, Sleep };
enum class Presence { Unknown, Occupied, Empty };
enum class Scene { None, Quiet, Normal, Busy, Sleep, Manual };

struct Config {
  uint32_t ttl_ms = 2000;
  uint32_t empty_ms = 120000;
  uint32_t settle_ms = 5000;
  uint32_t manual_ms = 1800000;
  uint32_t ir_gap_ms = 15000;
  int quiet_max = 2;
  int normal_max = 4;
  uint8_t quiet_slot = 1, normal_slot = 2, busy_slot = 3, sleep_slot = 4;
};

struct Snapshot {
  Mode mode = Mode::Auto;
  Presence presence = Presence::Unknown;
  Scene scene = Scene::None;
  int people = -1;
  bool lights = false;
  uint8_t ir_slot = 0;
  uint32_t override_remaining_ms = 0;
  uint32_t empty_remaining_ms = 0;
};

// Pure controller policy. Time is unsigned monotonic milliseconds; all accepted
// durations are below half the uint32_t range so subtraction survives millis wrap.
class Engine {
 public:
  explicit Engine(Config config = {}) { configure(config); }
  static bool valid(const Config &c) {
    const auto slot = [](uint8_t s) { return s >= 1 && s <= 16; };
    return c.ttl_ms >= 1000 && c.ttl_ms <= 10000
        && c.empty_ms >= 10000 && c.empty_ms <= 3600000
        && c.empty_ms > c.ttl_ms
        && c.settle_ms >= 1000 && c.settle_ms <= 60000
        && c.manual_ms >= 60000 && c.manual_ms <= 43200000
        && c.ir_gap_ms >= 5000 && c.ir_gap_ms <= 300000
        && c.quiet_max >= 1 && c.quiet_max < c.normal_max && c.normal_max <= 50
        && slot(c.quiet_slot) && slot(c.normal_slot)
        && slot(c.busy_slot) && slot(c.sleep_slot);
  }
  bool configure(const Config &c) {
    if (!valid(c)) return false;
    config_ = c;
    clearContinuity();
    return true;
  }
  const Config &config() const { return config_; }
  void resetSensor() {
    known_ = false;
    has_sequence_ = false;
    clearContinuity();
  }
  bool observe(uint32_t sequence, int people, uint32_t source_age_ms, uint32_t now) {
    if (people < -1 || people > 100 || source_age_ms > config_.ttl_ms) return false;
    if (has_sequence_ && static_cast<int32_t>(sequence - sequence_) <= 0) return false;
    // A fresh packet cannot erase a gap in the previous stream. Zero occupancy
    // must be continuously supported by source frames, not just two endpoints.
    if (!known_ || elapsed(now, source_at_) > config_.ttl_ms) clearContinuity();
    if (people > 0) {
      empty_active_ = false;
      if (candidate_active_ && candidate_ != bandFor(people)) candidate_active_ = false;
    } else {
      candidate_active_ = false;
    }
    sequence_ = sequence;
    has_sequence_ = true;
    people_ = people;
    known_ = people >= 0;
    source_at_ = now - source_age_ms;
    if (!known_) clearContinuity();
    return true;
  }
  bool setMode(Mode mode, uint32_t now, uint32_t lease_ms = 0) {
    if (mode != Mode::Auto && mode != Mode::Manual && mode != Mode::Sleep) return false;
    const uint32_t lease = lease_ms ? lease_ms : config_.manual_ms;
    if (mode != Mode::Auto && (lease < 60000 || lease > 43200000)) return false;
    mode_ = mode;
    mode_at_ = now;
    lease_ms_ = lease;
    manual_slot_ = 0;
    clearContinuity();
    if (mode == Mode::Sleep) { lights_ = false; scene_ = Scene::Sleep; }
    return true;
  }
  bool manualLights(bool on, uint32_t now, uint32_t lease_ms = 0) {
    const uint8_t keep = mode_ == Mode::Manual ? manual_slot_ : 0;
    if (!setMode(Mode::Manual, now, lease_ms)) return false;
    lights_ = on;
    manual_slot_ = keep;
    return true;
  }
  bool manualIr(uint8_t slot, uint32_t now, uint32_t lease_ms = 0) {
    if (slot < 1 || slot > 16 || !setMode(Mode::Manual, now, lease_ms)) return false;
    manual_slot_ = slot;
    return true;
  }
  Snapshot tick(uint32_t now) {
    if (mode_ != Mode::Auto && elapsed(now, mode_at_) >= lease_ms_) {
      mode_ = Mode::Auto;
      manual_slot_ = 0;
      clearContinuity();
    }
    const bool fresh = known_ && elapsed(now, source_at_) <= config_.ttl_ms;
    Snapshot s;
    s.mode = mode_;
    s.people = fresh ? people_ : -1;
    s.presence = !fresh ? Presence::Unknown : (people_ ? Presence::Occupied : Presence::Empty);
    if (mode_ != Mode::Auto) {
      s.override_remaining_ms = lease_ms_ - elapsed(now, mode_at_);
      s.scene = mode_ == Mode::Sleep ? Scene::Sleep : Scene::Manual;
      s.ir_slot = mode_ == Mode::Sleep ? config_.sleep_slot : manual_slot_;
    } else if (!fresh) {
      clearContinuity();  // Preserve last requested outputs; never equate unknown with zero.
      s.scene = scene_;
      s.ir_slot = 0;
    } else if (people_ == 0) {
      candidate_active_ = false;
      if (!empty_active_) { empty_active_ = true; empty_at_ = now; }
      const uint32_t duration = elapsed(now, empty_at_);
      s.empty_remaining_ms = duration >= config_.empty_ms ? 0 : config_.empty_ms - duration;
      if (duration >= config_.empty_ms) { lights_ = false; scene_ = Scene::Sleep; }
      s.scene = scene_;
      s.ir_slot = scene_ == Scene::Sleep ? config_.sleep_slot : 0;
    } else {
      empty_active_ = false;
      lights_ = true;
      const Scene band = bandFor(people_);
      if (!candidate_active_ || candidate_ != band) {
        candidate_ = band; candidate_at_ = now; candidate_active_ = true;
      }
      if (elapsed(now, candidate_at_) >= config_.settle_ms) scene_ = band;
      s.scene = scene_;
      s.ir_slot = slotFor(scene_);
    }
    s.lights = lights_;
    return s;
  }
  uint8_t pendingIr(uint32_t now, uint32_t available_mask) {
    const uint8_t slot = tick(now).ir_slot;
    if (!slot || !(available_mask & (1U << slot)) || slot == sent_slot_) return 0;
    if (has_sent_ && elapsed(now, sent_at_) < config_.ir_gap_ms) return 0;
    return slot;
  }
  void noteIrSent(uint8_t slot, uint32_t now) {
    if (slot < 1 || slot > 16) return;
    sent_slot_ = slot; sent_at_ = now; has_sent_ = true;
  }
  void invalidateSent(uint8_t slot) { if (sent_slot_ == slot) sent_slot_ = 0; }
  bool sentCurrent(uint8_t slot) const { return slot && sent_slot_ == slot; }
 private:
  static uint32_t elapsed(uint32_t now, uint32_t then) { return now - then; }
  Scene bandFor(int people) const {
    return people <= config_.quiet_max ? Scene::Quiet
         : people <= config_.normal_max ? Scene::Normal : Scene::Busy;
  }
  void clearContinuity() { empty_active_ = false; candidate_active_ = false; }
  uint8_t slotFor(Scene scene) const {
    switch (scene) {
      case Scene::Quiet: return config_.quiet_slot;
      case Scene::Normal: return config_.normal_slot;
      case Scene::Busy: return config_.busy_slot;
      default: return 0;
    }
  }
  Config config_{};
  Mode mode_ = Mode::Auto;
  Scene scene_ = Scene::None, candidate_ = Scene::None;
  bool known_ = false, has_sequence_ = false, lights_ = false;
  bool empty_active_ = false, candidate_active_ = false, has_sent_ = false;
  int people_ = -1;
  uint32_t source_at_ = 0, sequence_ = 0, empty_at_ = 0, candidate_at_ = 0;
  uint32_t mode_at_ = 0, lease_ms_ = 0, sent_at_ = 0;
  uint8_t manual_slot_ = 0, sent_slot_ = 0;
};

class ExclusiveConnection {
 public:
  bool connect(uint16_t id) {
    if (id == invalid || (id_ != invalid && id_ != id)) return false;
    id_ = id; return true;
  }
  void disconnect(uint16_t id) { if (id_ == id) id_ = invalid; }
  bool owns(uint16_t id) const { return id != invalid && id_ == id; }
 private:
  static constexpr uint16_t invalid = 0xffff;
  uint16_t id_ = invalid;
};

class RequestSequence {
 public:
  bool accept(uint32_t id) {
    if (!id || id <= last_) return false;
    last_ = id; return true;
  }
  void reset() { last_ = 0; }
 private:
  uint32_t last_ = 0;
};

}  // namespace room

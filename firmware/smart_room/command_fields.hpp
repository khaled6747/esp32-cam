#pragma once

// These are the actual typed field validators used by the device dispatcher.
// Keeping them free of Arduino I/O makes cross-language contract checks possible
// with the installed ArduinoJson headers and the existing native compiler.
#include <ArduinoJson.h>
#include <initializer_list>
#include "auth_core.hpp"
#include "room_core.hpp"

namespace room::fields {

inline bool exact(JsonObjectConst object, std::initializer_list<const char *> names) {
  if (object.size() != names.size()) return false;
  for (const auto *name : names) if (object[name].isNull()) return false;
  return true;
}
inline bool number(JsonObjectConst object, const char *name, uint32_t &out, uint32_t low, uint32_t high) {
  if (!object[name].is<uint32_t>()) return false;
  out = object[name].as<uint32_t>(); return out >= low && out <= high;
}
inline bool configuration(JsonObjectConst object, Config &config) {
  uint32_t quiet, normal, qslot, nslot, bslot, sslot;
  if (!number(object,"ttl_ms",config.ttl_ms,1000,10000) || !number(object,"empty_ms",config.empty_ms,10000,3600000)
      || !number(object,"settle_ms",config.settle_ms,1000,60000) || !number(object,"manual_ms",config.manual_ms,60000,43200000)
      || !number(object,"ir_gap_ms",config.ir_gap_ms,5000,300000) || !number(object,"quiet_max",quiet,1,49)
      || !number(object,"normal_max",normal,2,50) || !number(object,"quiet_slot",qslot,1,16)
      || !number(object,"normal_slot",nslot,1,16) || !number(object,"busy_slot",bslot,1,16) || !number(object,"sleep_slot",sslot,1,16)) return false;
  config.quiet_max = quiet; config.normal_max = normal; config.quiet_slot = qslot; config.normal_slot = nslot;
  config.busy_slot = bslot; config.sleep_slot = sslot; return Engine::valid(config);
}
inline void putConfiguration(JsonObject object, const Config &config) {
  object["ttl_ms"] = config.ttl_ms; object["empty_ms"] = config.empty_ms; object["settle_ms"] = config.settle_ms;
  object["manual_ms"] = config.manual_ms; object["ir_gap_ms"] = config.ir_gap_ms;
  object["quiet_max"] = config.quiet_max; object["normal_max"] = config.normal_max;
  object["quiet_slot"] = config.quiet_slot; object["normal_slot"] = config.normal_slot;
  object["busy_slot"] = config.busy_slot; object["sleep_slot"] = config.sleep_slot;
}
inline bool metadata(JsonObjectConst object, SlotMeta &meta, bool learn) {
  uint32_t temperature, fan, mode, slot = 1, hz = 38000;
  if (!number(object,"temperature",temperature,16,30) || !number(object,"fan",fan,0,3)
      || !number(object,"mode",mode,0,4) || !object["power"].is<bool>() || !object["sleep"].is<bool>()) return false;
  if (learn && (!number(object,"slot",slot,1,16) || !number(object,"hz",hz,36000,56000) || !object["label"].is<const char *>())) return false;
  meta.slot = slot; meta.temperature = temperature; meta.fan = fan; meta.mode = mode; meta.carrier_hz = hz;
  meta.power = object["power"].as<bool>(); meta.sleep = object["sleep"].as<bool>();
  if (learn) {
    const char *label = object["label"].as<const char *>(); const size_t length = std::strlen(label);
    if (!length || length >= meta.label.size() || !validUtf8(label, length)) return false;
    std::memcpy(meta.label.data(), label, length + 1);
  } else std::strcpy(meta.label.data(), "manual");
  return validMeta(meta);
}
inline bool localAction(JsonObjectConst object, const char *session, const char *phrase, uint32_t &id) {
  return exact(object,{"v","op","id","session","confirm"}) && number(object,"id",id,1,2147483647)
      && session && session[0] && object["session"].is<const char *>()
      && !std::strcmp(session,object["session"].as<const char *>())
      && object["confirm"].is<const char *>() && !std::strcmp(phrase,object["confirm"].as<const char *>());
}

}  // namespace room::fields

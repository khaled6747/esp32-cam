#pragma once

#include <Arduino.h>
#include <ArduinoJson.h>
#include <Preferences.h>
#include <IRrecv.h>
#include <IRsend.h>
#include <IRutils.h>
#include <esp_camera.h>
#include <esp_mac.h>
#include <esp_random.h>
#include <esp32-hal-bt.h>
#include <esp_bt_main.h>
#include <esp_gap_ble_api.h>
#include <esp_gatts_api.h>
#include <esp_gatt_common_api.h>
#include <mbedtls/md.h>
#include <mbedtls/platform_util.h>
#include <freertos/FreeRTOS.h>
#include <freertos/queue.h>
#include <algorithm>
#include <atomic>
#include <initializer_list>
#include "auth_core.hpp"
#include "command_fields.hpp"
#include "room_core.hpp"
#include "peripherals.hpp"

namespace smart {

constexpr uint16_t NO_CONNECTION = 0xffff;
enum class LinkEvent : uint8_t { Connected, Disconnected, Secure, Write };
struct Input {
  LinkEvent kind;
  uint16_t connection = NO_CONNECTION, length = 0;
  uint32_t generation = 0;
  uint8_t bytes[200]{};
};
struct Link {
  uint16_t id = NO_CONNECTION, mtu = 23;
  uint32_t generation = 0;
  bool secure = false, subscribed = false;
  uint8_t address[6]{};
};

room::Engine engine;
room::AuthenticationGate auth;
room::RequestSequence requests;
room::RequestSequence usb_requests;
room::LineAssembler<768> lines;
room::ControlAssembler<768> control;
SlotStore slots;
RoomOled oled;
Preferences preferences;
IRsend sender(IR_TX_PIN);
IRrecv receiver(IR_RX_PIN, room::MAX_IR_PULSES, 100, true);
decode_results received;
QueueHandle_t incoming = nullptr;
portMUX_TYPE link_mux = portMUX_INITIALIZER_UNLOCKED;
Link link;
std::atomic<esp_gatt_if_t> gatt_if{ESP_GATT_IF_NONE};
uint16_t handles[6]{};
std::atomic<bool> ble_ready{false};
bool camera_ready = false, preferences_ready = false;
bool owner_exists = false, learning = false;
bool security_display_ready = false, security_owner_exists = false;
std::atomic<uint8_t> adv_pending{3};
uint32_t current_generation = 0, connection_at = 0, pairing_at = 0;
uint32_t passkey = 0, last_status_at = 0, last_camera_at = 0;
uint32_t rx_queue_errors = 0, last_frame = 0, last_sequence = 0;
std::atomic<uint32_t> tx_errors{0};
uint8_t last_sent_slot = 0, ir_fault_slot = 0;
const char *ir_fault = "none";
std::array<uint8_t, 32> owner_key{};
std::array<char, 13> device_id{};
std::array<char, 17> boot_id{};
std::array<char, 33> host_session{};
room::SlotMeta learning_meta;
uint32_t learning_at = 0;

// Native IDF attributes avoid the C++ BLE wrapper's growing prepare-write
// accumulation. Long/prepared writes and nonzero offsets are explicitly denied.
enum Attribute { Service, CommandDeclaration, CommandValue, EventDeclaration, EventValue, Cccd };
uint16_t primary_uuid = ESP_GATT_UUID_PRI_SERVICE;
uint16_t declaration_uuid = ESP_GATT_UUID_CHAR_DECLARE;
uint16_t cccd_uuid = ESP_GATT_UUID_CHAR_CLIENT_CONFIG;
uint8_t service_uuid[16] = {0x01,0x93,0x4d,0x8e,0xf3,0x50,0x6f,0xa3,0xe0,0x47,0xad,0x24,0xa0,0x5c,0x87,0x6f};
uint8_t command_uuid[16] = {0x02,0x93,0x4d,0x8e,0xf3,0x50,0x6f,0xa3,0xe0,0x47,0xad,0x24,0xa0,0x5c,0x87,0x6f};
uint8_t event_uuid[16] = {0x03,0x93,0x4d,0x8e,0xf3,0x50,0x6f,0xa3,0xe0,0x47,0xad,0x24,0xa0,0x5c,0x87,0x6f};
uint8_t write_property = ESP_GATT_CHAR_PROP_BIT_WRITE;
uint8_t notify_property = ESP_GATT_CHAR_PROP_BIT_NOTIFY;
uint8_t empty_value[2]{};
esp_gatts_attr_db_t attributes[6] = {
  {{ESP_GATT_AUTO_RSP}, {ESP_UUID_LEN_16, reinterpret_cast<uint8_t *>(&primary_uuid), ESP_GATT_PERM_READ, 16, 16, service_uuid}},
  {{ESP_GATT_AUTO_RSP}, {ESP_UUID_LEN_16, reinterpret_cast<uint8_t *>(&declaration_uuid), ESP_GATT_PERM_READ, 1, 1, &write_property}},
  {{ESP_GATT_RSP_BY_APP}, {ESP_UUID_LEN_128, command_uuid, ESP_GATT_PERM_WRITE_ENC_MITM, 200, 0, empty_value}},
  {{ESP_GATT_AUTO_RSP}, {ESP_UUID_LEN_16, reinterpret_cast<uint8_t *>(&declaration_uuid), ESP_GATT_PERM_READ, 1, 1, &notify_property}},
  {{ESP_GATT_RSP_BY_APP}, {ESP_UUID_LEN_128, event_uuid, ESP_GATT_PERM_READ_ENC_MITM, 200, 0, empty_value}},
  {{ESP_GATT_RSP_BY_APP}, {ESP_UUID_LEN_16, reinterpret_cast<uint8_t *>(&cccd_uuid), ESP_GATT_PERM_READ_ENC_MITM | ESP_GATT_PERM_WRITE_ENC_MITM, 2, 2, empty_value}},
};
esp_ble_adv_params_t advertising = {
  .adv_int_min = 0x100, .adv_int_max = 0x180, .adv_type = ADV_TYPE_IND,
  .own_addr_type = BLE_ADDR_TYPE_PUBLIC, .peer_addr = {}, .peer_addr_type = BLE_ADDR_TYPE_PUBLIC,
  .channel_map = ADV_CHNL_ALL, .adv_filter_policy = ADV_FILTER_ALLOW_SCAN_ANY_CON_ANY,
};

Link readLink() {
  portENTER_CRITICAL(&link_mux); const Link copy = link; portEXIT_CRITICAL(&link_mux); return copy;
}
void disconnect(uint16_t id) {
  if (gatt_if != ESP_GATT_IF_NONE && id != NO_CONNECTION) esp_ble_gatts_close(gatt_if, id);
}
bool push(Input &event) {
  if (incoming && xQueueSend(incoming, &event, 0) == pdTRUE) return true;
  portENTER_CRITICAL(&link_mux); ++rx_queue_errors; portEXIT_CRITICAL(&link_mux);
  disconnect(event.connection); return false;
}
void randomHex(char *out, size_t bytes) {
  constexpr const char *digits = "0123456789abcdef";
  for (size_t i = 0; i < bytes; ++i) {
    const uint8_t value = static_cast<uint8_t>(esp_random());
    out[i * 2] = digits[value >> 4]; out[i * 2 + 1] = digits[value & 15];
  }
  out[bytes * 2] = 0;
}
bool pairingWindow(uint32_t now) {
  return oled.ready() && static_cast<uint32_t>(now - pairing_at) <= 120000;
}
void advertiseIfFree() {
  if (ble_ready && !adv_pending && readLink().id == NO_CONNECTION)
    if (esp_ble_gap_start_advertising(&advertising) != ESP_OK) ++tx_errors;
}

void gapCallback(esp_gap_ble_cb_event_t event, esp_ble_gap_cb_param_t *param) {
  if (event == ESP_GAP_BLE_ADV_DATA_SET_COMPLETE_EVT || event == ESP_GAP_BLE_SCAN_RSP_DATA_SET_COMPLETE_EVT) {
    if (event == ESP_GAP_BLE_ADV_DATA_SET_COMPLETE_EVT) {
      if (param->adv_data_cmpl.status != ESP_BT_STATUS_SUCCESS) { ++tx_errors; return; }
      adv_pending.fetch_and(static_cast<uint8_t>(~1U));
    } else {
      if (param->scan_rsp_data_cmpl.status != ESP_BT_STATUS_SUCCESS) { ++tx_errors; return; }
      adv_pending.fetch_and(static_cast<uint8_t>(~2U));
    }
    advertiseIfFree(); return;
  }
  const Link peer = readLink();
  if (peer.id == NO_CONNECTION) return;
  if (event == ESP_GAP_BLE_SEC_REQ_EVT) {
    const bool matches = std::memcmp(peer.address, param->ble_security.ble_req.bd_addr, 6) == 0;
    portENTER_CRITICAL(&link_mux);
    const bool allowed = security_display_ready || security_owner_exists;
    portEXIT_CRITICAL(&link_mux);
    esp_ble_gap_security_rsp(param->ble_security.ble_req.bd_addr, matches && allowed);
  } else if (event == ESP_GAP_BLE_PASSKEY_NOTIF_EVT) {
    if (std::memcmp(peer.address, param->ble_security.key_notif.bd_addr, 6) != 0) return;
    portENTER_CRITICAL(&link_mux);
    passkey = param->ble_security.key_notif.passkey;
    const bool can_display = security_display_ready;
    portEXIT_CRITICAL(&link_mux);
    if (!can_display) disconnect(peer.id);
  } else if (event == ESP_GAP_BLE_PASSKEY_REQ_EVT) {
    esp_ble_passkey_reply(param->ble_security.ble_req.bd_addr, false, 0);
  } else if (event == ESP_GAP_BLE_NC_REQ_EVT) {
    // Display-only hardware cannot safely confirm numeric comparison.
    esp_ble_confirm_reply(param->ble_security.key_notif.bd_addr, false);
  } else if (event == ESP_GAP_BLE_AUTH_CMPL_EVT) {
    const auto &result = param->ble_security.auth_cmpl;
    if (std::memcmp(peer.address, result.bd_addr, 6) != 0) return;
    const bool strong = result.success && (result.auth_mode & ESP_LE_AUTH_REQ_SC_ONLY)
                                      && (result.auth_mode & ESP_LE_AUTH_REQ_MITM);
    portENTER_CRITICAL(&link_mux);
    if (link.id == peer.id && link.generation == peer.generation) link.secure = strong;
    portEXIT_CRITICAL(&link_mux);
    if (!strong) { disconnect(peer.id); return; }
    Input input{}; input.kind = LinkEvent::Secure; input.connection = peer.id; input.generation = peer.generation;
    push(input);
  }
}

void gattCallback(esp_gatts_cb_event_t event, esp_gatt_if_t interface, esp_ble_gatts_cb_param_t *param) {
  if (event == ESP_GATTS_REG_EVT) {
    if (param->reg.status != ESP_GATT_OK) return;
    gatt_if = interface;
    esp_ble_gatts_create_attr_tab(attributes, interface, 6, 0);
  } else if (event == ESP_GATTS_CREAT_ATTR_TAB_EVT) {
    if (param->add_attr_tab.status != ESP_GATT_OK || param->add_attr_tab.num_handle != 6) return;
    std::memcpy(handles, param->add_attr_tab.handles, sizeof(handles));
    if (esp_ble_gatts_start_service(handles[Service]) != ESP_OK) ++tx_errors;
  } else if (event == ESP_GATTS_START_EVT) {
    ble_ready = param->start.status == ESP_GATT_OK && param->start.service_handle == handles[Service];
    advertiseIfFree();
  } else if (event == ESP_GATTS_CONNECT_EVT) {
    bool accepted = false; Input input{}; input.kind = LinkEvent::Connected;
    portENTER_CRITICAL(&link_mux);
    if (link.id == NO_CONNECTION) {
      link.id = param->connect.conn_id; ++link.generation; link.secure = false; link.subscribed = false; link.mtu = 23;
      std::memcpy(link.address, param->connect.remote_bda, 6); accepted = true;
    }
    input.connection = param->connect.conn_id; input.generation = link.generation;
    portEXIT_CRITICAL(&link_mux);
    esp_ble_gap_stop_advertising();
    if (!accepted) { disconnect(input.connection); return; }
    push(input);
  } else if (event == ESP_GATTS_DISCONNECT_EVT) {
    Input input{}; input.kind = LinkEvent::Disconnected; input.connection = param->disconnect.conn_id;
    bool owner_link = false;
    portENTER_CRITICAL(&link_mux);
    if (link.id == input.connection) {
      input.generation = link.generation; link.id = NO_CONNECTION; link.secure = false; link.subscribed = false; owner_link = true;
    }
    portEXIT_CRITICAL(&link_mux);
    if (owner_link) push(input);
  } else if (event == ESP_GATTS_MTU_EVT) {
    portENTER_CRITICAL(&link_mux);
    if (link.id == param->mtu.conn_id) link.mtu = param->mtu.mtu;
    portEXIT_CRITICAL(&link_mux);
  } else if (event == ESP_GATTS_WRITE_EVT) {
    const Link peer = readLink(); esp_gatt_status_t result = ESP_GATT_OK;
    if (param->write.conn_id != peer.id || !peer.secure) result = ESP_GATT_INSUF_AUTHENTICATION;
    else if (param->write.is_prep || param->write.offset) result = ESP_GATT_REQ_NOT_SUPPORTED;
    else if (param->write.handle == handles[Cccd]) {
      if (param->write.len != 2 || param->write.value[1] || param->write.value[0] > 1) result = ESP_GATT_INVALID_ATTR_LEN;
      else {
        portENTER_CRITICAL(&link_mux);
        if (link.id == peer.id && link.generation == peer.generation) link.subscribed = param->write.value[0] == 1;
        portEXIT_CRITICAL(&link_mux);
      }
    } else if (param->write.handle == handles[CommandValue]) {
      if (!param->write.need_rsp || !param->write.len || param->write.len > 200) result = ESP_GATT_INVALID_ATTR_LEN;
      else {
        Input input{}; input.kind = LinkEvent::Write; input.connection = peer.id; input.generation = peer.generation;
        input.length = param->write.len; std::memcpy(input.bytes, param->write.value, input.length);
        if (!push(input)) result = ESP_GATT_INSUF_RESOURCE;
      }
    } else result = ESP_GATT_WRITE_NOT_PERMIT;
    if (param->write.need_rsp) esp_ble_gatts_send_response(interface, param->write.conn_id, param->write.trans_id, result, nullptr);
  } else if (event == ESP_GATTS_EXEC_WRITE_EVT) {
    esp_ble_gatts_send_response(interface, param->exec_write.conn_id, param->exec_write.trans_id, ESP_GATT_REQ_NOT_SUPPORTED, nullptr);
  } else if (event == ESP_GATTS_READ_EVT) {
    const Link peer = readLink(); esp_gatt_rsp_t response{};
    const bool allowed = param->read.conn_id == peer.id && peer.secure && param->read.handle == handles[Cccd] && !param->read.offset;
    response.attr_value.handle = handles[Cccd]; response.attr_value.len = 2; response.attr_value.value[0] = peer.subscribed ? 1 : 0;
    if (param->read.need_rsp) esp_ble_gatts_send_response(interface, param->read.conn_id, param->read.trans_id,
      allowed ? ESP_GATT_OK : ESP_GATT_READ_NOT_PERMIT, allowed ? &response : nullptr);
  }
}

bool setupBle() {
  incoming = xQueueCreate(12, sizeof(Input)); if (!incoming || !btStart()) return false;
  if (esp_bluedroid_get_status() == ESP_BLUEDROID_STATUS_UNINITIALIZED && esp_bluedroid_init() != ESP_OK) return false;
  if (esp_bluedroid_get_status() != ESP_BLUEDROID_STATUS_ENABLED && esp_bluedroid_enable() != ESP_OK) return false;
  if (esp_ble_gap_register_callback(gapCallback) != ESP_OK || esp_ble_gatts_register_callback(gattCallback) != ESP_OK) return false;
  esp_ble_gatt_set_local_mtu(247);
  uint8_t authentication = ESP_LE_AUTH_REQ_SC_MITM_BOND, capability = ESP_IO_CAP_OUT, key_size = 16;
  uint8_t keys = ESP_BLE_ENC_KEY_MASK | ESP_BLE_ID_KEY_MASK, specified = ESP_BLE_ONLY_ACCEPT_SPECIFIED_AUTH_ENABLE;
  if (esp_ble_gap_set_security_param(ESP_BLE_SM_AUTHEN_REQ_MODE, &authentication, sizeof(authentication)) != ESP_OK
      || esp_ble_gap_set_security_param(ESP_BLE_SM_IOCAP_MODE, &capability, sizeof(capability)) != ESP_OK
      || esp_ble_gap_set_security_param(ESP_BLE_SM_MAX_KEY_SIZE, &key_size, sizeof(key_size)) != ESP_OK
      || esp_ble_gap_set_security_param(ESP_BLE_SM_SET_INIT_KEY, &keys, sizeof(keys)) != ESP_OK
      || esp_ble_gap_set_security_param(ESP_BLE_SM_SET_RSP_KEY, &keys, sizeof(keys)) != ESP_OK
      || esp_ble_gap_set_security_param(ESP_BLE_SM_ONLY_ACCEPT_SPECIFIED_SEC_AUTH, &specified, sizeof(specified)) != ESP_OK) return false;
  esp_ble_gap_set_device_name("SmartRoom");
  esp_ble_adv_data_t data{}; data.include_name = false; data.service_uuid_len = 16; data.p_service_uuid = service_uuid;
  data.flag = ESP_BLE_ADV_FLAG_GEN_DISC | ESP_BLE_ADV_FLAG_BREDR_NOT_SPT;
  esp_ble_adv_data_t scan{}; scan.set_scan_rsp = true; scan.include_name = true;
  if (esp_ble_gap_config_adv_data(&data) != ESP_OK || esp_ble_gap_config_adv_data(&scan) != ESP_OK) return false;
  return esp_ble_gatts_app_register(0) == ESP_OK;
}

bool send(JsonDocument &document, bool bluetooth) {
  static std::array<char, 4097> bytes{};
  const size_t size = measureJson(document);
  if (!size || size > 4095 || serializeJson(document, bytes.data(), bytes.size()) != size) { ++tx_errors; return false; }
  if (!bluetooth) {
    uint8_t header[8]{0xc3,0x3c}; room::put32(header + 2, size);
    room::put16(header + 6, room::crc16(reinterpret_cast<uint8_t *>(bytes.data()), size));
    return Serial.write(header, 8) == 8 && Serial.write(reinterpret_cast<uint8_t *>(bytes.data()), size) == size;
  }
  bytes[size] = '\n';
  const Link initial = readLink(); if (!initial.secure || !initial.subscribed || initial.generation != current_generation) return false;
  const size_t chunk = std::min<size_t>(160, initial.mtu >= 23 ? initial.mtu - 3 : 20);
  for (size_t offset = 0; offset <= size; offset += chunk) {
    const Link peer = readLink();
    if (peer.id != initial.id || peer.generation != initial.generation || !peer.secure || !peer.subscribed) return false;
    const size_t length = std::min(chunk, size + 1 - offset);
    if (esp_ble_gatts_send_indicate(gatt_if, peer.id, handles[EventValue], length,
                                  reinterpret_cast<uint8_t *>(bytes.data() + offset), false) != ESP_OK) { ++tx_errors; return false; }
    delay(4);  // Bounded notification pacing, not an appliance acknowledgment.
  }
  return true;
}
void ack(uint32_t id, bool ok, const char *code, bool bluetooth = true) {
  JsonDocument response; response["v"] = 1; response["type"] = "ack"; response["id"] = id;
  if (!bluetooth && host_session[0]) response["session"] = host_session.data();
  response["ok"] = ok; response["code"] = code; send(response, bluetooth);
}
using room::fields::exact;
using room::fields::number;
using room::fields::configuration;
using room::fields::putConfiguration;
using room::fields::metadata;
const char *modeName(room::Mode mode) { return mode == room::Mode::Auto ? "auto" : mode == room::Mode::Manual ? "manual" : "sleep"; }
const char *sceneName(room::Scene scene) {
  switch (scene) { case room::Scene::Quiet: return "quiet"; case room::Scene::Normal: return "normal";
    case room::Scene::Busy: return "busy"; case room::Scene::Sleep: return "sleep";
    case room::Scene::Manual: return "manual"; default: return "none"; }
}
void status(uint32_t id, bool bluetooth) {
  const auto snapshot = engine.tick(millis()); JsonDocument state;
  state["v"] = 1; state["type"] = "status"; state["id"] = id; state["device"] = device_id.data(); state["boot"] = boot_id.data();
  state["uptime_ms"] = millis(); state["people"] = snapshot.people;
  state["presence"] = snapshot.presence == room::Presence::Unknown ? "unknown" : snapshot.people ? "occupied" : "empty";
  state["mode"] = modeName(snapshot.mode); state["scene"] = sceneName(snapshot.scene); state["lights"] = snapshot.lights;
  state["override_ms"] = snapshot.override_remaining_ms; state["empty_remaining_ms"] = snapshot.empty_remaining_ms;
  state["requested_slot"] = snapshot.ir_slot; state["sent_slot"] = last_sent_slot;
  const char *result = learning ? "learning" : !ENABLE_IR_TRANSMIT ? "disabled" : !snapshot.ir_slot ? "no_request"
      : !slots.has(snapshot.ir_slot) ? "unlearned" : ir_fault_slot == snapshot.ir_slot ? ir_fault
      : engine.sentCurrent(snapshot.ir_slot) ? "pulses_sent_unconfirmed" : "queued";
  state["ir_result"] = result; state["relay_enabled"] = ENABLE_RELAY; state["ir_rx_enabled"] = ENABLE_IR_RECEIVE;
  state["ir_tx_enabled"] = ENABLE_IR_TRANSMIT; state["oled_ready"] = oled.ready(); state["camera_ready"] = camera_ready;
  state["storage_ready"] = slots.ready(); state["last_frame"] = last_frame; state["last_seq"] = last_sequence;
  state["learn_slot"] = learning ? learning_meta.slot : 0; state["stream_errors"] = control.errors(); state["ble_tx_errors"] = tx_errors.load();
  state["ble_ready"] = ble_ready.load();
  putConfiguration(state["config"].to<JsonObject>(), engine.config()); send(state, bluetooth);
}
void profiles(uint32_t id) {
  JsonDocument state; state["v"] = 1; state["type"] = "profiles"; state["id"] = id;
  JsonArray items = state["items"].to<JsonArray>();
  for (uint8_t slot = 1; slot <= 16; ++slot) if (slots.has(slot)) {
    const auto &meta = slots.meta(slot); JsonObject item = items.add<JsonObject>();
    item["slot"] = slot; item["label"] = meta.label.data(); item["temperature"] = meta.temperature;
    item["fan"] = meta.fan; item["mode"] = meta.mode; item["power"] = meta.power; item["sleep"] = meta.sleep;
    item["hz"] = meta.carrier_hz; item["pulses"] = meta.pulse_count;
  }
  send(state, true);
}
void stopLearning() { if (learning) receiver.disableIRIn(); learning = false; }
void queueSlot(uint32_t id, uint8_t slot, uint32_t lease) {
  if (!ENABLE_IR_TRANSMIT) { ack(id,false,"hardware_disabled"); return; }
  if (learning) { ack(id,false,"learning_busy"); return; }
  if (!slots.has(slot)) { ack(id,false,"unlearned_state"); return; }
  if (!engine.manualIr(slot,millis(),lease)) { ack(id,false,"invalid_lease"); return; }
  engine.invalidateSent(slot); ir_fault_slot = 0; ack(id,true,"queued");
}

void command(const char *text, size_t size) {
  const Link peer = readLink(); if (!peer.secure || peer.generation != current_generation) return;
  if (!room::flatCommand(text,size)) { ack(0,false,"invalid_json"); return; }
  JsonDocument document; const auto error = deserializeJson(document,text,size,DeserializationOption::NestingLimit(2));
  JsonObjectConst object = document.as<JsonObjectConst>(); uint32_t id;
  if (error || !object["v"].is<uint32_t>() || object["v"].as<uint32_t>() != 1
      || !number(object,"id",id,1,2147483647) || !object["op"].is<const char *>()) { ack(0,false,"invalid_envelope"); return; }
  if (!requests.accept(id)) { ack(id,false,"replayed_request"); return; }
  const char *op = object["op"].as<const char *>();
  if (!std::strcmp(op,"hello")) {
    if (!exact(object,{"v","id","op"})) { ack(id,false,"invalid_fields"); return; }
    uint8_t session[16], challenge[32]; esp_fill_random(session,sizeof(session)); esp_fill_random(challenge,sizeof(challenge));
    auth.begin(session,challenge,millis());
    JsonDocument response; response["v"] = 1; response["type"] = "hello"; response["id"] = id;
    response["device"] = device_id.data(); response["session"] = auth.session(); response["challenge"] = auth.challenge();
    response["owned"] = owner_exists; response["claim_open"] = !owner_exists && pairingWindow(millis()); send(response,true); return;
  }
  const char *session = object["session"].is<const char *>() ? object["session"].as<const char *>() : nullptr;
  if (!std::strcmp(op,"auth")) {
    if (!exact(object,{"v","id","op","session","proof"}) || !owner_exists || !object["proof"].is<const char *>()) { ack(id,false,"auth_required"); return; }
    char context[192]; uint8_t expected[32]{}; const size_t length = auth.context(device_id.data(),context,sizeof(context));
    const auto *provider = mbedtls_md_info_from_type(MBEDTLS_MD_SHA256);
    const bool calculated = provider && length && mbedtls_md_hmac(provider,owner_key.data(),owner_key.size(),
      reinterpret_cast<const uint8_t *>(context),length,expected) == 0;
    const bool ok = auth.prove(session,object["proof"].as<const char *>(),calculated ? expected : nullptr,millis());
    mbedtls_platform_zeroize(expected,sizeof(expected)); ack(id,ok,ok ? "authenticated" : "bad_proof");
    if (!ok) disconnect(peer.id);
    return;
  }
  if (!std::strcmp(op,"claim")) {
    uint8_t key[32]{};
    if (!exact(object,{"v","id","op","session","key"}) || owner_exists || !preferences_ready || !object["key"].is<const char *>()
        || !room::parseHex(object["key"].as<const char *>(),32,key) || !auth.claim(session,millis(),pairingWindow(millis()))) {
      mbedtls_platform_zeroize(key,sizeof(key)); ack(id,false,"claim_denied"); return;
    }
    if (preferences.putBytes("owner",key,sizeof(key)) != sizeof(key)) {
      auth.reset(); mbedtls_platform_zeroize(key,sizeof(key)); ack(id,false,"storage_failed"); return;
    }
    std::memcpy(owner_key.data(),key,sizeof(key)); mbedtls_platform_zeroize(key,sizeof(key)); owner_exists = true;
    portENTER_CRITICAL(&link_mux); security_owner_exists = true; portEXIT_CRITICAL(&link_mux);
    ack(id,true,"claimed"); return;
  }
  if (!auth.authorized(session)) { ack(id,false,"auth_required"); return; }
  if (!std::strcmp(op,"status") && exact(object,{"v","id","op","session"})) { status(id,true); return; }
  if (!std::strcmp(op,"profiles") && exact(object,{"v","id","op","session"})) { profiles(id); return; }
  uint32_t lease = 0;
  if (!std::strcmp(op,"set_mode")) {
    if (!exact(object,{"v","id","op","session","mode","lease_ms"}) || !object["mode"].is<const char *>()
        || !number(object,"lease_ms",lease,0,43200000)) { ack(id,false,"invalid_fields"); return; }
    const char *mode = object["mode"].as<const char *>(); room::Mode requested;
    if (!std::strcmp(mode,"auto")) requested = room::Mode::Auto;
    else if (!std::strcmp(mode,"manual")) requested = room::Mode::Manual;
    else if (!std::strcmp(mode,"sleep")) requested = room::Mode::Sleep;
    else { ack(id,false,"invalid_mode"); return; }
    const bool ok = engine.setMode(requested,millis(),lease); ack(id,ok,ok ? "policy_saved" : "invalid_lease"); return;
  }
  if (!std::strcmp(op,"lights")) {
    if (!exact(object,{"v","id","op","session","on","lease_ms"}) || !object["on"].is<bool>()
        || !number(object,"lease_ms",lease,0,43200000)) { ack(id,false,"invalid_fields"); return; }
    if (!ENABLE_RELAY) { ack(id,false,"hardware_disabled"); return; }
    const bool ok = engine.manualLights(object["on"].as<bool>(),millis(),lease); ack(id,ok,ok ? "requested_no_feedback" : "invalid_lease"); return;
  }
  if (!std::strcmp(op,"send_slot")) {
    uint32_t slot;
    if (!exact(object,{"v","id","op","session","slot","lease_ms"}) || !number(object,"slot",slot,1,16)
        || !number(object,"lease_ms",lease,0,43200000)) { ack(id,false,"invalid_fields"); return; }
    queueSlot(id,slot,lease); return;
  }
  if (!std::strcmp(op,"ac")) {
    room::SlotMeta requested;
    if (!exact(object,{"v","id","op","session","temperature","fan","mode","power","sleep","lease_ms"})
        || !metadata(object,requested,false) || !number(object,"lease_ms",lease,0,43200000)) { ack(id,false,"invalid_fields"); return; }
    for (uint8_t slot = 1; slot <= 16; ++slot) if (slots.has(slot)) {
      const auto &saved = slots.meta(slot);
      if (saved.temperature == requested.temperature && saved.fan == requested.fan && saved.mode == requested.mode
          && saved.power == requested.power && saved.sleep == requested.sleep) { queueSlot(id,slot,lease); return; }
    }
    ack(id,false,"unlearned_state"); return;
  }
  if (!std::strcmp(op,"configure")) {
    room::Config candidate;
    if (!exact(object,{"v","id","op","session","ttl_ms","empty_ms","settle_ms","manual_ms","ir_gap_ms","quiet_max","normal_max","quiet_slot","normal_slot","busy_slot","sleep_slot"})
        || !configuration(object,candidate)) { ack(id,false,"invalid_configuration"); return; }
    JsonDocument record; putConfiguration(record.to<JsonObject>(),candidate); String saved; serializeJson(record,saved);
    if (!preferences_ready || preferences.putString("config",saved) != saved.length()) { ack(id,false,"storage_failed"); return; }
    engine.configure(candidate); ack(id,true,"configuration_saved"); return;
  }
  if (!std::strcmp(op,"learn_start")) {
    room::SlotMeta meta;
    if (!exact(object,{"v","id","op","session","slot","label","temperature","fan","mode","power","sleep","hz"}) || !metadata(object,meta,true)) { ack(id,false,"invalid_fields"); return; }
    if (!ENABLE_IR_RECEIVE) { ack(id,false,"hardware_disabled"); return; }
    if (!slots.ready()) { ack(id,false,"storage_unmounted"); return; }
    if (learning) { ack(id,false,"learning_busy"); return; }
    learning_meta = meta; learning_at = millis(); learning = true; receiver.enableIRIn(); receiver.resume(); ack(id,true,"press_original_remote"); return;
  }
  if (!std::strcmp(op,"learn_cancel") && exact(object,{"v","id","op","session"})) { stopLearning(); ack(id,true,"learning_cancelled"); return; }
  if (!std::strcmp(op,"erase_slot")) {
    uint32_t slot;
    if (!exact(object,{"v","id","op","session","slot","confirm"}) || !number(object,"slot",slot,1,16)
        || !object["confirm"].is<bool>() || !object["confirm"].as<bool>()) { ack(id,false,"confirmation_required"); return; }
    stopLearning(); const bool ok = slots.eraseConfirmed(slot); if (ok) engine.invalidateSent(slot);
    ack(id,ok,ok ? "slot_erased" : "storage_failed"); return;
  }
  if (!std::strcmp(op,"storage_init")) {
    if (!exact(object,{"v","id","op","session","confirm"}) || !object["confirm"].is<const char *>()
        || std::strcmp(object["confirm"].as<const char *>(),"INIT_UNMOUNTED_STORAGE")) { ack(id,false,"confirmation_required"); return; }
    const bool ok = slots.initializeConfirmed(); ack(id,ok,ok ? "storage_ready" : "storage_failed"); return;
  }
  ack(id,false,"unknown_operation_or_fields");
}

void usbCommand(const char *text, size_t size) {
  if (!room::flatCommand(text,size)) { ack(0,false,"invalid_json",false); return; }
  JsonDocument document; const auto error = deserializeJson(document,text,size,DeserializationOption::NestingLimit(2));
  JsonObjectConst object = document.as<JsonObjectConst>();
  if (error || !object["v"].is<uint32_t>() || object["v"].as<uint32_t>() != 1 || !object["op"].is<const char *>()) return;
  const char *op = object["op"].as<const char *>();
  if (!std::strcmp(op,"hello")) {
    uint8_t session[16];
    if (!exact(object,{"v","op","session"}) || !object["session"].is<const char *>()
        || !room::parseHex(object["session"].as<const char *>(),16,session)) { ack(0,false,"invalid_session",false); return; }
    std::strcpy(host_session.data(),object["session"].as<const char *>()); engine.resetSensor(); usb_requests.reset(); last_frame = last_sequence = 0;
    JsonDocument reply; reply["v"] = 1; reply["type"] = "hello"; reply["device"] = device_id.data(); reply["boot"] = boot_id.data();
    reply["session"] = host_session.data(); reply["ttl_ms"] = engine.config().ttl_ms; send(reply,false); return;
  }
  if (!std::strcmp(op,"status") && exact(object,{"v","op"})) { status(0,false); return; }
  if (!std::strcmp(op,"observe")) {
    uint32_t sequence, frame, age;
    if (!exact(object,{"v","op","session","seq","frame","age_ms","people"}) || !object["session"].is<const char *>()
        || !host_session[0] || std::strcmp(host_session.data(),object["session"].as<const char *>())
        || !number(object,"seq",sequence,1,2147483647) || !number(object,"frame",frame,0,2147483647)
        || !number(object,"age_ms",age,0,engine.config().ttl_ms) || !object["people"].is<int>()) { ack(0,false,"invalid_observation",false); return; }
    if (!engine.observe(sequence,object["people"].as<int>(),age,millis())) { ack(0,false,"rejected_observation",false); return; }
    last_sequence = sequence; last_frame = frame; return;
  }
  if (!std::strcmp(op,"open_pairing")) {
    uint32_t id = 0;
    if (!room::fields::localAction(object,host_session.data(),"LOCAL_PAIRING_WINDOW",id)) { ack(id,false,"invalid_local_action",false); return; }
    if (!usb_requests.accept(id)) { ack(id,false,"replayed_request",false); return; }
    if (!oled.ready()) { ack(id,false,"oled_required",false); return; }
    pairing_at = millis(); ack(id,true,"pairing_window_open",false); return;
  }
  if (!std::strcmp(op,"reset_owner")) {
    uint32_t id = 0;
    if (!room::fields::localAction(object,host_session.data(),"ERASE_OWNER_AND_BONDS",id)) { ack(id,false,"invalid_local_action",false); return; }
    if (!usb_requests.accept(id)) { ack(id,false,"replayed_request",false); return; }
    if (!preferences_ready) { ack(id,false,"storage_failed",false); return; }
    if (owner_exists && !preferences.remove("owner")) { ack(id,false,"storage_failed",false); return; }
    owner_exists = false; auth.reset(); mbedtls_platform_zeroize(owner_key.data(),owner_key.size());
    portENTER_CRITICAL(&link_mux); security_owner_exists = false; portEXIT_CRITICAL(&link_mux);
    const Link peer = readLink(); disconnect(peer.id); stopLearning();
    int count = esp_ble_get_bond_device_num(); bool clean = count >= 0 && count <= 32;
    if (clean && count) {
      std::array<esp_ble_bond_dev_t,32> bonds{};
      clean = esp_ble_get_bond_device_list(&count,bonds.data()) == ESP_OK;
      if (clean) for (int i = 0; i < count; ++i) if (esp_ble_remove_bond_device(bonds[i].bd_addr) != ESP_OK) clean = false;
    }
    pairing_at = millis(); ack(id,clean,clean ? "owner_reset_bond_removal_requested" : "bond_removal_failed",false); return;
  }
  ack(0,false,"unknown_operation_or_fields",false);
}

bool setupCamera() {
  if (!ENABLE_CAMERA || !psramFound()) return false;
  camera_config_t config{};
  config.ledc_channel = LEDC_CHANNEL_0; config.ledc_timer = LEDC_TIMER_0;
  config.pin_d0 = 5; config.pin_d1 = 18; config.pin_d2 = 19; config.pin_d3 = 21;
  config.pin_d4 = 36; config.pin_d5 = 39; config.pin_d6 = 34; config.pin_d7 = 35;
  config.pin_xclk = 0; config.pin_pclk = 22; config.pin_vsync = 25; config.pin_href = 23;
  config.pin_sccb_sda = 26; config.pin_sccb_scl = 27; config.pin_pwdn = 32; config.pin_reset = -1;
  config.xclk_freq_hz = 20000000; config.pixel_format = PIXFORMAT_JPEG; config.frame_size = FRAMESIZE_VGA;
  config.jpeg_quality = 12; config.fb_count = 2; config.grab_mode = CAMERA_GRAB_LATEST; config.fb_location = CAMERA_FB_IN_PSRAM;
  return esp_camera_init(&config) == ESP_OK;
}
void cameraFrame(uint32_t now) {
  if (!camera_ready || static_cast<uint32_t>(now - last_camera_at) < 125) return;
  last_camera_at = now; camera_fb_t *frame = esp_camera_fb_get();
  if (!frame || frame->format != PIXFORMAT_JPEG || !frame->len || frame->len > 256000) {
    if (frame) esp_camera_fb_return(frame); return;
  }
  uint8_t header[8]{0xa5,0x5a}; room::put32(header + 2, frame->len); room::put16(header + 6, room::crc16(frame->buf,frame->len));
  Serial.write(header,8); Serial.write(frame->buf,frame->len); esp_camera_fb_return(frame);
}
void learnFrame(uint32_t now) {
  if (!learning) return;
  if (static_cast<uint32_t>(now - learning_at) > 30000) {
    stopLearning(); JsonDocument event; event["v"] = 1; event["type"] = "learned"; event["ok"] = false; event["code"] = "learning_timeout"; send(event,true); return;
  }
  if (!receiver.decode(&received)) return;
  room::RecordedSlot record; record.meta = learning_meta; const uint16_t length = getCorrectedRawLength(&received);
  bool valid = !received.overflow && length >= 16 && length <= room::MAX_IR_PULSES;
  uint16_t position = 0;
  if (valid) for (uint16_t i = 1; i < received.rawlen && valid; ++i) {
    uint32_t duration = received.rawbuf[i] * kRawTick;
    while (duration > UINT16_MAX && valid) {
      if (position + 2 > room::MAX_IR_PULSES) { valid = false; break; }
      record.pulses[position++] = UINT16_MAX; record.pulses[position++] = 0; duration -= UINT16_MAX;
    }
    if (valid) { if (position == room::MAX_IR_PULSES) valid = false; else record.pulses[position++] = duration; }
  }
  record.meta.pulse_count = position; valid = valid && position == length && room::validSlot(record);
  const bool stored = valid && slots.save(record); stopLearning();
  if (stored) { engine.invalidateSent(record.meta.slot); ir_fault_slot = 0; }
  JsonDocument event; event["v"] = 1; event["type"] = "learned"; event["slot"] = record.meta.slot;
  event["ok"] = stored; event["code"] = !valid ? "incomplete_or_noise" : stored ? "saved_raw_unverified" : "storage_failed";
  event["pulses"] = position; send(event,true);
}
void applyOutputs(uint32_t now) {
  const auto state = engine.tick(now);
  if (ENABLE_RELAY) digitalWrite(RELAY_PIN,(state.lights != RELAY_ACTIVE_LOW) ? HIGH : LOW);
  if (!ENABLE_IR_TRANSMIT || learning) return;
  const uint8_t pending = engine.pendingIr(now,slots.mask()); if (!pending || pending == ir_fault_slot) return;
  room::RecordedSlot record;
  if (!slots.load(pending,record)) { ir_fault_slot = pending; ir_fault = "record_corrupt"; return; }
  sender.sendRaw(record.pulses.data(),record.meta.pulse_count,record.meta.carrier_hz);
  engine.noteIrSent(pending,millis()); last_sent_slot = pending; ir_fault_slot = 0;
  JsonDocument event; event["v"] = 1; event["type"] = "ir_sent"; event["slot"] = pending; event["confirmed_by_ac"] = false;
  if (auth.authorized(auth.session())) send(event,true);
}
void display(uint32_t now) {
  if (!oled.ready()) return;
  const auto state = engine.tick(now); oled.clear(); char text[32]; const Link peer = readLink();
  if (peer.id != NO_CONNECTION && !auth.authorized(auth.session())) {
    oled.text(0,0,"BLUETOOTH PAIRING"); oled.text(2,0,"ENTER ON PHONE");
    portENTER_CRITICAL(&link_mux); const uint32_t code = passkey; portEXIT_CRITICAL(&link_mux);
    snprintf(text,sizeof(text),"%06lu",static_cast<unsigned long>(code)); oled.text(4,0,text,2);
  } else {
    oled.text(0,0,"SMART ROOM");
    if (state.people < 0) snprintf(text,sizeof(text),"PEOPLE: UNKNOWN"); else snprintf(text,sizeof(text),"PEOPLE: %d",state.people);
    oled.text(1,0,text); oled.text(2,0,modeName(state.mode));
    snprintf(text,sizeof(text),"LIGHT REQUEST: %s",state.lights ? "ON" : "OFF"); oled.text(3,0,text);
    if (last_sent_slot && slots.has(last_sent_slot)) {
      const auto &meta = slots.meta(last_sent_slot); snprintf(text,sizeof(text),"IR: %u C FAN %u",meta.temperature,meta.fan); oled.text(4,0,text);
    } else oled.text(4,0,"IR: NOT SENT");
    oled.text(5,0,"NO AC FEEDBACK"); oled.text(6,0,learning ? "IR LEARNING" : peer.id == NO_CONNECTION ? "BLE: AVAILABLE" : "BLE: ONE OWNER");
    oled.text(7,0,ENABLE_RELAY && ENABLE_IR_TRANSMIT ? "BENCH CONFIG" : "OUTPUTS DISABLED");
  }
  oled.flush();
}
void setup() {
  Serial.setRxBufferSize(2048); Serial.setTxBufferSize(16384); Serial.begin(UART_BAUD); delay(300);
  Serial.println("SMART-ROOM prototype v1 - outputs require hardware review");
  uint8_t mac[6]; esp_read_mac(mac,ESP_MAC_WIFI_STA);
  for (unsigned i = 0; i < 6; ++i) snprintf(device_id.data() + i * 2,3,"%02x",mac[i]);
  randomHex(boot_id.data(),8); preferences_ready = preferences.begin("smart_room",false);
  if (preferences_ready && preferences.getBytesLength("owner") == owner_key.size()) owner_exists = preferences.getBytes("owner",owner_key.data(),owner_key.size()) == owner_key.size();
  if (preferences_ready) {
    const String saved = preferences.getString("config",""); JsonDocument record;
    if (saved.length() && room::flatCommand(saved.c_str(),saved.length()) && !deserializeJson(record,saved)) {
      room::Config candidate; if (configuration(record.as<JsonObjectConst>(),candidate)) engine.configure(candidate);
    }
  }
  slots.begin(); oled.begin(); pairing_at = millis();
  portENTER_CRITICAL(&link_mux); security_owner_exists = owner_exists; security_display_ready = oled.ready(); portEXIT_CRITICAL(&link_mux);
  if (ENABLE_RELAY) { digitalWrite(RELAY_PIN,RELAY_ACTIVE_LOW ? HIGH : LOW); pinMode(RELAY_PIN,OUTPUT); }
  if (ENABLE_IR_TRANSMIT) sender.begin();
  camera_ready = setupCamera(); const bool ble_started = setupBle();
  if (!ble_started) Serial.println("BLE_SETUP_FAILED - no Bluetooth control available");
}
void loop() {
  uint32_t now = millis(); const Link peer = readLink();
  if (peer.id == NO_CONNECTION && current_generation) {
    current_generation = 0; auth.reset(); requests.reset(); lines.reset(); stopLearning(); advertiseIfFree();
  }
  Input input{};
  for (unsigned n = 0; incoming && n < 16 && xQueueReceive(incoming,&input,0) == pdTRUE; ++n) {
    const Link live = readLink();
    if (input.kind == LinkEvent::Disconnected) continue;
    if (input.connection != live.id || input.generation != live.generation) continue;
    if (input.kind == LinkEvent::Connected) {
      current_generation = input.generation; auth.reset(); requests.reset(); lines.reset(); stopLearning(); connection_at = now;
      uint32_t code = 100000 + esp_random() % 900000;
      portENTER_CRITICAL(&link_mux); passkey = code; portEXIT_CRITICAL(&link_mux);
      esp_ble_gap_set_security_param(ESP_BLE_SM_SET_STATIC_PASSKEY,&code,sizeof(code));
      esp_bd_addr_t address; std::memcpy(address,live.address,sizeof(address));
      if (esp_ble_set_encryption(address,ESP_BLE_SEC_ENCRYPT_MITM) != ESP_OK) disconnect(live.id);
    } else if (input.kind == LinkEvent::Write && live.secure && current_generation == input.generation) {
      for (uint16_t i = 0; i < input.length; ++i) if (lines.feed(input.bytes[i],millis())) command(lines.data(),lines.size());
    }
  }
  const Link active = readLink();
  if (active.id != NO_CONNECTION && current_generation && !auth.authorized(auth.session())
      && static_cast<uint32_t>(now - connection_at) > 90000) disconnect(active.id);
  for (unsigned bytes = 0; bytes < 1024 && Serial.available(); ++bytes) {
    const int byte = Serial.read(); if (byte >= 0 && control.feed(byte,millis())) usbCommand(control.data(),control.size());
  }
  now = millis(); learnFrame(now); applyOutputs(now);
  if (static_cast<uint32_t>(now - last_status_at) >= 1000) {
    last_status_at = now; status(0,false); if (auth.authorized(auth.session())) status(0,true); display(now);
    portENTER_CRITICAL(&link_mux); security_display_ready = oled.ready(); portEXIT_CRITICAL(&link_mux);
  }
  cameraFrame(millis()); delay(1);
}

}  // namespace smart

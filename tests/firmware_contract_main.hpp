// Included only AFTER the unmodified dispatcher slice by run_contract_tests.py.
int main() {
  try {
    std::array<char,32769> input{};
    std::cin.getline(input.data(),input.size());
    if (!std::cin || std::strlen(input.data()) > 32768) throw std::runtime_error("Fixture input bound");
    JsonDocument request;
    if (deserializeJson(request,input.data(),DeserializationOption::NestingLimit(4))) throw std::runtime_error("Fixture JSON");
    JsonObjectConst object = request.as<JsonObjectConst>(); uint32_t final_time;
    if (!room::fields::exact(object,{"fixture","messages","final_now"}) || !object["messages"].is<JsonArrayConst>()
        || !room::fields::number(object,"final_now",final_time,0,UINT32_MAX)) throw std::runtime_error("Fixture request schema");
    smart::initialize(object["fixture"].as<JsonObjectConst>());
    JsonArrayConst messages = object["messages"].as<JsonArrayConst>();
    if (messages.size() > 32) throw std::runtime_error("Fixture message count");
    for (JsonObjectConst message : messages) {
      if (!room::fields::exact(message,{"bluetooth","wire","now"}) || !message["bluetooth"].is<bool>()
          || !message["wire"].is<const char *>() || !room::fields::number(message,"now",smart::now,0,UINT32_MAX))
        throw std::runtime_error("Fixture message schema");
      const std::string hex = message["wire"].as<const char *>();
      if (hex.empty() || hex.size() > 4096 || hex.size() % 2) throw std::runtime_error("Fixture packet size");
      std::vector<uint8_t> bytes(hex.size() / 2);
      if (!room::parseHex(hex.c_str(),bytes.size(),bytes.data())) throw std::runtime_error("Fixture hex");
      const bool bluetooth = message["bluetooth"].as<bool>();
      for (const auto byte : bytes) {
        if (bluetooth) {
          if (smart::lines.feed(byte,smart::now)) smart::command(smart::lines.data(),smart::lines.size());
        } else if (smart::control.feed(byte,smart::now)) smart::usbCommand(smart::control.data(),smart::control.size());
      }
    }
    smart::now = final_time;
    // Actual status serialization, separated from solicited events for inspection.
    smart::status(0,false); const auto final_status = smart::captures.back().json; smart::captures.pop_back();
    JsonDocument result, event;
    auto events = result["events"].to<JsonArray>();
    for (const auto &capture : smart::captures) {
      if (deserializeJson(event,capture.json,DeserializationOption::NestingLimit(6))) throw std::runtime_error("Fixture output JSON");
      auto item = events.add<JsonObject>(); item["bluetooth"] = capture.bluetooth; item["data"] = event.as<JsonObjectConst>();
    }
    if (deserializeJson(event,final_status,DeserializationOption::NestingLimit(6))) throw std::runtime_error("Fixture status JSON");
    result["status"] = event.as<JsonObjectConst>();
    result["authorized"] = smart::fixture_link.secure && smart::auth.authorized(smart::auth.session());
    result["owner_exists"] = smart::owner_exists; result["storage_writes"] = smart::storage_writes;
    result["disconnect_requests"] = smart::disconnect_requests; result["receiver_starts"] = smart::receiver_starts;
    result["provider_calls"] = smart::provider_calls; result["provider_context_verified"] = smart::provider_context_verified;
    result["io_simulated"] = true;
    serializeJson(result,std::cout); std::cout << '\n'; return 0;
  } catch (const std::exception &error) {
    std::cerr << "Contract fixture failed: " << error.what() << '\n'; return 1;
  }
}

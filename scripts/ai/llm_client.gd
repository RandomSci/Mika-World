class_name LLMClient
extends Node
## One shared, budgeted client for optional language-model calls (NPC phrasing, contextual curiosity).
## Safe by default:
##  * provider "mock" unless BOTH MIKA_DEV_LLM_PROVIDER=openai and an API key are configured in the DEV
##    environment (process env or <project>/.env.dev, which is git-ignored). Production keys are never read.
##  * hard budgets: calls per hour, max output tokens, timeout; over budget -> mock fallback.
##  * the model id is configurable (default gpt-5-mini) and NOT assumed to exist: an API "model not
##    found" answer disables the client and is reported.
##  * the key is never logged, printed, written to reports or sent anywhere but the provider endpoint.
## Callers must treat every answer as a proposal and validate it against engine state.

static var instance: LLMClient

var provider := "mock"
var model := "gpt-5-mini"
var max_calls_per_hour := 30
var max_output_tokens := 300
var timeout_s := 12.0
var status := "mock (no DEV LLM configured)"
var calls: Array = []          # timestamps of real calls (budget window)
var stats := {"real_calls": 0, "mock_calls": 0, "failures": 0, "over_budget": 0}
var _key := ""


func setup() -> void:
	instance = self
	var env := _read_env_file(ProjectSettings.globalize_path("res://.env.dev"))
	for k in ["MIKA_DEV_LLM_PROVIDER", "MIKA_DEV_OPENAI_API_KEY", "MIKA_DEV_LLM_MODEL", "MIKA_DEV_LLM_MAX_CALLS_PER_HOUR", "MIKA_DEV_LLM_TIMEOUT"]:
		if OS.get_environment(k) != "":
			env[k] = OS.get_environment(k)
	model = String(env.get("MIKA_DEV_LLM_MODEL", model))
	max_calls_per_hour = int(env.get("MIKA_DEV_LLM_MAX_CALLS_PER_HOUR", max_calls_per_hour))
	timeout_s = float(env.get("MIKA_DEV_LLM_TIMEOUT", timeout_s))
	_key = String(env.get("MIKA_DEV_OPENAI_API_KEY", ""))
	if String(env.get("MIKA_DEV_LLM_PROVIDER", "mock")) == "openai" and _key != "" and not RenderProfile.options.has("llm-mock"):
		provider = "openai"
		status = "openai configured (model %s, budget %d calls/h)" % [model, max_calls_per_hour]
	print("[llm] ", status)


static func _read_env_file(path: String) -> Dictionary:
	var out := {}
	if not FileAccess.file_exists(path):
		return out
	var f := FileAccess.open(path, FileAccess.READ)
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line.begins_with("#") or not line.contains("="):
			continue
		out[line.get_slice("=", 0).strip_edges()] = line.substr(line.find("=") + 1).strip_edges().trim_prefix("\"").trim_suffix("\"")
	return out


func describe() -> Dictionary:
	return {"provider": provider, "model": model, "status": status, "budget_per_hour": max_calls_per_hour,
		"calls_last_hour": _calls_last_hour(), "stats": stats}


func _calls_last_hour() -> int:
	var now := Time.get_unix_time_from_system()
	calls = calls.filter(func(t): return now - float(t) < 3600.0)
	return calls.size()


## Ask for a JSON object. Returns {"ok", "json" (Dictionary), "provider", "error"}. Never throws.
## `mock` is the deterministic answer used whenever no real call is made.
func ask_json(system: String, user: String, mock: Dictionary) -> Dictionary:
	if provider != "openai":
		stats.mock_calls += 1
		return {"ok": true, "json": mock, "provider": "mock"}
	if _calls_last_hour() >= max_calls_per_hour:
		stats.over_budget += 1
		return {"ok": true, "json": mock, "provider": "mock (over budget)"}
	calls.append(Time.get_unix_time_from_system())
	var http := HTTPRequest.new()
	http.timeout = timeout_s
	add_child(http)
	var body := {"model": model, "messages": [{"role": "system", "content": system}, {"role": "user", "content": user}],
		"response_format": {"type": "json_object"}, "max_completion_tokens": max_output_tokens}
	var err := http.request("https://api.openai.com/v1/chat/completions", ["Content-Type: application/json", "Authorization: Bearer " + _key],
		HTTPClient.METHOD_POST, JSON.stringify(body))
	if err != OK:
		http.queue_free()
		stats.failures += 1
		return {"ok": true, "json": mock, "provider": "mock (request error)"}
	var r: Array = await http.request_completed
	http.queue_free()
	if r[0] != HTTPRequest.RESULT_SUCCESS or r[1] != 200:
		stats.failures += 1
		var txt := (r[3] as PackedByteArray).get_string_from_utf8().left(300)
		if r[1] == 404 or txt.contains("model_not_found") or txt.contains("does not exist"):
			provider = "mock"
			status = "disabled: model '%s' not available to this key" % model
		return {"ok": true, "json": mock, "provider": "mock (http %d)" % r[1]}
	stats.real_calls += 1
	var parsed = JSON.parse_string((r[3] as PackedByteArray).get_string_from_utf8())
	var content := ""
	if parsed is Dictionary and parsed.get("choices", []).size() > 0:
		content = String(parsed.choices[0].message.get("content", ""))
	var j = JSON.parse_string(content)
	if not j is Dictionary:
		stats.failures += 1
		return {"ok": true, "json": mock, "provider": "mock (unparseable answer)"}
	return {"ok": true, "json": j, "provider": "openai"}

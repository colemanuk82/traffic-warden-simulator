extends Node
## Autoload "Updater": checks GitHub once per start for a newer release of the game.
## Quiet by design: no internet, a slow reply or anything odd just means no update note.
## Turned off with the "Check for updates" setting.

signal update_found(version: String, url: String)

const API_URL := "https://api.github.com/repos/colemanuk82/traffic-warden-simulator/releases/latest"
const RELEASES_URL := "https://github.com/colemanuk82/traffic-warden-simulator/releases/latest"

var latest_version := ""  # set once a newer version is found
var download_url := ""
var tls_options: TLSOptions = null  # dev tests behind a TLS-inspecting proxy pass their own CA here
var _http: HTTPRequest
var _checked := false


func _ready() -> void:
	# Give the game a moment to start before touching the network
	get_tree().create_timer(2.0).timeout.connect(check)


func current_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", "0.0.0"))


func has_update() -> bool:
	return latest_version != ""


func check() -> void:
	if _checked or not Game.settings.get("update_check", true) or Engine.is_editor_hint():
		return
	_checked = true
	_http = HTTPRequest.new()
	_http.timeout = 10.0
	add_child(_http)
	_http.request_completed.connect(_on_reply)
	_use_proxy_from_env()
	if tls_options:
		_http.set_tls_options(tls_options)
	var headers := ["Accept: application/vnd.github+json", "User-Agent: TrafficWardenSim/" + current_version()]
	if _http.request(API_URL, headers) != OK:
		_http.queue_free()


## Honours an HTTPS_PROXY setting (some offices and schools need one).
func _use_proxy_from_env() -> void:
	var proxy := OS.get_environment("HTTPS_PROXY")
	if proxy == "":
		proxy = OS.get_environment("https_proxy")
	if proxy == "":
		return
	var hostport := proxy.trim_prefix("http://").trim_prefix("https://").split("@")[-1].trim_suffix("/")
	var parts := hostport.rsplit(":", true, 1)
	if parts.size() == 2 and parts[1].is_valid_int():
		_http.set_https_proxy(parts[0], int(parts[1]))


func _on_reply(result: int, code: int, _headers: PackedStringArray, body: PackedByteArray) -> void:
	_http.queue_free()
	if result != HTTPRequest.RESULT_SUCCESS or code != 200:
		return
	var data = JSON.parse_string(body.get_string_from_utf8())
	if not data is Dictionary or not data.has("tag_name"):
		return
	var tag := str(data.tag_name).trim_prefix("v")
	if not is_newer(tag, current_version()):
		return
	latest_version = tag
	download_url = _pick_download(data)
	update_found.emit(latest_version, download_url)


## The right file for this device: the APK on Android, the installer on Windows, else the release page.
func _pick_download(data: Dictionary) -> String:
	var want := ".apk" if OS.get_name() == "Android" else ("-setup.exe" if OS.get_name() == "Windows" else "")
	if want != "":
		for a in data.get("assets", []):
			if a is Dictionary and str(a.get("name", "")).ends_with(want):
				return str(a.get("browser_download_url", ""))
	return str(data.get("html_url", RELEASES_URL))


## "1.10.0" is newer than "1.9.2"; anything that isn't numbers counts as zero.
static func is_newer(a: String, b: String) -> bool:
	var pa := a.split(".")
	var pb := b.split(".")
	for i in maxi(pa.size(), pb.size()):
		var x := int(pa[i]) if i < pa.size() and pa[i].is_valid_int() else 0
		var y := int(pb[i]) if i < pb.size() and pb[i].is_valid_int() else 0
		if x != y:
			return x > y
	return false


func open_download() -> void:
	OS.shell_open(download_url if download_url != "" else RELEASES_URL)

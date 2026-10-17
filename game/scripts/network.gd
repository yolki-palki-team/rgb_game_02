extends Node
var game
var http: HTTPRequest
var token=""
var status="Connecting wallets…"
var message=""
var message_operation_id=""
var trial: Dictionary={}
var busy=false
var pending: Callable
var request_path=""
var base="http://127.0.0.1:8787"
var claim_key=""
var action_key=""
var action_name=""
var profiles: Dictionary={}
var profile_slot="A"
var profile_path="user://managed_profiles.json"
var profile: Dictionary={}
var items: Array=[]
var players: Array=[]
var history: Array=[]
var service: Dictionary={"available":false}
var equipment: Dictionary={}
var lease_deadline=0
var poll_timer=0.0
var poll_started=0
var transfer_intent: Dictionary={}
var cloud_items=0
var selected_serial=0
var trial_pulse=0.0
var test_mode=false
var online=false

func _ready():
 http=HTTPRequest.new();http.timeout=6;add_child(http)
 http.request_completed.connect(_completed)
 var configured=OS.get_environment("RUNEFORGE_API_URL")
 if configured!="":base=configured
 if OS.has_feature("web"):base=str(JavaScriptBridge.get_interface("window").location.origin)
 test_mode="--web-qa" in OS.get_cmdline_user_args() or "--test-profiles" in OS.get_cmdline_user_args() or "--outage-game-check" in OS.get_cmdline_user_args() or "--network-smoke" in OS.get_cmdline_user_args() or "--managed-game-check" in OS.get_cmdline_user_args() or "--smoke" in OS.get_cmdline_user_args()
 if test_mode:profile_path="user://managed_test_profiles.json"
 if FileAccess.file_exists(profile_path):
  var stored=JSON.parse_string(FileAccess.get_file_as_string(profile_path))
  if stored is Dictionary:profiles=stored.get("profiles",{});profile_slot=stored.get("active","A")
 for arg in OS.get_cmdline_user_args():
  if arg.begins_with("--profile="):profile_slot=arg.trim_prefix("--profile=")
 for slot in ["A","B"]:
  if not profiles.has(slot):profiles[slot]={"key":Crypto.new().generate_random_bytes(32).hex_encode(),"name":(("Test WASM " if test_mode else "WASM ") if OS.has_feature("web") else ("Test " if test_mode else "Player "))+slot}
 save_profiles()

func save_profiles():
 var file=FileAccess.open(profile_path+".tmp",FileAccess.WRITE)
 if file:
  file.store_string(JSON.stringify({"profiles":profiles,"active":profile_slot}));file.close()
  DirAccess.rename_absolute(profile_path+".tmp",profile_path)
  if OS.has_feature("web"):JavaScriptBridge.force_fs_sync()

func _process(delta):
 trial_pulse=maxf(0,trial_pulse-delta)
 if Time.get_ticks_msec()>=lease_deadline:equipment={}
 if not game.menu_started:return
 poll_timer+=delta
 if poll_timer>=1.0 and not busy:
  poll_timer=0
  if token!="":refresh_status()
  elif poll_timer==0:connect_profile()

func clear_use():
 equipment={};lease_deadline=0

func request(path,method,body,callback):
 if busy:return
 busy=true;pending=callback;request_path=path
 var headers=PackedStringArray(["Content-Type: application/json"])
 if token!="":headers.append("Authorization: Bearer "+token)
 var err=http.request(base+path,headers,method,JSON.stringify(body) if method!=HTTPClient.METHOD_GET else "")
 if err!=OK:
  busy=false;connection_error()

func connection_error():
 online=false;clear_use();service={"available":false}
 status="Server offline. Campaign available; RGB items disabled."
 message="Check the local RuneForge service. Transfers are never simulated and resume after reconnection."

func _completed(result,code,_headers,body):
 busy=false
 if result!=HTTPRequest.RESULT_SUCCESS or body.is_empty():connection_error();return
 var parsed=JSON.parse_string(body.get_string_from_utf8())
 if not parsed is Dictionary:connection_error();return
 if code>=400:
  message=str(parsed.get("detail","Request rejected"))
  if code==401:token="";online=false;clear_use()
  if code==503:service={"available":false};clear_use();status=message
  # A definite rejection is safe to correct; ambiguous network outcomes retain the exact key/payload.
  if code in [409,422]:action_key="";action_name=""
  if request_path.ends_with("/transfer") and code in [400,403,404,409,410,422,503]:transfer_intent={}
  return
 online=true
 if pending.is_valid():pending.call(parsed)

func connect_profile():
 if busy:return
 # Persist registration keys before requests. Retries recover the same two profiles.
 for slot in ["A","B"]:
  if not profiles[slot].has("token"):
   request("/api/players",HTTPClient.METHOD_POST,{"name":profiles[slot].name,"registration_key":profiles[slot].key,"is_test":test_mode},func(data):
    profiles[slot].token=data.token;profiles[slot].id=data.id;save_profiles();connect_profile())
   return
 token=profiles[profile_slot].token
 refresh_status()

func switch_profile(slot):
 if busy:return
 clear_use();message="";message_operation_id="";game.save_game();profile_slot=slot;token="";trial={};items=[];history=[];players=[];action_key="";transfer_intent={};selected_serial=0
 save_profiles();connect_profile()

func refresh_status():
 if token=="":connect_profile();return
 poll_started=Time.get_ticks_msec()
 request("/api/relics",HTTPClient.METHOD_GET,{},func(data):
  profile=data.profile;service=data.service;status=service.message;items=data.items;players=data.players;history=data.history;cloud_items=items.size()
  sync_operation_message()
  var current=data.get("trial")
  if current is Dictionary:trial=current;claim_key="reward-"+str(trial.id)
  if selected_serial==0 and not items.is_empty():selected_serial=int(items[0].serial)
  var equipped=data.get("equipment")
  clear_use()
  if equipped is Dictionary and service.available:
   # Conservative monotonic lease: subtract complete request RTT from server validity.
   var remaining=maxf(0,float(equipped.lease_until)-float(data.server_time))
   lease_deadline=poll_started+int(remaining*1000)
   if lease_deadline>Time.get_ticks_msec():equipment=equipped)

func sync_operation_message():
 if message_operation_id=="":return
 for operation in history:
  if operation.id!=message_operation_id:continue
  if operation.state=="settled":
   message="Transfer complete. Sword #"+str(int(operation.serial))+" received by player «"+operation.recipient_name+"»."
  elif operation.state=="failed":
   message="Transfer incomplete. Ownership rechecked; review the sword card."
  elif operation.error_code!=null:
   message="Transfer paused. Checking wallet; the sword remains reserved."
  else:message="Sword #"+str(int(operation.serial))+" · "+operation.status
  return

func begin_trial():
 message_operation_id=""
 if not online:connect_profile();return
 request("/api/sessions",HTTPClient.METHOD_POST,{},func(data):trial=data;claim_key="reward-"+str(data.id);action_key="";message="Guard against heavy attacks. Rest to recover stamina.")

func trial_action(action):
 if action_key=="":action_key=str(trial.id)+"-"+str(trial.turn);action_name=action
 request("/api/sessions/"+str(trial.id)+"/commands",HTTPClient.METHOD_POST,{"action":action_name,"turn":trial.turn,"idempotency_key":action_key},func(data):
  trial=data;action_key="";trial_pulse=0.6;game.sound("hit");message=""
  if trial.status=="won":message="Victory! Flame Sword earned. The smith will deliver it automatically.";game.sound("bell");refresh_status())

func claim_reward():
 request("/api/sessions/"+str(trial.id)+"/result",HTTPClient.METHOD_POST,{"idempotency_key":claim_key},func(data):message=data.message;selected_serial=int(data.get("serial",0));refresh_status())

func equip_item(serial):
 message_operation_id=""
 request("/api/relics/"+str(serial)+"/equip",HTTPClient.METHOD_POST,{},func(data):message=data.message;game.sound("loot");refresh_status())

func unequip_item():
 message_operation_id=""
 clear_use()
 request("/api/relics/equipment",HTTPClient.METHOD_DELETE,{},func(data):message=data.message;refresh_status())

func transfer_item(serial,recipient_id):
 message_operation_id=""
 clear_use()
 if transfer_intent.is_empty():
  transfer_intent={"serial":serial,"recipient_id":recipient_id,"key":Crypto.new().generate_random_bytes(16).hex_encode()}
 if int(transfer_intent.serial)!=serial or transfer_intent.recipient_id!=recipient_id:
  message="Check the previous transfer status first.";return
 request("/api/relics/"+str(serial)+"/transfer",HTTPClient.METHOD_POST,{"recipient_id":recipient_id,"confirm":true,"idempotency_key":transfer_intent.key},func(data):
  transfer_intent={};message_operation_id=data.id;message=data.message;refresh_status())

func equipped_damage() -> int:
 if equipment.is_empty() or Time.get_ticks_msec()>=lease_deadline:return 0
 return int(equipment.damage)

func profile_label(slot) -> String:
 var prefix="Test " if test_mode else "Player "
 if OS.has_feature("web"):prefix="Test WASM " if test_mode else "WASM "
 return prefix+str(slot)

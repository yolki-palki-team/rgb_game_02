extends Control
# A separate HTTPRequest keeps model polling independent from wallet leases.
var game
var http: HTTPRequest
var title: Label
var status: Label
var progress: ProgressBar
var transcript: RichTextLabel
var entry: LineEdit
var send_button: Button
var retry_button: Button
var clear_button: Button
var revision=0
var messages: Array=[]
var service: Dictionary={}
var pending_intent: Dictionary={}
var ready_history=false
var busy=false
var active=false
var poll=0.0
var identity=""
var request_identity=""
var request_kind=""
var last_error=""
var rendered=""
var base_override="" # Used only by the headless outage check.

func box(background,border) -> StyleBoxFlat:
 var s=StyleBoxFlat.new();s.bg_color=Color(background);s.border_color=Color(border)
 s.set_border_width_all(1);s.set_corner_radius_all(6)
 s.content_margin_left=14;s.content_margin_right=14;s.content_margin_top=10;s.content_margin_bottom=10
 return s

func _ready():
 set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 mouse_filter=Control.MOUSE_FILTER_STOP
 var shade=ColorRect.new();shade.color=Color(0.02,0.03,0.05,0.65);shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT);add_child(shade)
 var panel=PanelContainer.new();panel.position=Vector2(310,116);panel.size=Vector2(660,488)
 panel.add_theme_stylebox_override("panel",box("101c28","d9bd83"));add_child(panel)
 var column=VBoxContainer.new();column.add_theme_constant_override("separation",10);panel.add_child(column)
 var heading=HBoxContainer.new();column.add_child(heading)
 title=Label.new();title.text="BRAM  /  EMBERFALL'S SMITH";title.size_flags_horizontal=Control.SIZE_EXPAND_FILL
 title.add_theme_color_override("font_color",Color("d9bd83"));title.add_theme_font_size_override("font_size",21);heading.add_child(title)
 var close=Button.new();close.text="Close  [Esc]";close.pressed.connect(close_dialogue);heading.add_child(close)
 var note=Label.new();note.text="Local Qwen · Advice only · Items and transfers stay under your control"
 note.add_theme_font_size_override("font_size",13);note.add_theme_color_override("font_color",Color("8c9ba5"));column.add_child(note)
 transcript=RichTextLabel.new();transcript.custom_minimum_size=Vector2(620,245);transcript.size_flags_vertical=Control.SIZE_EXPAND_FILL
 transcript.bbcode_enabled=false;transcript.scroll_following=true;transcript.selection_enabled=true
 transcript.add_theme_stylebox_override("normal",box("172431","344753"));transcript.add_theme_color_override("default_color",Color("e3e1d6"));transcript.add_theme_font_size_override("normal_font_size",16);column.add_child(transcript)
 status=Label.new();status.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART;status.custom_minimum_size=Vector2(620,40)
 status.add_theme_font_size_override("font_size",14);status.add_theme_color_override("font_color",Color("82c3bb"));column.add_child(status)
 progress=ProgressBar.new();progress.custom_minimum_size.y=7;progress.show_percentage=false;column.add_child(progress)
 var row=HBoxContainer.new();column.add_child(row)
 entry=LineEdit.new();entry.placeholder_text="Ask about your gear or the Oath Trial…";entry.max_length=600
 entry.size_flags_horizontal=Control.SIZE_EXPAND_FILL;entry.add_theme_stylebox_override("normal",box("172431","425563"));entry.text_submitted.connect(func(_text):send_message());row.add_child(entry)
 send_button=Button.new();send_button.text="Send  [Enter]";send_button.pressed.connect(send_message);row.add_child(send_button)
 var footer=HBoxContainer.new();column.add_child(footer)
 clear_button=Button.new();clear_button.text="Clear conversation";clear_button.pressed.connect(clear_history);footer.add_child(clear_button)
 retry_button=Button.new();retry_button.text="Retry";retry_button.pressed.connect(retry);footer.add_child(retry_button)
 var hint=Label.new();hint.text="  Separate history for each profile · Last 12 messages";hint.add_theme_font_size_override("font_size",12);footer.add_child(hint)
 var theme_override=Theme.new();theme_override.default_font_size=15
 for kind in ["normal","hover","pressed","focus"]:theme_override.set_stylebox(kind,"Button",box("293e49" if kind=="hover" else "172431","d9bd83" if kind=="focus" else "425563"))
 theme_override.set_color("font_color","Button",Color("e3e1d6"));theme=theme_override
 http=HTTPRequest.new();http.timeout=8;add_child(http);http.request_completed.connect(completed)
 hide()

func current_identity() -> String:
 return game.net.profile_slot+":"+game.net.token

func reset_profile():
 http.cancel_request();busy=false;ready_history=false;revision=0;messages=[];service={};pending_intent={};entry.text="";last_error="";rendered="";poll=0
 identity=current_identity()

func open_dialogue():
 game.overlay="blacksmith";active=true;show()
 if identity!=current_identity():reset_profile()
 entry.grab_focus();poll=0;refresh();render()

func close_dialogue():
 active=false;hide();entry.release_focus()
 if game.overlay=="blacksmith":game.overlay=""

func _process(delta):
 if not active:return
 if game.overlay!="blacksmith":close_dialogue();return
 if identity!=current_identity():reset_profile();refresh()
 poll-=delta
 if poll<=0 and not busy:refresh();poll=1.0
 render()

func call_api(kind,method,body={}):
 if busy:return
 if game.net.token=="":last_error="Connecting your profile. Start the local game server if this persists.";return
 busy=true;request_identity=identity;request_kind=kind
 var path="/api/npc/blacksmith"
 if kind=="send":path+="/messages"
 if kind=="load":path+="/load"
 var base=base_override if base_override!="" else game.net.base
 var err=http.request(base+path,PackedStringArray(["Content-Type: application/json","Authorization: Bearer "+game.net.token]),method,"" if method==HTTPClient.METHOD_GET else JSON.stringify(body))
 if err!=OK:busy=false;last_error="Game server unavailable. Your message is kept; retry after reconnecting."

func refresh():call_api("history",HTTPClient.METHOD_GET)

func campaign() -> Dictionary:
 var owned: Array=[]
 for item in game.inventory:
  if item in ["iron","fang","rune","legendary","armor"]:owned.append(item)
 return {"health":clampf(game.health,0,100),"stamina":clampf(game.stamina,0,100),"gold":game.gold,"potions":game.potions,"inventory":owned,"weapon":game.weapon,"armor":game.armor}

func has_pending() -> bool:
 for row in messages:
  if row.status in ["queued","generating"]:return true
 return false

func send_message():
 if busy or not ready_history or has_pending() or not pending_intent.is_empty():return
 if service.get("state","")!="ready":return
 var text=entry.text.strip_edges()
 if text=="":return
 pending_intent={"text":text,"request_key":Crypto.new().generate_random_bytes(16).hex_encode(),"revision":revision,"campaign":campaign()}
 call_api("send",HTTPClient.METHOD_POST,pending_intent)

func clear_history():
 if busy or not ready_history:return
 call_api("clear",HTTPClient.METHOD_DELETE,{"revision":revision})

func retry():
 if busy:return
 if not ready_history or not last_error.is_empty():refresh();return
 if service.get("state","") in ["error","offline"]:call_api("load",HTTPClient.METHOD_POST);return
 if service.get("state","")!="ready" or has_pending():return
 if pending_intent.is_empty() and not messages.is_empty() and messages[-1].status=="failed":
  var row=messages[-1];pending_intent={"text":row.text,"request_key":row.request_key,"revision":revision,"campaign":campaign()}
 if not pending_intent.is_empty():call_api("send",HTTPClient.METHOD_POST,pending_intent)

func completed(result,code,_headers,body):
 busy=false
 if request_identity!=current_identity():return
 if result!=HTTPRequest.RESULT_SUCCESS:
  last_error="Game server unavailable or timed out. Your message is kept; retry after reconnecting.";return
 var data=JSON.parse_string(body.get_string_from_utf8())
 if not data is Dictionary:last_error="Game server returned an unreadable reply. Please retry.";return
 if code>=400:
  last_error=str(data.get("detail","The request could not be completed. Please retry."))
  if code in [409,422]:pending_intent={};ready_history=false
  return
 last_error=""
 match request_kind:
  "history":
   revision=int(data.revision);messages=data.messages;service=data.service;ready_history=true
   if not pending_intent.is_empty():
    for row in messages:
     if row.request_key==pending_intent.request_key:pending_intent={};entry.text="";break
  "send":
   var replaced=false
   for i in range(messages.size()):
    if messages[i].id==data.id:messages[i]=data;replaced=true;break
   if not replaced:messages.append(data)
   pending_intent={};entry.text="";poll=0
  "clear":revision=int(data.revision);messages=[];pending_intent={};rendered="";poll=0
  "load":poll=0
 render()

func render():
 title.text="BRAM  /  "+game.net.profile_label(game.net.profile_slot)
 var content="Ask Bram about your equipment, RGB items, or the Oath Trial.\nHe can advise you, but cannot change your items.\n"
 for row in messages:
  content+="\nYou: "+str(row.text)+"\n"
  if row.status=="completed":content+="Bram: "+str(row.reply)+"\n"
  elif row.status=="failed":content+="["+str(row.get("error","Reply interrupted. Please retry."))+"]\n"
  else:content+="Bram is preparing a reply…\n"
 if content!=rendered:transcript.text=content;rendered=content
 var state=service.get("state","connecting")
 var pending=has_pending()
 status.text="Ready · Qwen runs locally through QVAC."
 if not ready_history:status.text="Connecting to the game server…"
 elif pending:status.text="Preparing a reply… You may close this window and keep playing."
 elif state=="downloading":status.text="Downloading Qwen: %d%% · %.0f / %.0f MB" % [int(service.get("progress",0)),float(service.get("downloaded",0))/1000000,float(service.get("total",0))/1000000]
 elif state in ["starting","loading"]:status.text="Loading the local Qwen model… You can keep playing."
 elif state=="cancelling":status.text="Finishing an interrupted reply. Please wait."
 elif state=="generating":status.text="The smith is answering another visitor. Please wait."
 elif state=="offline":status.text="Local QVAC service is offline. Start RuneForge, then retry."
 elif state=="error":status.text="Could not load the local model. Check disk space, connection and memory; retry."
 if not pending_intent.is_empty() and not pending:status.text="Message delivery is unconfirmed. Retry sends the same request safely."
 if last_error!="":status.text=last_error
 progress.visible=state in ["downloading","loading","starting"]
 progress.value=float(service.progress) if service.get("progress")!=null else 0.0
 send_button.disabled=busy or not ready_history or pending or state!="ready" or not pending_intent.is_empty()
 clear_button.disabled=busy or not ready_history
 retry_button.visible=last_error!="" or state in ["offline","error"] or not pending_intent.is_empty() or (not messages.is_empty() and messages[-1].status=="failed")
 retry_button.disabled=busy or pending

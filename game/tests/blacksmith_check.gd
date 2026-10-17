extends SceneTree
var game
var failures: Array=[]
var evidence={"path":"Godot LineEdit -> authenticated FastAPI -> QVAC SDK -> local Qwen","manual_ui_check":false,"checks":[],"replies":[]}
func _initialize():run.call_deferred()
func check(ok,label):
 if ok:evidence.checks.append(label)
 else:failures.append(label)
func wait_until(condition: Callable,seconds=80.0) -> bool:
 var deadline=Time.get_ticks_msec()+int(seconds*1000)
 while Time.get_ticks_msec()<deadline:
  if condition.call():return true
  await create_timer(0.05).timeout
 return false
func key(code,pressed=true):
 var event=InputEventKey.new();event.keycode=code;event.physical_keycode=code;event.pressed=pressed;Input.parse_input_event(event);Input.flush_buffered_events()
func clear_dialogue(dialog):
 await wait_until(func():return not dialog.busy and dialog.ready_history)
 dialog.clear_history()
 await wait_until(func():return not dialog.busy and dialog.messages.is_empty())
func ask(dialog,text):
 if not await wait_until(func():return not dialog.busy and dialog.ready_history and dialog.service.get("state")=="ready" and not dialog.has_pending()):
  failures.append("Real QVAC ready: "+dialog.status.text);return {}
 dialog.entry.text=text;dialog.entry.grab_focus();key(KEY_ENTER);key(KEY_ENTER,false)
 # Enter and repeated Send are deliberately submitted during the same request.
 dialog.send_message();dialog.send_message()
 if not await wait_until(func():return not dialog.messages.is_empty() and dialog.messages[-1].text==text and dialog.messages[-1].status in ["completed","failed"]):
  failures.append("Response timeout: "+dialog.status.text);return {}
 var row=dialog.messages[-1]
 check(row.status=="completed","Real model reply: "+text)
 if row.status=="completed":
  check(row.model=="QWEN3_4B_Q4_K_M","Reply identifies local Qwen")
  evidence.replies.append({"question":text,"reply":row.reply,"model":row.model,"duration_ms":row.duration_ms})
 else:failures.append(str(row.get("error")))
 return row
func run():
 game=load("res://scenes/main.tscn").instantiate();root.add_child(game)
 game.smoke=true;game.start(false);game.net.connect_profile()
 if not await wait_until(func():return game.net.online and game.net.token!="" and not game.net.busy,20):
  failures.append("Backend must be running");finish();return
 if game.net.profile_slot!="A":game.net.switch_profile("A")
 await wait_until(func():return game.net.online and game.net.profile_slot=="A" and game.net.token!="" and not game.net.busy)
 game.hero=Vector2(770,745);key(KEY_E);key(KEY_E,false)
 var dialog=game.ui.blacksmith
 check(game.overlay=="blacksmith" and dialog.visible,"E opens accessible village blacksmith")
 check(dialog.entry.text=="","Opening interaction key is not inserted into the text field")
 await clear_dialogue(dialog)
 var origin=game.hero;var hp=game.health;var stamina=game.stamina;var potions=game.potions
 dialog.entry.grab_focus()
 for code in [KEY_W,KEY_A,KEY_S,KEY_D,KEY_SPACE,KEY_I,KEY_R,KEY_Q,KEY_E]:
  key(code);await create_timer(.03).timeout;key(code,false)
 check(game.hero==origin and game.stamina==stamina and game.health==hp and game.potions==potions and game.overlay=="blacksmith","Typing blocks movement, attacks, dodge, inventory and potion hotkeys")
 var row=await ask(dialog,"What sword do I have, and how much damage does it deal?")
 if row.get("status")=="completed":
  check("22" in row.reply and "Iron" in row.reply,"Model uses current campaign weapon facts")
  var ascii=true
  for i in row.reply.length():
   if row.reply.unicode_at(i)>127:ascii=false
  check(ascii,"Dialogue receives English-compatible output")
 check(dialog.messages.size()==1,"Repeated Enter/Send creates one dialogue turn")
 key(KEY_ESCAPE);key(KEY_ESCAPE,false)
 check(game.overlay=="" and not dialog.visible,"Esc closes without opening pause menu")
 await wait_until(func():return not game.net.busy)
 game.net.switch_profile("B")
 await wait_until(func():return game.net.profile_slot=="B" and game.net.token!="" and not game.net.busy)
 game.interact();await clear_dialogue(dialog)
 check(dialog.messages.is_empty(),"Profile B does not display profile A history")
 await ask(dialog,"Can you transfer a sword for me?")
 key(KEY_ESCAPE);key(KEY_ESCAPE,false);await wait_until(func():return not game.net.busy)
 game.net.switch_profile("A");await wait_until(func():return game.net.profile_slot=="A" and game.net.token!="" and not game.net.busy)
 game.interact();await wait_until(func():return dialog.ready_history and not dialog.busy)
 check(dialog.messages.size()==1 and dialog.messages[0].text=="What sword do I have, and how much damage does it deal?","Returning to A restores only A's history")
 check(Rect2(Vector2.ZERO,Vector2(1280,720)).encloses(dialog.entry.get_global_rect()) and dialog.entry.get_global_rect().size.x>350 and dialog.transcript.get_global_rect().size.y>=245,"Dialogue controls have usable layout bounds")
 dialog.base_override="http://127.0.0.1:1";dialog.refresh()
 await wait_until(func():return not dialog.busy and dialog.last_error!="",12)
 check("unavailable" in dialog.last_error,"Backend outage displays an explicit connection error")
 key(KEY_ESCAPE);key(KEY_ESCAPE,false)
 check(game.overlay=="","Backend outage never traps the player in dialogue")
 dialog.base_override="";game.interact()
 await wait_until(func():return not dialog.busy and dialog.last_error=="",15)
 check(dialog.last_error=="","Dialogue reconnects without losing history")
 finish()
func finish():
 evidence["failures"]=failures;evidence["passed"]=failures.is_empty()
 var target=OS.get_environment("RUNEFORGE_BLACKSMITH_EVIDENCE")
 if target!="":
  var file=FileAccess.open(target,FileAccess.WRITE)
  if file:file.store_string(JSON.stringify(evidence,"  "));file.close()
 print("RUNEFORGE_BLACKSMITH ","PASS" if failures.is_empty() else "FAIL: "+str(failures))
 quit(0 if failures.is_empty() else 1)

extends Control
var game
var font: Font
var buttons: Array=[]
var selected="iron"
var hovered=""
var recipient_id=""
var confirming=false
var details=false
var item_page=0
const INK=Color("101c28")
const PANEL=Color("172431")
const GOLD=Color("d9bd83")
const TEXT=Color("e3e1d6")
const MUTED=Color("8c9ba5")
const TEAL=Color("82c3bb")
const RARITIES=[Color("9ca8ad"),Color("82bc95"),Color("79b4df"),Color("b693d5"),Color("e6c07a")]

func _ready():
 font=ThemeDB.fallback_font
 mouse_filter=Control.MOUSE_FILTER_IGNORE

func label_at(p,s,size=18,color=TEXT):draw_string(font,p,str(s),HORIZONTAL_ALIGNMENT_LEFT,-1,size,color)
func line(a,b,color=Color("3e4c57")):draw_line(a,b,color,1)
func panel(rect,border=Color("46515a")):
 draw_style_box(style(INK,border,2),rect)
 for p in [rect.position+Vector2(7,7),Vector2(rect.end.x-7,rect.position.y+7),rect.end-Vector2(7,7),Vector2(rect.position.x+7,rect.end.y-7)]:draw_circle(p,1.5,GOLD)
func style(bg,border,width=1):
 var s=StyleBoxFlat.new();s.bg_color=bg;s.border_color=border;s.set_border_width_all(width);s.set_corner_radius_all(4);return s
func button(rect,title,action,accent=false,enabled=true):
 var over=rect.has_point(get_global_mouse_position())
 var col=Color("293e49") if over else PANEL
 draw_style_box(style(col,GOLD if accent else Color("425563")),rect)
 label_at(rect.position+Vector2(16,rect.size.y/2+6),title,16,(GOLD if accent else TEXT) if enabled else MUTED)
 if enabled:buttons.append({"rect":rect,"action":action})
func bar(rect,value,maxval,color):
 draw_style_box(style(Color("0b141f"),Color("37424d")),rect)
 var inner=rect.grow(-3);inner.size.x*=clampf(value/maxval,0,1)
 draw_style_box(style(color,color,0),inner)
 draw_line(rect.position+Vector2(4,4),Vector2(inner.end.x,rect.position.y+4),Color(1,1,1,0.16),1)
func icon(key,rect):draw_texture_rect(game.textures[key],rect,false)
func wrapped(p,text,width=350,size=17,color=MUTED):
 var words=text.split(" ");var row="";var yy=p.y
 for word in words:
  if font.get_string_size(row+word,HORIZONTAL_ALIGNMENT_LEFT,-1,size).x>width:
   label_at(Vector2(p.x,yy),row,size,color);yy+=25;row=""
  row+=word+" "
 label_at(Vector2(p.x,yy),row,size,color)

func _draw():
 if game==null or font==null:return
 buttons.clear()
 # Light vignette, letterboxed HUD with clear sightlines through the center.
 draw_rect(Rect2(0,0,1280,110),Color(0.02,0.04,0.07,0.3))
 if game.state=="menu":draw_menu();return
 draw_hud()
 if game.state=="dead":
  draw_rect(Rect2(0,0,1280,720),Color(0.02,0.03,0.05,0.85))
  label_at(Vector2(440,280),"THE EMBER FADES",38,GOLD)
  label_at(Vector2(420,330),"But your covenant has not been forgotten.",20,MUTED)
  button(Rect2(480,380,320,54),"Return to the shrine  ·  −20 gold",func():game.respawn(),true)
 elif game.overlay!="":
  draw_rect(Rect2(0,0,1280,720),Color(0.02,0.04,0.06,0.82))
  match game.overlay:
   "inventory":draw_inventory()
   "rgb":draw_rgb()
   "trial":draw_trial()
   "pause":draw_pause()
   "settings":draw_settings()
 if game.notice_time>0 and game.overlay not in ["rgb","trial"]:
  var width=mini(1170,int(font.get_string_size(game.notice,HORIZONTAL_ALIGNMENT_LEFT,-1,17).x+60))
  panel(Rect2((1280-width)/2.0,606,width,48),Color("6e6758"))
  label_at(Vector2((1280-width)/2.0+24,637),game.notice,17,GOLD)

func draw_menu():
 draw_rect(Rect2(0,0,1280,720),Color(0.02,0.04,0.06,0.72))
 # A vertical rune and restrained typography form the game's visual signature.
 icon("icon",Rect2(140,110,72,72))
 label_at(Vector2(140,224),"ASHES OF THE COVENANT",15,TEAL)
 label_at(Vector2(136,304),"RUNEFORGE",68,TEXT)
 line(Vector2(140,330),Vector2(635,330),GOLD)
 wrapped(Vector2(140,368),"A dying flame. An ancient oath. Beneath Emberfall, something still remembers your name.",440,20,MUTED)
 button(Rect2(140,450,300,50),"Begin Journey",func():game.start(false),true)
 button(Rect2(140,512,300,46),"Continue",func():game.start(true),false,FileAccess.file_exists(game.SAVE_PATH))
 button(Rect2(454,450,180,50),"Settings",func():game.state="play";game.overlay="settings")
 button(Rect2(454,512,180,46),"Quit",func():game.quit_game())
 label_at(Vector2(140,657),"CHAPTER I   /   THE HOLLOW CRYPT",14,MUTED)
 panel(Rect2(855,160,290,380),Color("57615f"))
 icon("legendary",Rect2(925,210,148,148))
 label_at(Vector2(890,405),"RECLAIM THE DAWN",20,GOLD)
 wrapped(Vector2(890,443),"Explore. Dodge. Endure. A complete single-player covenant awaits.",220,17,MUTED)
 if game.notice_time>0:label_at(Vector2(140,600),game.notice,16,GOLD)

func draw_hud():
 panel(Rect2(24,22,306,102))
 icon("icon",Rect2(38,38,53,53))
 label_at(Vector2(104,48),"THE ASHEN WARDEN",13,GOLD)
 bar(Rect2(104,61,206,20),game.health,100,Color("a74d5b"))
 bar(Rect2(104,88,206,10),game.stamina,100,Color("5a9f9b"))
 label_at(Vector2(107,115),str(int(game.health))+" / 100",11,MUTED)
 panel(Rect2(966,22,290,96))
 label_at(Vector2(985,48),"THE LAST COVENANT",13,GOLD)
 var objectives=["Speak to the keeper  [E]","Enter the eastern crypt","Defeat the Shadow Guardian","Return to the keeper","Emberfall is safe. Explore freely."]
 label_at(Vector2(985,76),objectives[clampi(game.quest,0,4)],16,TEXT)
 label_at(Vector2(985,100),"CHAPTER I  ·  "+("COMPLETE" if game.quest==4 else "IN PROGRESS"),11,MUTED)
 label_at(Vector2(560,39),"EMBERFALL" if game.hero.x<1080 else "THE HOLLOW CRYPT",16,GOLD)
 label_at(Vector2(579,61),"A S H E S   &   O A T H S",10,MUTED)
 panel(Rect2(24,644,340,54))
 icon(game.weapon_icon(),Rect2(36,650,42,42))
 label_at(Vector2(90,666),game.weapon_name(),16,GOLD)
 label_at(Vector2(90,685),str(game.weapon_damage())+" ATK   /   LMB attack",12,MUTED)
 panel(Rect2(380,644,154,54))
 icon("potion",Rect2(390,654,32,32));label_at(Vector2(430,678),"Q  ×"+str(game.potions),18,TEXT)
 icon("gold",Rect2(554,655,28,28));label_at(Vector2(592,678),str(game.gold)+" gold",20,GOLD)
 button(Rect2(774,650,138,42),"I  Inventory",func():game.overlay="inventory")
 button(Rect2(922,650,160,42),"R  Items",func():game.overlay="rgb";game.net.refresh_status())
 button(Rect2(1092,650,164,42),"Esc  Journal",func():game.overlay="pause")
 label_at(Vector2(31,143),"WASD Move   ·   Space Dodge   ·   E Interact",12,MUTED)
 # Boss health appears only in the arena.
 for e in game.enemies:
  if e.kind=="boss" and e.hp>0 and game.hero.distance_to(e.p)<540:
   panel(Rect2(395,90,490,68),Color("67566e"))
   label_at(Vector2(420,113),"SHADOW GUARDIAN",16,GOLD)
   label_at(Vector2(740,113),"PHASE "+str(e.phase),12,MUTED)
   bar(Rect2(418,125,442,12),e.hp,e.max,Color("946587"))
 # Compact map: actual traversable tiles and player position.
 panel(Rect2(1134,137,122,84))
 for cell in game.walls:
  if cell.x%2==0 and cell.y%2==0:draw_rect(Rect2(1141+cell.x*2.1,145+cell.y*2.1,3,3),Color("34434d"))
 draw_circle(Vector2(1141+game.hero.x/48*2.1,145+game.hero.y/48*2.1),3,GOLD)

func draw_inventory():
 hovered=""
 panel(Rect2(160,105,960,484),Color("69706b"))
 label_at(Vector2(192,150),"THE WARDEN'S SATCHEL",28,GOLD)
 label_at(Vector2(194,179),"LOCAL CAMPAIGN  /  Equipment and relics",13,MUTED)
 button(Rect2(1008,125,86,34),"Close",func():game.overlay="")
 line(Vector2(192,198),Vector2(1086,198))
 for i in range(16):
  var rect=Rect2(194+(i%4)*78,220+(i/4)*78,66,66)
  var id=game.inventory[i] if i<game.inventory.size() else ""
  var color=RARITIES[game.ITEMS[id].rarity] if id!="" else Color("35424d")
  draw_style_box(style(PANEL,color,2 if id==selected else 1),rect)
  if id!="":
   icon(game.ITEMS[id].icon,rect.grow(-9))
   buttons.append({"rect":rect,"action":func():selected=id})
   if rect.has_point(get_global_mouse_position()):hovered=id
   if id in [game.weapon,game.armor]:draw_circle(rect.end-Vector2(8,8),3,TEAL)
 var id=selected if selected in game.inventory else "iron"
 var item=game.ITEMS[id]
 icon(item.icon,Rect2(574,225,82,82))
 label_at(Vector2(682,253),item.name,24,RARITIES[item.rarity])
 label_at(Vector2(684,283),["COMMON","UNCOMMON","RARE","EPIC","LEGENDARY"][item.rarity]+"  /  "+item.slot.to_upper(),12,MUTED)
 wrapped(Vector2(580,342),item.desc,460,18,TEXT)
 label_at(Vector2(580,422),"ATTACK  "+str(item.damage) if item.slot=="weapon" else "DAMAGE REDUCTION  30%",16,GOLD)
 label_at(Vector2(580,454),"Ownership: local save · not an RGB asset",14,MUTED)
 button(Rect2(580,488,210,48),"Equipped" if id in [game.weapon,game.armor] else "Equip item",func():game.equip(id),true)
 for i in range(2):
  var equipped=game.weapon if i==0 else game.armor
  var slot=Rect2(842+i*100,475,64,64)
  draw_style_box(style(PANEL,TEAL),slot)
  if equipped!="":icon(game.ITEMS[equipped].icon,slot.grow(-10))
  label_at(slot.position+Vector2(0,82),"WEAPON" if i==0 else "ARMOR",11,MUTED)
 label_at(Vector2(194,563),"Click an item to inspect it.  Colored borders indicate rarity.",14,MUTED)
 if hovered!="":
  var info=game.ITEMS[hovered]
  var pos=get_global_mouse_position()+Vector2(16,16)
  pos.x=minf(pos.x,960);pos.y=minf(pos.y,590)
  panel(Rect2(pos,Vector2(280,64)),RARITIES[info.rarity])
  label_at(pos+Vector2(14,25),info.name,17,RARITIES[info.rarity])
  label_at(pos+Vector2(14,48),info.slot.capitalize()+" · "+str(info.damage)+" ATK",13,MUTED)

func draw_pause():
 panel(Rect2(400,165,480,390),Color("65716c"))
 label_at(Vector2(440,217),"THE COVENANT",30,GOLD)
 label_at(Vector2(440,251),"Your journey is saved automatically.",17,MUTED)
 button(Rect2(440,282,400,46),"Resume journey",func():game.overlay="",true)
 button(Rect2(440,341,400,46),"Settings",func():game.overlay="settings")
 button(Rect2(440,400,400,46),"Save & return to title",func():game.save_game();game.overlay="";game.state="menu")
 button(Rect2(440,459,400,46),"Save & quit",func():game.quit_game())

func draw_settings():
 panel(Rect2(400,165,480,390),Color("65716c"))
 label_at(Vector2(440,217),"SETTINGS",30,GOLD)
 button(Rect2(440,270,400,48),"Sound: "+("Off" if game.muted else "On"),func():game.muted=not game.muted;game.save_settings())
 button(Rect2(440,332,400,48),"Screen shake: "+("On" if game.screen_shake else "Off"),func():game.screen_shake=not game.screen_shake;game.save_settings())
 button(Rect2(440,394,400,48),"Toggle fullscreen",func():DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN))
 button(Rect2(440,470,400,42),"Back",func():game.overlay="" if game.menu_started else "";game.state="play" if game.menu_started else "menu",true)

func draw_rgb():
 var net=game.net
 panel(Rect2(60,65,1160,558),Color("65716c"))
 label_at(Vector2(86,105),"OATH FORGE",28,GOLD)
 for j in range(2):
  var slot=["A","B"][j]
  button(Rect2(600+j*150,81,140,34),net.profile_label(slot),func():net.switch_profile(slot);confirming=false;recipient_id="",net.profile_slot==slot,not net.busy)
 button(Rect2(910,81,170,34),"Trial",func():game.overlay="trial",true)
 button(Rect2(1100,81,92,34),"Close",func():game.overlay="")
 label_at(Vector2(86,136),str(net.profile.get("name",""))+" · "+str(net.profile.get("id","")).left(8)+"  |  "+net.status,14,TEAL if net.service.get("available",false) else Color("da9c91"))
 line(Vector2(86,150),Vector2(1192,150))
 label_at(Vector2(86,177),"YOUR ITEMS",13,MUTED)
 if net.items.is_empty():
  wrapped(Vector2(86,220),"Complete the Oath Trial. The smith will issue one unique Flame Sword for your reward.",238,17,TEXT)
  button(Rect2(86,360,245,44),"Enter the trial",func():game.overlay="trial",true)
 item_page=clampi(item_page,0,maxi(0,(net.items.size()-1)/4))
 for j in range(item_page*4,mini(net.items.size(),item_page*4+4)):
  var item=net.items[j];var y=195+(j%4)*79
  button(Rect2(86,y,248,69),"",func():net.selected_serial=int(item.serial);confirming=false,net.selected_serial==int(item.serial))
  icon("legendary",Rect2(97,y+10,45,45))
  label_at(Vector2(151,y+28),"Flame Sword #"+str(int(item.serial)),15,GOLD)
  label_at(Vector2(151,y+50),"Yours" if item.is_owner else ("Transferred" if item.owner_id!=null else "In transit"),13,MUTED)
 if net.items.size()>4:
  button(Rect2(86,524,116,32),"←",func():item_page-=1,false,item_page>0)
  button(Rect2(214,524,120,32),"→",func():item_page+=1,false,(item_page+1)*4<net.items.size())
 line(Vector2(354,173),Vector2(354,553))
 var chosen={}
 for item in net.items:
  if int(item.serial)==net.selected_serial:chosen=item
 if not chosen.is_empty():
  icon("legendary",Rect2(378,177,100,100))
  label_at(Vector2(501,202),chosen.name+"  #"+str(int(chosen.serial)),27,GOLD)
  label_at(Vector2(503,232),"LEGENDARY   /   DAMAGE  "+str(int(chosen.damage))+"   /   RGB UDA",15,TEAL)
  var available=net.online and net.service.get("available",false)
  var ownership_text=chosen.status if chosen.is_owner or chosen.owner_id==null else "Transferred to another player · unavailable"
  if not available:ownership_text="Connection lost · item use suspended"
  label_at(Vector2(503,259),ownership_text,16,TEXT)
  wrapped(Vector2(382,298),chosen.description,780,16,MUTED)
  button(Rect2(382,345,200,42),"Equipped" if net.equipped_damage()>0 and int(net.equipment.get("serial",0))==int(chosen.serial) else "Equip",func():net.equip_item(int(chosen.serial)),true,chosen.can_equip and available and not net.busy)
  button(Rect2(596,345,200,42),"Transfer",func():confirming=not confirming;recipient_id="",false,chosen.can_equip and available and not net.busy)
  button(Rect2(810,345,194,42),"Details  "+("−" if details else "+"),func():details=not details)
  if confirming:
   var recipients=net.players.duplicate()
   # Put the other local demo profile first; all choices still use real server identities.
   var other=net.profiles.get("B" if net.profile_slot=="A" else "A",{}).get("id","")
   recipients.sort_custom(func(a,b):return a.id==other and b.id!=other)
   if not recipients.is_empty():
    var recipient_index=0
    for k in range(recipients.size()):
     if recipients[k].id==recipient_id:recipient_index=k;break
    var receiver=recipients[recipient_index]
    recipient_id=receiver.id
    button(Rect2(382,403,420,40),"To: "+receiver.name+" · "+receiver.id.left(8)+"  ▸",func():recipient_id=recipients[(recipient_index+1)%recipients.size()].id)
    button(Rect2(818,403,354,40),"Confirm transfer",func():net.transfer_item(int(chosen.serial),receiver.id);confirming=false,true,available and chosen.can_equip and not net.busy)
    wrapped(Vector2(382,468),"The sword will be unequipped and reserved during verification. Once received, only the selected player can use it.",775,15,TEXT)
   else:label_at(Vector2(382,430),"No other profiles. Connect Player B first.",16,MUTED)
  elif details:
   label_at(Vector2(382,417),"Verified game asset · separate wallet · Bitcoin regtest",14,TEAL)
   wrapped(Vector2(382,444),str(chosen.asset_id) if chosen.asset_id!=null else "The asset_id appears after real issuance.",780,14,TEXT)
   for op in net.history:
    if int(op.serial)!=int(chosen.serial):continue
    if op.txid!=null:label_at(Vector2(382,492),"txid: "+str(op.txid),12,MUTED)
    if op.error_code!=null:label_at(Vector2(382,520),"Diagnostics: "+str(op.error_code),13,MUTED)
    break
  else:
   label_at(Vector2(382,417),"SWORD HISTORY",13,MUTED)
   var history_y=444
   for op in net.history:
    if int(op.serial)!=int(chosen.serial) or history_y>516:continue
    label_at(Vector2(382,history_y),("Reward" if op.kind=="award" else "→ "+op.recipient_name)+" · "+op.status,15,TEXT)
    history_y+=24
    if op.error_code!=null:
     label_at(Vector2(382,history_y),"Operation paused for wallet verification. Sword reserved.",13,Color("da9c91"))
     history_y+=24
 label_at(Vector2(86,580),"Wallet keys are held by the local RuneForge service. Campaign gold is ordinary game currency.",14,MUTED)
 if net.message!="":
  panel(Rect2(60,632,1160,62))
  wrapped(Vector2(86,657),net.message,1100,15,GOLD)

func trial_actor(kind,p,size):
 var frame=int(game.t*4)%4
 draw_texture_rect_region(game.textures[kind],Rect2(p,size),Rect2(frame*40,0,40,48))

func draw_trial():
 var net=game.net;var trial=net.trial
 panel(Rect2(120,65,1040,558),Color("65716c"))
 label_at(Vector2(154,112),"OATH TRIAL",29,GOLD)
 button(Rect2(890,85,235,38),"My items",func():game.overlay="rgb";net.refresh_status())
 label_at(Vector2(154,144),"Tactical duel · server-verified · profile "+net.profile_slot,15,TEAL)
 wrapped(Vector2(154,180),"Smith: survive the duel and I will forge your Flame Sword. Read the Guardian: guard against heavy attacks and rest when your stamina runs low.",940,17,TEXT)
 for j in range(20):
  draw_texture_rect_region(game.textures.floor,Rect2(155+j*48,253,48,265),Rect2((j%6)*24,0,24,24))
 draw_rect(Rect2(155,253,960,265),Color(0.02,0.03,0.05,0.5))
 draw_arc(Vector2(640,430),135,0,TAU,64,Color("6b586c"),2)
 trial_actor("player",Vector2(305,318),Vector2(100,120))
 trial_actor("boss",Vector2(805,282),Vector2(145,174))
 if net.trial_pulse>0:draw_arc(Vector2(730,370),83,-1.5,1.4,24,Color(1,0.7,0.4,net.trial_pulse),7)
 if trial.is_empty():
  icon("legendary",Rect2(600,292,80,80))
  label_at(Vector2(487,427),"Reward: Flame Sword · 52 damage",18,GOLD)
  button(Rect2(460,542,360,46),"Accept challenge",func():net.begin_trial(),true,not net.busy and net.online)
 else:
  bar(Rect2(260,275,210,17),trial.get("hp",0),100,Color("a74d5b"))
  bar(Rect2(260,300,210,9),trial.get("stamina",0),100,TEAL)
  bar(Rect2(780,255,210,17),trial.get("enemy_hp",0),180,Color("946587"))
  if trial.status=="active":
   var intent={"heavy":"HEAVY ATTACK — guard","sweep":"Sweeping attack","bolt":"Magic bolt","recover":"Guardian is recovering"}.get(trial.intent,str(trial.intent))
   label_at(Vector2(435,485),intent,19,GOLD)
   for j in range(3):
    var action=["attack","guard","rest"][j]
    button(Rect2(260+j*260,542,240,46),["Attack","Guard","Rest"][j],func():net.trial_action(action),j==0,not net.busy)
  elif trial.status=="won":
   icon("legendary",Rect2(600,305,80,80))
   label_at(Vector2(465,450),"VICTORY · SWORD EARNED",24,GOLD)
   label_at(Vector2(390,485),"The smith issues and delivers your reward automatically.",16,TEXT)
   button(Rect2(460,542,360,46),"Track delivery",func():game.overlay="rgb";net.refresh_status(),true)
  else:
   label_at(Vector2(470,470),"The Oath demands another attempt.",20,GOLD)
   button(Rect2(460,542,360,46),"Try again",func():net.begin_trial(),true,not net.busy)
 if net.message!="" or not net.online:
  panel(Rect2(120,632,1040,62))
  wrapped(Vector2(154,657),net.message if net.online else net.status,970,15,GOLD)

func _input(event):
 if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
  for b in buttons:
   if b.rect.has_point(get_global_mouse_position()):
    b.action.call();get_viewport().set_input_as_handled();queue_redraw();return

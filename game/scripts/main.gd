extends Node2D

const TILE = 48
const WORLD = Vector2(2400, 1440)
const SAVE_PATH = "user://runeforge_v1.json"
const ITEMS = {
 "iron": {"name":"Warden's Iron", "icon":"sword", "rarity":0, "damage":22, "slot":"weapon", "desc":"A faithful blade, worn smooth by a hundred vigils."},
 "fang": {"name":"Briar Fang", "icon":"fang", "rarity":1, "damage":29, "slot":"weapon", "desc":"Goblin steel. Light, cruel, and surprisingly well balanced."},
 "rune": {"name":"Covenant Edge", "icon":"rune", "rarity":2, "damage":36, "slot":"weapon", "desc":"The old runes still remember the names of the fallen."},
 "armor": {"name":"Ashen Plate", "icon":"armor", "rarity":3, "damage":0, "slot":"armor", "desc":"Forged beneath a dying star. Reduces incoming damage by 30%."},
 "legendary": {"name":"Dawn of the Forsaken", "icon":"legendary", "rarity":4, "damage":48, "slot":"weapon", "desc":"The Guardian's final gift. A local campaign relic; no RGB ownership claim."},
 "potion": {"name":"Crimson Draught", "icon":"potion", "rarity":0, "damage":0, "slot":"consumable", "desc":"Restores 45 health. Press Q to drink during combat."}
}
var textures = {}
var sounds = {}
var walls = {}
var props: Array = []
var enemies: Array = []
var drops: Array = []
var bolts: Array = []
var particles: Array = []
var texts: Array = []
var chests: Array = []
var hero = Vector2(480, 720)
var facing = Vector2.RIGHT
var health = 100.0
var stamina = 100.0
var gold = 0
var potions = 3
var inventory: Array = ["iron"]
var weapon = "iron"
var armor = ""
var killed: Array = []
var opened: Array = []
var quest = 0
var boss_dead = false
var attack_cd = 0.0
var slash_time = 0.0
var roll_time = 0.0
var invulnerable = 0.0
var hurt_flash = 0.0
var shake = 0.0
var t = 0.0
var walk = false
var state = "menu"
var overlay = ""
var notice = ""
var notice_time = 0.0
var menu_started = false
var camera: Camera2D
var ui: Control
var net: Node
var screen_shake = true
var muted = false
var stats = {"attacks":0, "dodges":0, "distance":0.0, "samples":0, "damage":0.0, "duration":0.0}
var autosave = 0.0
var audio: AudioStreamPlayer
var smoke = false
var death_count = 0

func _ready():
 randomize()
 var settings=ConfigFile.new()
 if settings.load("user://settings.cfg")==OK:
  muted=settings.get_value("game","muted",false)
  screen_shake=settings.get_value("game","screen_shake",true)
 for key in ["player","skeleton","goblin","mage","boss","elder","blacksmith","anvil","floor","earth","path","wall","water","tree","house","chest","fire","shrine","grave","torch","sword","fang","rune","legendary","potion","armor","gold","glow","icon","banner","pillar","rubble","bones","bush","carpet"]:
  textures[key] = load("res://assets/" + key + ".png")
 for key in ["hit","slash","loot","roll","hurt","bell"]:
  sounds[key] = load("res://assets/" + key + ".wav")
 audio = AudioStreamPlayer.new()
 add_child(audio)
 camera = Camera2D.new()
 camera.position = hero
 camera.position_smoothing_enabled = true
 camera.position_smoothing_speed = 8
 camera.limit_left = 0
 camera.limit_top = 0
 camera.limit_right = 2400
 camera.limit_bottom = 1440
 add_child(camera)
 var layer = CanvasLayer.new()
 add_child(layer)
 ui = Control.new()
 ui.set_script(load("res://scripts/interface.gd"))
 ui.game = self
 layer.add_child(ui)
 net = Node.new()
 net.set_script(load("res://scripts/network.gd"))
 net.game = self
 add_child(net)
 build_world()
 smoke = "--blacksmith-check" in OS.get_cmdline_user_args() or "--verify-sword4" in OS.get_cmdline_user_args() or "--outage-game-check" in OS.get_cmdline_user_args() or "--managed-game-check" in OS.get_cmdline_user_args() or "--smoke" in OS.get_cmdline_user_args() or "--network-smoke" in OS.get_cmdline_user_args()
 if "--smoke" in OS.get_cmdline_user_args():
  run_smoke.call_deferred()
 if "--network-smoke" in OS.get_cmdline_user_args():
  run_network_smoke.call_deferred()
 if "--verify-sword4" in OS.get_cmdline_user_args():
  run_sword4_check.call_deferred()
 if "--managed-game-check" in OS.get_cmdline_user_args():
  run_managed_check.call_deferred()
 if "--outage-game-check" in OS.get_cmdline_user_args():
  run_outage_check.call_deferred()
 if "--capture" in OS.get_cmdline_user_args():
  start(false)
  hero = Vector2(480,720)
  quest=1
  if "--view=crypt" in OS.get_cmdline_user_args():hero=Vector2(1370,720);quest=2
  if "--view=boss" in OS.get_cmdline_user_args():hero=Vector2(2020,870);quest=2
  if "--view=inventory" in OS.get_cmdline_user_args():
   inventory=["iron","fang","rune","armor","legendary"];overlay="inventory";ui.selected="legendary"
  if "--view=menu" in OS.get_cmdline_user_args():state="menu"
  if "--view=vault" in OS.get_cmdline_user_args():overlay="rgb"
  if "--view=trial" in OS.get_cmdline_user_args():overlay="trial"
  if "--view=transfer" in OS.get_cmdline_user_args():overlay="rgb";ui.confirming=true
  notice_time=0
  camera.position = hero
  camera.reset_smoothing()
  capture.call_deferred()

func build_world():
 walls.clear()
 props.clear()
 enemies.clear()
 chests.clear()
 # Village clearing, connecting passage, crypt halls and a final arena.
 for y in range(30):
  for x in range(50):
   var open = (x>=2 and x<=18 and y>=4 and y<=25) or (x>=18 and x<=23 and y>=13 and y<=16) or (x>=23 and x<=34 and y>=5 and y<=25) or (x>=34 and x<=38 and y>=13 and y<=16) or (x>=38 and x<=47 and y>=7 and y<=24)
   if not open: walls[Vector2i(x,y)] = true
 for p in [Vector2i(26,10),Vector2i(31,10),Vector2i(26,19),Vector2i(31,19),Vector2i(40,10),Vector2i(45,10),Vector2i(40,21),Vector2i(45,21)]:
  walls[p] = true
 for x in range(3,19,3):
  props.append({"kind":"tree","p":Vector2(x*48,240),"scale":2.0})
  props.append({"kind":"tree","p":Vector2(x*48+20,1220),"scale":2.0})
 for p in [Vector2(185,460),Vector2(850,420),Vector2(190,880),Vector2(870,1020),Vector2(240,1150)]:
  props.append({"kind":"tree","p":p,"scale":2.0})
 for p in [Vector2(400,440),Vector2(740,490),Vector2(430,1080)]:
  props.append({"kind":"house","p":p,"scale":1.6})
  for x in range(int((p.x-80)/48),int((p.x+80)/48)+1):
   for y in range(int((p.y-68)/48),int((p.y-10)/48)+1):walls[Vector2i(x,y)]=true
 props.append({"kind":"fire","p":Vector2(510,590),"scale":1.6})
 props.append({"kind":"elder","p":Vector2(650,660),"scale":1.7})
 props.append({"kind":"blacksmith","p":Vector2(800,720),"scale":1.7})
 props.append({"kind":"anvil","p":Vector2(853,740),"scale":1.3})
 props.append({"kind":"shrine","p":Vector2(330,740),"scale":1.8})
 for p in [Vector2(1150,600),Vector2(1150,860),Vector2(1640,560),Vector2(1640,1110),Vector2(1870,610),Vector2(1870,840),Vector2(2210,510),Vector2(2210,1100)]:
  props.append({"kind":"torch","p":p,"scale":2.0})
 for i in range(16):
  props.append({"kind":"grave","p":Vector2(1180+(i%4)*125,330+(i/4)*250),"scale":1.4})
 for p in [Vector2(1248,528),Vector2(1488,528),Vector2(1248,960),Vector2(1488,960),Vector2(1920,528),Vector2(2160,528),Vector2(1920,1056),Vector2(2160,1056)]:
  props.append({"kind":"pillar","p":p+Vector2(24,24),"scale":1.6})
 for p in [Vector2(1140,470),Vector2(1650,470),Vector2(1840,590),Vector2(2250,590)]:
  props.append({"kind":"banner","p":p,"scale":1.6})
 for i in range(18):
  props.append({"kind":"bush","p":Vector2(220+(i*173)%650,300+(i*217)%880),"scale":1.5})
 for i in range(12):
  props.append({"kind":"rubble" if i%3!=0 else "bones","p":Vector2(1160+(i*163)%1050,410+(i*237)%730),"scale":1.3})
 var spawns = [["skeleton",Vector2(1260,660)],["goblin",Vector2(1430,780)],["skeleton",Vector2(1480,480)],["mage",Vector2(1520,1040)],["goblin",Vector2(1290,1070)],["mage",Vector2(1620,730)],["skeleton",Vector2(1600,1200)],["boss",Vector2(2070,740)]]
 for i in range(spawns.size()):
  if i in killed: continue
  var kind = spawns[i][0]
  var hp = {"skeleton":66.0,"goblin":46.0,"mage":58.0,"boss":640.0}[kind]
  enemies.append({"id":i,"kind":kind,"p":spawns[i][1],"home":spawns[i][1],"hp":hp,"max":hp,"state":"idle","timer":0.0,"cooldown":1.0,"flash":0.0,"phase":1,"attack":0,"target":Vector2.ZERO,"angle":0.0})
 for i in range(3):
  chests.append({"id":i,"p":[Vector2(780,850),Vector2(1530,340),Vector2(1510,1180)][i],"open":i in opened})

func start(continuing: bool):
 if continuing and not load_game(): return
 if not continuing:
  hero=Vector2(480,720);health=100;stamina=100;gold=0;potions=3;inventory=["iron"];weapon="iron";armor="";killed=[];opened=[];quest=0;boss_dead=false
  drops.clear();bolts.clear();particles.clear();texts.clear()
  stats={"attacks":0,"dodges":0,"distance":0.0,"samples":0,"damage":0.0,"duration":0.0}
 build_world()
 state="play";overlay="";menu_started=true
 camera.position=hero;camera.reset_smoothing()
 announce("EMBERFALL  /  Speak to the keeper [E]",4.0)
 if not smoke:net.connect_profile()

func solid(p: Vector2, radius=12.0) -> bool:
 for offset in [Vector2(-radius,-radius),Vector2(radius,-radius),Vector2(-radius,radius),Vector2(radius,radius)]:
  var v=p+offset
  if walls.has(Vector2i(floori(v.x/TILE),floori(v.y/TILE))):return true
 return false

func move_body(p: Vector2, delta: Vector2, radius=12.0) -> Vector2:
 # Small substeps prevent rolling through one-tile walls at low frame rates.
 var steps=maxi(1,ceili(delta.length()/8.0))
 var step=delta/steps
 for i in range(steps):
  if not solid(p+Vector2(step.x,0),radius):p.x+=step.x
  if not solid(p+Vector2(0,step.y),radius):p.y+=step.y
 return p

func line_clear(a: Vector2,b: Vector2) -> bool:
 var count=maxi(1,ceili(a.distance_to(b)/16.0))
 for i in range(1,count):
  if solid(a.lerp(b,float(i)/count),2):return false
 return true

func _process(dt):
 var d=minf(dt,0.05)
 t+=d
 notice_time=maxf(0,notice_time-d)
 if state=="play" and overlay=="":
  update_player(d)
  update_enemies(d)
  update_projectiles(d)
  autosave+=d
  if autosave>12:
   save_game();autosave=0
 for i in range(particles.size()-1,-1,-1):
  particles[i].life-=d;particles[i].p+=particles[i].v*d;particles[i].v*=0.96
  if particles[i].life<=0:particles.remove_at(i)
 for i in range(texts.size()-1,-1,-1):
  texts[i].life-=d;texts[i].p.y-=d*25
  if texts[i].life<=0:texts.remove_at(i)
 shake=maxf(0,shake-d*20)
 camera.position=hero+Vector2(randf_range(-shake,shake),randf_range(-shake,shake))*(1 if screen_shake else 0)
 queue_redraw();ui.queue_redraw()

func update_player(d):
 attack_cd=maxf(0,attack_cd-d);slash_time=maxf(0,slash_time-d);roll_time=maxf(0,roll_time-d);invulnerable=maxf(0,invulnerable-d);hurt_flash=maxf(0,hurt_flash-d)
 stamina=minf(100,stamina+d*(16 if roll_time>0 else 27))
 var direction=Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W))).normalized()
 walk=direction.length()>0
 if roll_time>0:hero=move_body(hero,facing*d*520)
 else:
  hero=move_body(hero,direction*d*190)
  var mouse=get_global_mouse_position()-hero
  if mouse.length()>4:facing=mouse.normalized()
 if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and attack_cd<=0:attack()
 for i in range(drops.size()-1,-1,-1):
  if hero.distance_to(drops[i].p)<38:
   var item=drops[i].item
   if item=="gold":gold+=drops[i].amount
   elif item=="potion":potions+=1
   elif not item in inventory:inventory.append(item)
   sound("loot");burst(drops[i].p,Color("ddc285"),10);drops.remove_at(i)
 if hero.x>1080 and quest==1:quest=2;announce("THE HOLLOW CRYPT  /  Find the Shadow Guardian",4)

func attack():
 if roll_time>0 or stamina<12:return
 attack_cd=0.34;slash_time=0.19;stamina-=12;stats.attacks+=1
 sound("slash")
 for e in enemies:
  var to=e.p-hero
  if e.hp>0 and to.length()<(118 if e.kind=="boss" else 94) and facing.dot(to.normalized())>0.05 and line_clear(hero,e.p):
   hit_enemy(e,float(weapon_damage()))

func dodge():
 if stamina<30 or roll_time>0:return
 stamina-=30;roll_time=0.25;invulnerable=0.32;stats.dodges+=1;sound("roll")
 var dir=Vector2(float(Input.is_physical_key_pressed(KEY_D))-float(Input.is_physical_key_pressed(KEY_A)),float(Input.is_physical_key_pressed(KEY_S))-float(Input.is_physical_key_pressed(KEY_W)))
 if dir.length()>0:facing=dir.normalized()
 burst(hero,Color("7baba9"),9)

func hit_enemy(e,amount):
 e.hp-=amount;e.flash=0.15
 floating(e.p-Vector2(0,50),str(int(amount)),Color("f2dbac"));burst(e.p-Vector2(0,24),Color("c7b297"),10)
 if e.kind!="boss":
  e.p=move_body(e.p,(e.p-hero).normalized()*16);e.state="hurt";e.timer=0.2
 shake=3;sound("hit")
 if e.hp<=0:
  e.state="dead";e.timer=0.7;killed.append(e.id)
  drops.append({"p":e.p,"item":"gold","amount":80 if e.kind=="boss" else 12})
  if e.kind=="goblin" and not "fang" in inventory:drops.append({"p":e.p+Vector2(20,0),"item":"fang","amount":1})
  elif e.kind!="boss" and randf()<0.3:drops.append({"p":e.p+Vector2(-18,0),"item":"potion","amount":1})
  if e.kind=="boss":
   boss_dead=true;quest=3
   if not "legendary" in inventory:inventory.append("legendary")
   announce("GUARDIAN FALLEN  /  Dawn of the Forsaken acquired",6);sound("bell");save_game()

func damage(amount):
 if invulnerable>0 or state!="play":return
 var actual=amount*(0.7 if armor!="" else 1.0)
 health=maxf(0,health-actual);stats.damage+=actual;invulnerable=0.65;hurt_flash=0.2;shake=7
 burst(hero,Color("c76970"),12);floating(hero-Vector2(0,55),"−"+str(int(actual)),Color("f19591"));sound("hurt")
 if health<=0:state="dead";death_count+=1

func respawn():
 gold=maxi(0,gold-20);health=100;stamina=100;hero=Vector2(480,720);bolts.clear();state="play";invulnerable=2
 build_world();save_game();announce("The covenant calls you back.  −20 gold",4)

func update_enemies(d):
 for e in enemies:
  e.cooldown-=d;e.flash=maxf(0,e.flash-d)
  var diff=hero-e.p
  var distance=diff.length()
  if e.state=="dead":e.timer=maxf(0,e.timer-d);continue
  if e.kind=="boss" and distance<530:
   stats.duration+=d;stats.distance+=distance;stats.samples+=1
   if e.hp<e.max*0.5 and e.phase==1:
    e.phase=2;announce("THE COVENANT BREAKS  /  Guardian phase II",3);burst(e.p,Color("ac86cf"),45)
  if e.state=="hurt":
   e.timer-=d
   if e.timer<=0:e.state="chase"
   continue
  if e.state=="telegraph":
   e.timer-=d
   if e.timer<=0:enemy_strike(e)
   continue
  if e.state=="recover":
   e.timer-=d
   if e.timer<=0:e.state="chase"
   continue
  if distance>({"boss":540.0,"mage":420.0}.get(e.kind,340.0)) or not line_clear(e.p,hero):
   e.state="idle"
   continue
  e.state="chase"
  var range_attack={"skeleton":60.0,"goblin":53.0,"mage":300.0,"boss":160.0}[e.kind]
  if e.kind=="boss" and e.cooldown<=0:
   e.attack=(e.attack+1)%3
   # Interpretable adaptation: repeated dodges favor delayed nova; ranged play favors bolts.
   if stats.dodges>stats.attacks*0.65:e.attack=1
   elif distance>230:e.attack=2
   e.state="telegraph";e.timer=1.05 if e.attack==1 else 0.78;e.target=hero;e.angle=diff.angle()
  elif distance<range_attack and e.cooldown<=0:
   e.state="telegraph";e.timer=0.7 if e.kind=="mage" else 0.48;e.target=hero;e.angle=diff.angle()
  else:
   var speed={"skeleton":78.0,"goblin":122.0,"mage":64.0,"boss":85.0}[e.kind]*(1.2 if e.phase==2 else 1)
   var dir=diff.normalized()
   if e.kind=="mage" and distance<180:dir=-dir
   elif distance<range_attack*0.75:dir=Vector2.ZERO
   var candidate=move_body(e.p,dir*speed*d,16 if e.kind=="boss" else 11)
   # Slide around obstacles and keep mobs separated.
   if candidate.distance_to(e.p)<0.1 and dir.length()>0:candidate=move_body(e.p,dir.orthogonal()*speed*d)
   for other in enemies:
    if other.id!=e.id and other.hp>0:
     var separation=candidate-other.p
     if separation.length()<31 and separation.length()>0.1:candidate=move_body(candidate,separation.normalized()*d*40)
   e.p=candidate

func enemy_strike(e):
 e.state="recover";e.timer=0.5;e.cooldown=1.4 if e.kind!="boss" else (1.0 if e.phase==2 else 1.8)
 if e.kind=="mage" or (e.kind=="boss" and e.attack==2):
  var count=7 if e.kind=="boss" and e.phase==2 else (5 if e.kind=="boss" else 1)
  for i in range(count):
   var angle=e.angle+(i-(count-1)/2.0)*0.22
   bolts.append({"p":e.p-Vector2(0,15),"v":Vector2.from_angle(angle)*220,"life":4.0,"damage":17.0})
 elif e.kind=="boss" and e.attack==1:
  burst(e.p,Color("bb86d9"),38)
  if hero.distance_to(e.p)<190:damage(28)
 else:
  burst(e.p+Vector2.from_angle(e.angle)*40,Color("d79c85"),12)
  var reach=160 if e.kind=="boss" else 73
  if hero.distance_to(e.p)<reach and Vector2.from_angle(e.angle).dot((hero-e.p).normalized())>0.1 and line_clear(e.p,hero):damage(24 if e.kind=="boss" else 12)

func update_projectiles(d):
 for i in range(bolts.size()-1,-1,-1):
  var b=bolts[i];b.p+=b.v*d;b.life-=d
  if hero.distance_to(b.p)<20:damage(b.damage);b.life=0
  if b.life<=0 or solid(b.p,4):burst(b.p,Color("a491d3"),6);bolts.remove_at(i)

func interact():
 if hero.distance_to(Vector2(800,720))<85:
  ui.blacksmith.open_dialogue();return
 if hero.distance_to(Vector2(650,820))<85:
  overlay="trial";net.refresh_status();sound("bell");return
 if hero.distance_to(Vector2(650,660))<100:
  if quest==0:quest=1;announce("KEEPER: The crypt stirs. Break the Guardian's oath, and bring back the dawn.",6)
  elif quest==3:quest=4;gold+=150;announce("KEEPER: Emberfall remembers you, Warden.  +150 gold",6)
  else:announce("KEEPER: Follow the eastern road. Dodge the red warnings; strike during recovery.",5)
  save_game();sound("bell");return
 if hero.distance_to(Vector2(330,740))<90:
  health=100;stamina=100;potions=maxi(potions,3);save_game();announce("COVENANT SHRINE  /  Health restored · Draughts replenished · Saved",4);sound("bell");return
 for c in chests:
  if not c.open and hero.distance_to(c.p)<75:
   c.open=true;opened.append(c.id);gold+=25;potions+=1
   var item=["fang","rune","armor"][c.id]
   if not item in inventory:inventory.append(item)
   announce("Found "+ITEMS[item].name+" · +25 gold · +1 draught",4);burst(c.p,Color("e0c482"),22);sound("loot");save_game();return
 announce("Nothing nearby. Find the keeper, shrine, or an unopened chest.",2)

func drink():
 if potions>0 and health<100:
  potions-=1;health=minf(100,health+45);burst(hero,Color("b76c75"),16);sound("loot")

func weapon_damage() -> int:
 var verified=net.equipped_damage()
 return verified if verified>0 else int(ITEMS[weapon].damage)

func weapon_name() -> String:
 return "Flame Sword #"+str(int(net.equipment.serial)) if net.equipped_damage()>0 else str(ITEMS[weapon].name)

func weapon_icon() -> String:
 return "legendary" if net.equipped_damage()>0 else str(ITEMS[weapon].icon)

func equip(id):
 if not id in inventory:return
 if ITEMS[id].slot=="weapon":
  weapon=id
  if not net.equipment.is_empty():net.unequip_item()
 elif ITEMS[id].slot=="armor":armor=id
 save_game();sound("loot")

func save_game(path=SAVE_PATH):
 if not menu_started:return
 if smoke and path==SAVE_PATH:path="user://smoke_save.json"
 var data={"version":1,"hero":[hero.x,hero.y],"health":health,"gold":gold,"potions":potions,"inventory":inventory,"weapon":weapon,"armor":armor,"killed":killed,"opened":opened,"quest":quest,"boss_dead":boss_dead}
 var file=FileAccess.open(path+".tmp",FileAccess.WRITE)
 if file:
  file.store_string(JSON.stringify(data));file.close()
  DirAccess.rename_absolute(path+".tmp",path)

func load_game(path=SAVE_PATH) -> bool:
 if not FileAccess.file_exists(path):announce("No saved covenant yet. Choose Begin Journey.",3);return false
 var data=JSON.parse_string(FileAccess.get_file_as_string(path))
 if not data is Dictionary or data.get("version",0)!=1:announce("Save could not be read.",3);return false
 for required in ["hero","health","gold","potions","inventory","weapon","killed","opened","quest","boss_dead"]:
  if not data.has(required):announce("Save is incomplete. Begin a new journey or restore a backup.",4);return false
 if not data.hero is Array or data.hero.size()!=2 or not data.inventory is Array or not data.killed is Array or not data.opened is Array:
  announce("Save contains invalid data.",3);return false
 for value in [data.hero[0],data.hero[1],data.health,data.gold,data.potions,data.quest]:
  if not (value is int or value is float):announce("Save contains invalid numbers.",3);return false
 if not data.weapon is String or not data.boss_dead is bool:announce("Save contains invalid equipment.",3);return false
 hero=Vector2(data.hero[0],data.hero[1]);health=clampf(data.health,1,100);stamina=100;gold=maxi(0,int(data.gold));potions=maxi(0,int(data.potions))
 inventory=[]
 for item in data.inventory:
  if ITEMS.has(item):inventory.append(item)
 if not "iron" in inventory:inventory.append("iron")
 weapon=data.weapon if data.weapon in inventory else "iron";armor=data.get("armor","") if data.get("armor","") in inventory else ""
 killed=data.killed;opened=data.opened;quest=int(data.quest);boss_dead=data.boss_dead
 drops.clear();bolts.clear();return true

func _input(event):
 if overlay=="blacksmith":
  if event is InputEventKey and event.pressed and event.keycode==KEY_ESCAPE:
   ui.blacksmith.close_dialogue();get_viewport().set_input_as_handled()
  return
 if event is InputEventKey and event.pressed and not event.echo:
  if get_viewport().gui_get_focus_owner() is LineEdit and event.keycode!=KEY_ESCAPE:return
  if event.keycode==KEY_ESCAPE:
   if overlay!="":overlay=""
   elif state=="play":overlay="pause";save_game()
   elif state=="menu" and menu_started:state="play"
  if state=="play":
   if event.keycode==KEY_I:overlay="" if overlay=="inventory" else "inventory"
   if event.keycode==KEY_R:overlay="" if overlay=="rgb" else "rgb";net.refresh_status()
   if overlay=="":
    if event.keycode==KEY_SPACE:dodge()
    if event.keycode==KEY_E:
     interact()
     if overlay=="blacksmith":get_viewport().set_input_as_handled()
    if event.keycode==KEY_Q:drink()
    if event.keycode==KEY_F5:save_game();announce("Covenant saved",2)

func announce(message,seconds=3.0):notice=message;notice_time=seconds
func sound(key):
 if muted or smoke:return
 audio.stream=sounds[key];audio.volume_db=-10;audio.play()
func burst(p,c,count):
 for i in range(count):particles.append({"p":p,"v":Vector2.from_angle(randf()*TAU)*randf_range(20,110),"life":randf_range(0.2,0.65),"color":c})
func floating(p,message,c):texts.append({"p":p,"text":message,"color":c,"life":0.8})

func tex(key,p,size,frame=0):
 var source=Rect2(Vector2.ZERO,textures[key].get_size())
 if key in ["player","skeleton","goblin","mage","boss","elder"]:source=Rect2(frame*40,0,40,48)
 draw_texture_rect_region(textures[key],Rect2(p,size),source)

func draw_actor(kind,p,frame,scale_factor=1.7,flash=0.0,fade=1.0):
 draw_set_transform(p,0,Vector2(1,0.35))
 draw_circle(Vector2(0,-5),18*scale_factor,Color(0.01,0.03,0.05,0.5*fade))
 draw_set_transform(Vector2.ZERO)
 var color=Color(2,1.8,1.5,fade) if flash>0 else Color(1,1,1,fade)
 draw_texture_rect_region(textures[kind],Rect2(p-Vector2(20,43)*scale_factor,Vector2(40,48)*scale_factor),Rect2(frame*40,0,40,48),color)

func _draw():
 if textures.is_empty():return
 var bounds=Rect2(camera.get_screen_center_position()-Vector2(700,420),Vector2(1400,840))
 for y in range(maxi(0,int(bounds.position.y/48)),mini(30,int(bounds.end.y/48)+1)):
  for x in range(maxi(0,int(bounds.position.x/48)),mini(50,int(bounds.end.x/48)+1)):
   var pos=Vector2(x*48,y*48)
   var key="earth" if x<21 else "floor"
   if x<21 and (y in [14,15,16] or (x in [10,11] and y>9 and y<22)):key="path"
   if walls.has(Vector2i(x,y)):key="wall" if x>=21 else "earth"
   draw_texture_rect_region(textures[key],Rect2(pos,Vector2(48,48)),Rect2(((x*7+y*13)%6)*24,0,24,24))
   if walls.has(Vector2i(x,y)):
    if x>=21:
     draw_rect(Rect2(pos,Vector2(48,48)),Color(0.02,0.03,0.06,0.35))
     if not walls.has(Vector2i(x,y+1)):
      draw_rect(Rect2(pos+Vector2(0,45),Vector2(48,5)),Color("79818a"));draw_rect(Rect2(pos+Vector2(0,50),Vector2(48,16)),Color(0,0,0,0.35))
    else:draw_rect(Rect2(pos,Vector2(48,48)),Color(0.01,0.03,0.04,0.45))
 for y in range(13,17):
  for x in range(35,44):
   if not walls.has(Vector2i(x,y)):tex("carpet",Vector2(x*48,y*48),Vector2(48,48))
 # Inlaid rune circle in the boss arena.
 var center=Vector2(2070,740)
 draw_arc(center,190,0,TAU,80,Color("47545b"),3)
 draw_arc(center,174,0,TAU,80,Color("35434e"),1)
 for i in range(12):
  var p=center+Vector2.from_angle(i*TAU/12)*182
  draw_line(p-Vector2(4,6),p+Vector2(4,6),Color("6f7485"),2)
 # The Oath forge is a visible, interactive village portal.
 var forge=Vector2(650,820)
 draw_texture_rect(textures.glow,Rect2(forge-Vector2(90,115),Vector2(180,180)),false,Color(0.7,0.5,1,0.6))
 draw_arc(forge-Vector2(0,22),35,0,TAU,40,Color("b49ad1"),3)
 tex("legendary",forge-Vector2(24,58+sin(t*3)*4),Vector2(48,48))
 draw_string(ThemeDB.fallback_font,forge+Vector2(-83,42),"OATH TRIAL [E]",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("dfc58d"))
 # Road edge lamps and passage lettering use world coordinates.
 draw_string(ThemeDB.fallback_font,Vector2(885,640),"THE HOLLOW →",HORIZONTAL_ALIGNMENT_LEFT,-1,17,Color("b5ac8a"))
 for e in enemies:
  if e.state=="telegraph":
   var col=Color(0.86,0.28,0.33,0.24+sin(t*18)*0.07)
   if e.kind=="boss" and e.attack==1:
    draw_circle(e.p,190,col);draw_arc(e.p,190,0,TAU,64,Color("e89da4"),3)
   elif e.kind=="mage" or (e.kind=="boss" and e.attack==2):
    draw_line(e.p,e.p+Vector2.from_angle(e.angle)*340,col,22)
   else:
    var points=PackedVector2Array([e.p])
    for j in range(17):points.append(e.p+Vector2.from_angle(e.angle-0.95+j*1.9/16)*(160 if e.kind=="boss" else 78))
    draw_colored_polygon(points,col)
 var objects: Array=[]
 for p in props:objects.append({"type":"prop","data":p,"y":p.p.y})
 for c in chests:objects.append({"type":"chest","data":c,"y":c.p.y})
 for e in enemies:objects.append({"type":"enemy","data":e,"y":e.p.y})
 objects.append({"type":"hero","y":hero.y})
 objects.sort_custom(func(a,b):return a.y<b.y)
 for obj in objects:
  match obj.type:
   "hero":
    if invulnerable<=0 or int(t*18)%2==0:
     draw_actor("player",hero,int(t*(11 if walk else 3))%4,1.7,hurt_flash)
   "enemy":
    var e=obj.data
    if e.state=="dead" and e.timer<=0:continue
    draw_actor(e.kind,e.p,int(t*(8 if e.state=="chase" else 3))%4,2.8 if e.kind=="boss" else 1.7,e.flash,e.timer/0.7 if e.state=="dead" else 1.0)
    if e.hp<e.max and e.hp>0 and e.kind!="boss":
     draw_rect(Rect2(e.p-Vector2(25,83),Vector2(50,4)),Color("232d36"));draw_rect(Rect2(e.p-Vector2(25,83),Vector2(50*e.hp/e.max,4)),Color("a85f68"))
   "prop":
    var p=obj.data
    if p.kind in ["elder","blacksmith"]:draw_actor(p.kind,p.p,int(t*2)%4,p.scale)
    else:
     var size=textures[p.kind].get_size()*p.scale
     tex(p.kind,p.p-Vector2(size.x/2,size.y),size)
   "chest":
    var c=obj.data
    tex("chest",c.p-Vector2(32,54),Vector2(64,64))
    if c.open:draw_line(c.p-Vector2(22,27),c.p+Vector2(22,-27),Color("171c25"),7)
 if hero.distance_to(Vector2(800,720))<85:
  draw_string(ThemeDB.fallback_font,Vector2(748,620),"BRAM  /  E — Talk",HORIZONTAL_ALIGNMENT_LEFT,-1,15,Color("dfc58d"))
 if hero.distance_to(Vector2(650,660))<110:
  draw_string(ThemeDB.fallback_font,Vector2(610,570),"KEEPER  [E]",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("dfc58d"))
 if hero.distance_to(Vector2(330,740))<100:
  draw_string(ThemeDB.fallback_font,Vector2(270,620),"REST  [E]",HORIZONTAL_ALIGNMENT_LEFT,-1,14,Color("9edbd0"))
 for drop in drops:
  var p=drop.p+Vector2(0,sin(t*4+drop.p.x)*3-15)
  draw_circle(p,16,Color(0.9,0.7,0.4,0.12));tex("gold" if drop.item=="gold" else ITEMS[drop.item].icon,p-Vector2(16,16),Vector2(32,32))
 for b in bolts:
  draw_circle(b.p,12,Color(0.58,0.42,0.8,0.2));draw_circle(b.p,6,Color("b9a1eb"));draw_circle(b.p,2,Color("f3e6f5"))
 if slash_time>0:
  var angle=facing.angle();var progress=1-slash_time/0.19
  draw_arc(hero,64,angle-1.3+progress,angle+0.8+progress,20,Color(0.9,0.91,0.77,slash_time/0.19),7)
  draw_arc(hero,75,angle-1.3+progress,angle+0.8+progress,20,Color(0.55,0.85,0.8,slash_time/0.3),3)
 for p in particles:draw_circle(p.p,2,Color(p.color,p.life*1.5))
 for p in props:
  if p.kind in ["fire","torch","shrine"]:
   var size=210 if p.kind=="fire" else 150
   draw_texture_rect(textures.glow,Rect2(p.p-Vector2(size/2.0,size/2.0+35),Vector2(size,size)),false,Color(1,0.8,0.5,0.65+sin(t*6+p.p.x)*0.1))
 for tx in texts:draw_string(ThemeDB.fallback_font,tx.p,tx.text,HORIZONTAL_ALIGNMENT_CENTER,-1,20,Color(tx.color,tx.life*1.5))
 # Quiet moving motes create atmosphere without obscuring action.
 for i in range(28):
  var p=Vector2(fmod(i*191+t*7,WORLD.x),fmod(i*107-t*10+WORLD.y,WORLD.y))
  draw_circle(p,1.3,Color(0.8,0.7,0.45,0.25+sin(t+i)*0.15))

func run_smoke():
 start(false)
 var failures: Array=[]
 if solid(hero):failures.append("spawn collision")
 var reached=reachable_cells(Vector2i(10,15))
 for c in chests:
  if not reached.has(Vector2i(floori(c.p.x/TILE),floori(c.p.y/TILE))):failures.append("unreachable chest")
 if not reached.has(Vector2i(43,15)):failures.append("unreachable boss arena")
 hero=Vector2(650,660);interact()
 if quest!=1:failures.append("keeper quest")
 hero=chests[0].p;interact()
 if not chests[0].open or not "fang" in inventory:failures.append("chest loot")
 var loot_gold=gold;interact()
 if gold!=loot_gold:failures.append("duplicate chest loot")
 hero=Vector2(330,740);health=40;potions=0;interact()
 if health!=100 or potions!=3:failures.append("shrine")
 hero=Vector2(480,720)
 var before=hero
 hero=move_body(hero,Vector2(100,0))
 if hero.x<=before.x:failures.append("movement")
 var wall_stop=move_body(Vector2(1100,720),Vector2(0,-900))
 if solid(wall_stop):failures.append("wall tunneling")
 var target=enemies[0]
 hero=target.p-Vector2(55,0);facing=Vector2.RIGHT;attack()
 if target.hp>=target.max:failures.append("sword damage")
 stamina=100;dodge()
 if invulnerable<=0:failures.append("dodge")
 invulnerable=0;damage(10)
 if health>=100:failures.append("damage")
 var mage=enemies[3]
 mage.state="telegraph";mage.timer=0;mage.angle=0
 enemy_strike(mage)
 if bolts.is_empty():failures.append("mage projectile")
 bolts.clear()
 for e in enemies:
  if e.kind in ["skeleton","goblin"]:
   hero=e.p+Vector2(0,30);e.angle=PI/2;invulnerable=0
   var old_health=health
   enemy_strike(e)
   if health>=old_health:failures.append(e.kind+" melee")
   health=100
 var boss=enemies[-1]
 boss.hp=300;hero=boss.p+Vector2(100,0);update_enemies(0.1)
 if boss.phase!=2:failures.append("boss phase")
 hit_enemy(boss,1000)
 if not boss_dead or not "legendary" in inventory:failures.append("boss loot")
 equip("legendary")
 if weapon!="legendary":failures.append("equip")
 save_game("user://test_save.json");gold=99999;load_game("user://test_save.json")
 if gold==99999:failures.append("save load")
 var broken=FileAccess.open("user://test_corrupt.json",FileAccess.WRITE)
 broken.store_string('{"version":1}');broken.close()
 if load_game("user://test_corrupt.json"):failures.append("corrupt save acceptance")
 health=1;invulnerable=0;damage(100)
 if state!="dead":failures.append("death")
 respawn()
 if state!="play" or health!=100:failures.append("respawn")
 net.equipment={"damage":52,"serial":1};net.lease_deadline=Time.get_ticks_msec()+2000
 if weapon_damage()!=52:failures.append("managed weapon stats")
 net.lease_deadline=0
 if weapon_damage()!=int(ITEMS[weapon].damage):failures.append("expired ownership lease")
 net.clear_use();overlay=""
 print("RUNEFORGE_SMOKE ","PASS: connectivity quests chests shrine movement collision melee ranged dodge boss loot equipment save/load death respawn" if failures.is_empty() else str(failures))
 get_tree().quit(0 if failures.is_empty() else 1)

func capture():
 await get_tree().create_timer(1).timeout
 var output=OS.get_environment("RUNEFORGE_CAPTURE")
 if output=="":output="user://runeforge.png"
 get_viewport().get_texture().get_image().save_png(output)
 print("CAPTURE ",output)
 if "--capture-exit" in OS.get_cmdline_user_args():get_tree().quit()

func run_network_smoke():
 start(false)
 net.token=""
 net.connect_profile()
 await wait_network()
 if not net.online:
  print("NETWORK_SMOKE_FAIL: ",net.status);get_tree().quit(1);return
 net.begin_trial()
 await wait_network()
 for i in range(60):
  if net.trial.get("status","")!="active":break
  var action="guard" if net.trial.intent=="heavy" else ("rest" if net.trial.stamina<24 else "attack")
  await get_tree().create_timer(0.4).timeout
  net.trial_action(action)
  await wait_network()
 if net.trial.get("status","")!="won":
  print("NETWORK_SMOKE_FAIL: trial ",net.message);get_tree().quit(1);return
 net.claim_reward()
 await wait_network()
 var original=net.cloud_items
 net.claim_reward()
 await wait_network()
 if net.cloud_items!=original or original<1:
  print("NETWORK_SMOKE_FAIL: reward replay");get_tree().quit(1);return
 print("RUNEFORGE_NETWORK_SMOKE PASS: authenticated Godot HTTP -> PostgreSQL trial -> single reward -> idempotent replay")
 get_tree().quit()

func wait_network():
 var timeout=0.0
 while net.busy and timeout<15:
  await get_tree().create_timer(0.05).timeout
  timeout+=0.05

func save_settings():
 var settings=ConfigFile.new()
 settings.set_value("game","muted",muted)
 settings.set_value("game","screen_shake",screen_shake)
 settings.save("user://settings.cfg")

func reachable_cells(origin: Vector2i) -> Dictionary:
 var visited={origin:true}
 var frontier: Array=[origin]
 var index=0
 while index<frontier.size():
  var cell=frontier[index];index+=1
  for offset in [Vector2i.LEFT,Vector2i.RIGHT,Vector2i.UP,Vector2i.DOWN]:
   var candidate=cell+offset
   if candidate.x<0 or candidate.x>=50 or candidate.y<0 or candidate.y>=30:continue
   if not walls.has(candidate) and not visited.has(candidate):
    visited[candidate]=true;frontier.append(candidate)
 return visited

func run_managed_check():
 start(false);overlay="trial"
 net.switch_profile("A")
 await wait_network()
 if not net.online:managed_failure("backend connection");return
 if net.trial.is_empty() or net.trial.get("status")=="lost":net.begin_trial();await wait_network()
 for turn in range(60):
  if net.trial.get("status")!="active":break
  await get_tree().create_timer(0.45).timeout
  await wait_network()
  net.trial_action("guard" if net.trial.intent=="heavy" else ("rest" if net.trial.stamina<24 else "attack"))
  await wait_network()
 if net.trial.get("status")!="won":managed_failure("server trial victory");return
 net.refresh_status();await wait_network()
 if net.items.is_empty():managed_failure("automatic award");return
 var serial=int(net.items[0].serial)
 var receiver_id=net.profiles.B.id
 # Reruns inspect the same instance; they do not request another trial/reward.
 var already_sent=net.items[0].owner_id==receiver_id
 if not already_sent:
  if not await wait_managed_owned(serial):managed_failure("award wallet settlement");return
  net.equip_item(serial);await wait_network()
  if weapon_damage()!=52:managed_failure("sender equip stats");return
  # Verify the real campaign attack consumes the server weapon stat.
  var target=enemies[0];target.p=Vector2(550,720);target.hp=1000;target.max=1000;hero=Vector2(500,720);facing=Vector2.RIGHT;roll_time=0;stamina=100
  attack()
  if target.hp!=948:managed_failure("campaign sword damage");return
  overlay="rgb";net.selected_serial=serial
  await managed_capture("managed-sender.png")
  await wait_network();net.transfer_item(serial,receiver_id);await wait_network()
  if net.equipped_damage()!=0 or weapon_damage()==52:managed_failure("sender reservation revokes stats");return
  await wait_network();net.switch_profile("B");await wait_network()
 else:net.switch_profile("B");await wait_network()
 if not await wait_managed_owned(serial):managed_failure("recipient wallet settlement");return
 net.equip_item(serial);await wait_network()
 if weapon_damage()!=52:managed_failure("recipient equip stats");return
 overlay="rgb";net.selected_serial=serial
 await managed_capture("managed-recipient.png")
 var proof={"serial":serial,"asset_id":net.equipment.asset_id,"damage":weapon_damage(),"checks":["server_trial","real_wallet_delivery","sender_equipped","campaign_attack_52","reservation_revokes","recipient_equipped"]}
 var evidence_path=OS.get_environment("RUNEFORGE_EVIDENCE_DIR")
 if evidence_path!="":
  var out=FileAccess.open(evidence_path+"/managed-godot.json",FileAccess.WRITE)
  out.store_string(JSON.stringify(proof,"  "));out.close()
 print("RUNEFORGE_MANAGED_GAME PASS: server victory, real UDA, campaign damage 52, transfer, recipient damage 52")
 get_tree().quit()

func wait_managed_owned(serial):
 for attempt in range(240):
  await wait_network();net.refresh_status();await wait_network()
  for item in net.items:
   if int(item.serial)==serial and item.can_equip:return true
  await get_tree().create_timer(1).timeout
 return false

func managed_capture(filename):
 var path=OS.get_environment("RUNEFORGE_EVIDENCE_DIR")
 if path=="" or DisplayServer.get_name()=="headless":return
 await get_tree().process_frame
 await RenderingServer.frame_post_draw
 get_viewport().get_texture().get_image().save_png(path+"/"+filename)

func managed_failure(reason):
 print("RUNEFORGE_MANAGED_GAME FAIL: ",reason," / ",net.message)
 get_tree().quit(1)

func run_outage_check():
 start(false);overlay="rgb";net.switch_profile("B");await wait_network()
 if net.items.is_empty():managed_failure("no real test sword for outage check");return
 var serial=int(net.items[0].serial)
 if not await wait_managed_owned(serial):managed_failure("outage precondition");return
 net.equip_item(serial);await wait_network()
 if weapon_damage()!=52:managed_failure("outage equip precondition");return
 print("OUTAGE_READY")
 await get_tree().create_timer(12).timeout
 if net.online or net.equipped_damage()!=0 or weapon_damage()!=22:
  managed_failure("offline lease revocation");return
 await managed_capture("backend-offline.png")
 print("RUNEFORGE_BACKEND_OUTAGE PASS: real equipped sword revoked; local campaign weapon restored")
 get_tree().quit()

func run_sword4_check():
 start(false);overlay="rgb";net.switch_profile("A");await wait_network()
 if net.profile.get("id")!="e2bc20f0-4fc2-49f4-8363-799560e64378" or net.profile.get("is_test",true):
  managed_failure("ordinary profile A identity");return
 if not await wait_managed_owned(4):managed_failure("ordinary A sword 4 ownership");return
 net.equip_item(4);await wait_network();net.selected_serial=4
 if net.equipment.get("asset_id")!="rgb:HMuDmE2i-aknsETo-4mmIZrS-hrK12HK-Qn_Yi1F-kY5jYa8" or weapon_damage()!=52:
  managed_failure("same sword 4 equipped with damage 52");return
 if net.players.size()!=1 or net.players[0].id!=net.profiles.B.id:
  managed_failure("normal recipient list must contain ordinary B only");return
 # Use the actual settled return operation: no transfer or fixture state is fabricated.
 var completed={}
 for operation in net.history:
  if int(operation.serial)==4 and operation.recipient_id==net.profile.id and operation.state=="settled":completed=operation;break
 if completed.is_empty():managed_failure("settled return history");return
 net.message="Transfer is running automatically."
 net.message_operation_id=completed.id
 net.refresh_status();await wait_network()
 if not net.message.begins_with("Transfer complete.") or "running" in net.message:
  managed_failure("stale transfer message");return
 await managed_capture("sword4-ordinary-A.png")
 var result={"serial":4,"profile_id":net.profile.id,"profile_name":net.profile.name,"is_test":net.profile.is_test,"asset_id":net.equipment.asset_id,"damage":weapon_damage(),"recipient_ids":[net.players[0].id],"message":net.message}
 var output=OS.get_environment("RUNEFORGE_EVIDENCE_DIR")
 if output!="":
  var file=FileAccess.open(output+"/sword4-godot.json",FileAccess.WRITE);file.store_string(JSON.stringify(result,"  "));file.close()
 net.switch_profile("B");await wait_network()
 if net.message!="" or net.message_operation_id!="":managed_failure("profile switch clears messages");return
 net.switch_profile("A");await wait_network()
 print("SWORD4_GODOT_PASS: ordinary A, same asset, 52 damage, no test recipients, settled status")
 get_tree().quit()

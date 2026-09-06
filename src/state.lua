local State = {}
local function tableAt(value) return type(value)=="table" and value or {} end
local function number(value) value=tonumber(value); return value or 0 end
local function percent(current, maximum)
  current,maximum=number(current),number(maximum)
  if maximum<=0 then return 0 end
  local value=current/maximum*100
  if value<0 then value=0 elseif value>100 then value=100 end
  return math.floor(value*10+0.5)/10
end
local function resource(vitals,key)
  local current,maximum=number(vitals[key]),number(vitals[key.."_max"])
  return {current=current,maximum=maximum,percent=percent(current,maximum),visible=maximum>0}
end
function State.normalize(source,command_snapshot)
  source=tableAt(source); local char=tableAt(source.Char); local status=tableAt(char.Status); local vitals=tableAt(char.Vitals)
  local roomRoot=tableAt(source.Room); local room=tableAt(roomRoot.Info)
  local parsed=tableAt(command_snapshot); local info=tableAt(parsed.info); local religion=tableAt(parsed.religion); local runes=tableAt(parsed.runes); local parsedCharacter=tableAt(info.character); local stat=tableAt(parsed.stat); local inventory=tableAt(parsed.inventory); local skills=tableAt(parsed.skills)
  local name=tostring(status.name or parsedCharacter.name or ""); local surname=tostring(status.surname or parsedCharacter.surname or "")
  local full=(name.." "..surname):match("^%s*(.-)%s*$"); if full=="" then full=parsedCharacter.full_name or "Unknown" end
  local characterClass=tostring(status.class or parsedCharacter.class or "Unknown"):match("^%s*(.-)%s*$")
  local characterRace=tostring(status.race or parsedCharacter.race or "Unknown"):match("^%s*(.-)%s*$")
  local psi=resource(vitals,"psi"); local web=resource(vitals,"web")
  local classKey=characterClass:lower(); local raceKey=characterRace:lower()
  if classKey=="psion" or classKey=="psycian" then psi.visible=true end
  if raceKey=="arachnian" then web.visible=true end
  return {
    character={name=name,surname=surname,full_name=full,race=characterRace,class=characterClass,alignment=status.alignment or parsedCharacter.alignment or "Unknown",physical=tableAt(info.physical),religion=status.religion or religion.rank,deity=status.deity or religion.deity,favors=tonumber(status.favors) or religion.favors,religious_balance=status.religious_balance or religion.balance,religious_alignment=status.religious_alignment or religion.alignment},
    attributes=tableAt(info.attributes),
    combat={body_armor=stat.body_armor,or_rating=stat.or_rating,dr=stat.dr,move=stat.move,damage_bonus=stat.damage_bonus,stance=stat.stance,area_position=stat.area_position,novice_protected=stat.novice_protected},
    equipment={items=tableAt(stat.equipment)},
    inventory={items=tableAt(inventory.items),total_weight=inventory.total_weight},
    skills={items=tableAt(skills.items)},
    runes={items=tableAt(runes.items)},
    vitals={hp=resource(vitals,"hp"),fatigue=resource(vitals,"fatigue"),psi=psi,web=web,carry=resource(vitals,"carry"),gold=number(vitals.gold),silver=number(vitals.silver),position=number(vitals.position),roundtime=number(vitals.roundtime),weapon_readied=vitals.weapon_readied==true,shield_readied=vitals.shield_readied==true},
    room={name=room.name or "Unknown room",num=room.num,area=room.area,environment=room.environment or "Unknown",exits=tableAt(room.exits),flags=tableAt(room.flags),players=tableAt(roomRoot.Players),wrong_direction=roomRoot.WrongDir}
  }
end
return State

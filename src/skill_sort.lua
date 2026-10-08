local SkillSort={}

local defaults={primary="level",direction="desc",secondary="uses",secondary_direction="asc"}
local keys={level=true,uses=true,name=true,number=true,ready=true,category=true}
local directions={asc=true,desc=true}
local fields={"primary","direction","secondary","secondary_direction"}
local function valid(field,value)
  if type(value)~="string" then return false end
  if field=="primary" then return keys[value]==true end
  if field=="secondary" then return value=="none" or keys[value]==true end
  return directions[value]==true
end
function SkillSort.normalize(config)
  local result={}
  for _,field in ipairs(fields) do
    local value=type(config)=="table" and rawget(config,field) or nil
    result[field]=valid(field,value) and value or defaults[field]
  end
  return result
end
function SkillSort.validate(config)
  if type(config)~="table" then return nil,"skill sort config must be a table" end
  -- Only these data fields are accepted; no coercion or inherited settings.
  for field in next,config do
    if defaults[field]==nil then return nil,"unknown skill sort config key" end
  end
  for _,field in ipairs(fields) do
    local value=rawget(config,field)
    if value~=nil and not valid(field,value) then return nil,"invalid skill sort "..field end
  end
  return SkillSort.normalize(config)
end

-- Authoritative game identifiers, never possessed skills or display ordinals.
local catalog={
  "Brawling","Sharp Weapons","Blunt Weapons","Piercing Weapons","Thrown Weapons","Missile Weapons",
  "Shield Use","Quickdraw","Dodging","Focus Force","Berserk Attack","Parry Blows","Bargaining",
  "Identify Gems/Minerals","Climbing","Detect Traps","Remove Traps","Skinning","Disguise","Pick Locks",
  "Riding","Hiding","Swimming","Alchemy","Backstab","Martial Arts","Picking Pockets","Shoplifting",
  "Stealth","Poisoning","Identify Magick","Identify Weapon Quality","Play Instruments","Armor Smithing",
  "Weapon Smithing","Singing","Fletching","Tracking","Disarming","Psionics","Channeling","First Aid",
  "Body Building","Turn Undead","Draining","Biting","Clawing","Webbing","Breath Weapon",
  "Identify Armor Quality","Linguistics","Herbalism","Healing","Spellcasting","Conjuration","Delving","Stinging",
}
local function cleanName(value)
  if type(value)~="string" then return "" end
  return (value:gsub("\27%[[0-?]*[ -/]*[@-~]",""):gsub("\r","")
    :match("^%s*(.-)%s*$"):gsub("^[%*%s]+",""):gsub("%s+"," "):lower())
end
local ids={}; for id,value in ipairs(catalog) do ids[cleanName(value)]=id end
-- Legacy full names and labels keep their original game IDs after renames.
local aliases={sharps=2,blunts=3,piercing=4,thrown=5,missiles=6,
  ["pole weapons"]=4,poles=4,["throw weapons"]=5,throws=5,["shield parry"]=7}
local combatIds={
  [1]=true,[2]=true,[3]=true,[4]=true,[5]=true,[6]=true,[7]=true,[8]=true,[9]=true,[10]=true,[11]=true,[12]=true,
  [25]=true,[26]=true,[30]=true,[39]=true,[40]=true,[41]=true,[42]=true,[43]=true,[44]=true,[45]=true,[46]=true,
  [47]=true,[48]=true,[49]=true,[53]=true,[54]=true,[55]=true,[57]=true,
}
function SkillSort.skillId(value)
  if type(value)~="string" or #value>2048 then return nil end
  local cleaned=cleanName(value)
  return ids[cleaned] or aliases[cleaned]
end
function SkillSort.canonicalName(value)
  local id=SkillSort.skillId(value)
  return id and catalog[id] or nil
end
function SkillSort.combatCategory(skill)
  local value=type(skill)=="table" and skill.name or skill
  return combatIds[SkillSort.skillId(value)] and "combat" or "utility"
end
local function numeric(value)
  local number=(type(value)=="number" or type(value)=="string") and tonumber(value) or nil
  if not number or number~=number or number==math.huge or number==-math.huge then return 0 end
  return number
end
local function compare(a,b,key,direction)
  local av,bv=a[key],b[key]
  if av==bv then return 0 end
  -- Unknown identifiers stay last even when number order is descending.
  if key=="number" then
    if av==nil then return 1 end
    if bv==nil then return -1 end
  end
  local before=av<bv
  if direction=="desc" then before=not before end
  return before and -1 or 1
end
function SkillSort.sorted(items,config)
  local preferences=SkillSort.normalize(config)
  local decorated={}
  for index,item in ipairs(type(items)=="table" and items or {}) do
    local skill=type(item)=="table" and item or {}
    local id=SkillSort.skillId(skill.name)
    decorated[index]={item=item,index=index,name=id and catalog[id]:lower() or cleanName(skill.name),number=id,
      level=numeric(skill.level),uses=numeric(skill.remain),ready=skill.remain==0 and 0 or 1,
      category=SkillSort.combatCategory(skill)=="combat" and 0 or 1}
  end
  table.sort(decorated,function(a,b)
    local order=compare(a,b,preferences.primary,preferences.direction)
    if order==0 and preferences.secondary~="none" then
      order=compare(a,b,preferences.secondary,preferences.secondary_direction)
    end
    if order==0 then order=compare(a,b,"name","asc") end
    if order==0 then order=compare(a,b,"number","asc") end
    if order==0 then return a.index<b.index end
    return order<0
  end)
  local result={}; for index,entry in ipairs(decorated) do result[index]=entry.item end
  return result
end
return SkillSort

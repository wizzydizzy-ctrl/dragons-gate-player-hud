local SkillSort=require("skill_sort")
local Display=require("skill_display")
local fields={"primary","direction","secondary","secondary_direction"}
local defaults={primary="level",direction="desc",secondary="uses",secondary_direction="asc"}
local keys={"level","uses","name","number","ready","category"}
local secondaryKeys={"level","uses","name","number","ready","category","none"}
local function configEq(actual,expected)
  local count=0; for _ in pairs(actual) do count=count+1 end; eq(count,4)
  for _,field in ipairs(fields) do eq(actual[field],expected[field]) end
end
local function sequence(actual,expected)
  eq(#actual,#expected)
  for index,item in ipairs(expected) do eq(actual[index],item) end
end

test("skill sort defaults and normalization are fresh and ignore invalid fields",function()
  local first=SkillSort.normalize(); local second=SkillSort.normalize({})
  configEq(first,defaults); configEq(second,defaults); assert(first~=second)
  first.primary="name"; configEq(SkillSort.normalize(),defaults)
  for _,config in ipairs({false,true,1,"level",function() end}) do configEq(SkillSort.normalize(config),defaults) end
  local config={primary="number",direction=false,secondary="none",secondary_direction="down",extra="ignored"}
  local normalized=SkillSort.normalize(config)
  configEq(normalized,{primary="number",direction="desc",secondary="none",secondary_direction="asc"})
  eq(config.direction,false); eq(config.secondary_direction,"down"); eq(config.extra,"ignored")
  local invalid={primary="none",direction="DESC",secondary=true,secondary_direction=1}
  configEq(SkillSort.normalize(invalid),defaults)
end)

test("skill sort strict validation rejects bad types keys and values and accepts omitted fields",function()
  local normalized=assert(SkillSort.validate({})); configEq(normalized,defaults)
  local config={primary="name",direction="asc"}
  normalized=assert(SkillSort.validate(config)); assert(normalized~=config)
  configEq(normalized,{primary="name",direction="asc",secondary="uses",secondary_direction="asc"})
  eq(config.secondary,nil); normalized.primary="ready"; eq(config.primary,"name")
  local invalid={false,true,1,"level",function() end,{unknown="level"},{[1]="level"},{[false]="level"},
    {primary="none"},{primary="LEVEL"},{secondary=""},{direction="up"},{secondary_direction="down"}}
  for _,field in ipairs(fields) do
    for _,value in ipairs({false,true,0,{},function() end}) do invalid[#invalid+1]={[field]=value} end
  end
  for _,configValue in ipairs(invalid) do
    local result,err=SkillSort.validate(configValue); eq(result,nil); eq(type(err),"string"); assert(#err>0)
  end
  local result,err=SkillSort.validate(nil); eq(result,nil); eq(type(err),"string")
end)

test("skill sort config validation and normalization only read explicit data fields",function()
  local config=setmetatable({primary="name"},{__index=function() error("inherited config executed") end,
    __pairs=function() error("config iterator executed") end})
  configEq(SkillSort.normalize(config),{primary="name",direction="desc",secondary="uses",secondary_direction="asc"})
  configEq(assert(SkillSort.validate(config)),SkillSort.normalize(config))
end)

test("skill sort owns all 57 catalog identifiers and normalizes ANSI stars spacing and abbreviations",function()
  local catalog={
    "Brawling","Sharp Weapons","Blunt Weapons","Pole Weapons","Throw Weapons","Missile Weapons",
    "Shield Parry","Quickdraw","Dodging","Focus Force","Berserk Attack","Parry Blows","Bargaining",
    "Identify Gems/Minerals","Climbing","Detect Traps","Remove Traps","Skinning","Disguise","Pick Locks",
    "Riding","Hiding","Swimming","Alchemy","Backstab","Martial Arts","Picking Pockets","Shoplifting",
    "Stealth","Poisoning","Identify Magick","Identify Weapon Quality","Play Instruments","Armor Smithing",
    "Weapon Smithing","Singing","Fletching","Tracking","Disarming","Psionics","Channeling","First Aid",
    "Body Building","Turn Undead","Draining","Biting","Clawing","Webbing","Breath Weapon",
    "Identify Armor Quality","Linguistics","Herbalism","Healing","Spellcasting","Conjuration","Delving","Stinging",
  }
  local combat={[1]=true,[2]=true,[3]=true,[4]=true,[5]=true,[6]=true,[7]=true,[8]=true,[9]=true,[10]=true,[11]=true,[12]=true,
    [25]=true,[26]=true,[30]=true,[39]=true,[40]=true,[41]=true,[42]=true,[43]=true,[44]=true,[45]=true,[46]=true,
    [47]=true,[48]=true,[49]=true,[53]=true,[54]=true,[55]=true,[57]=true}
  eq(#catalog,57); eq(Display.skillId,SkillSort.skillId); eq(Display.combatCategory,SkillSort.combatCategory)
  for id,value in ipairs(catalog) do
    local messy="\27[32m \t ** "..value:upper():gsub(" "," \t ").."  \27[0m\r"
    eq(SkillSort.skillId(value),id); eq(SkillSort.skillId(messy),id)
    eq(SkillSort.skillId(Display.displayName(value)),id)
    local category=combat[id] and "combat" or "utility"
    eq(SkillSort.combatCategory(messy),category)
    eq(SkillSort.combatCategory({name=messy,remain=0}),category)
    eq(Display.category({name=messy,remain=0}),"ready")
  end
  for _,value in ipairs({false,true,42,{},"Future Art","Future Sharp Weapons","","Sharpsmithing",string.rep("x",2049)}) do
    eq(SkillSort.skillId(value),nil); eq(SkillSort.combatCategory(value),"utility")
  end
  eq(SkillSort.skillId(nil),nil); eq(SkillSort.combatCategory(nil),"utility")
  for id,label in ipairs({"Sharps","Blunts","Poles","Throws","Missiles"}) do
    eq(SkillSort.skillId("\27[31m ** "..label:upper().." \27[0m"),id+1)
  end
end)



-- Synthetic fixture pins exactly the supplied TRAIN catalog pairs. IDs are
-- explicit game identifiers, not positions in this possessed-skill subset.
local latestTrainCatalog={
  {id=16,name="Detect Traps"},
  {id=33,name="Play Instruments"},
  {id=50,name="Identify Armor Quality"},
  {id=40,name="Psionics"},
  {id=42,name="First Aid"},
  {id=22,name="Hiding"},
  {id=3,name="Blunt Weapons",aliases={"Blunts"}},
  {id=1,name="Brawling"},
  {id=2,name="Sharp Weapons",aliases={"Sharps"}},
  {id=4,name="Piercing Weapons",aliases={"Pole Weapons","Poles","Piercing"}},
  {id=5,name="Thrown Weapons",aliases={"Throw Weapons","Throws","Thrown"}},
  {id=6,name="Missile Weapons",aliases={"Missiles"}},
  {id=7,name="Shield Use",aliases={"Shield Parry"}},
  {id=8,name="Quickdraw"},
  {id=13,name="Bargaining"},
  {id=54,name="Spellcasting"},
  {id=39,name="Disarming"},
  {id=29,name="Stealth"},
  {id=23,name="Swimming"},
  {id=14,name="Identify Gems/Minerals"},
  {id=31,name="Identify Magick"},
  {id=32,name="Identify Weapon Quality"},
}

test("latest TRAIN catalog pins every supplied ID across current names and legacy aliases",function()
  eq(#latestTrainCatalog,22); local seen={}
  for _,entry in ipairs(latestTrainCatalog) do
    assert(not seen[entry.id]); seen[entry.id]=true
    local names={entry.name}
    for _,alias in ipairs(entry.aliases or {}) do names[#names+1]=alias end
    for _,value in ipairs(names) do
      local messy="\27[32m ** "..value:upper():gsub(" "," \t ").." \27[0m\r"
      eq(SkillSort.skillId(value),entry.id); eq(SkillSort.skillId(messy),entry.id)
      eq(SkillSort.canonicalName(value),entry.name); eq(SkillSort.canonicalName(messy),entry.name)
      eq(SkillSort.skillId(Display.displayName(value)),entry.id)
    end
  end
end)

test("latest TRAIN number sorting preserves exactly the supplied possessed rows and game IDs",function()
  local numberOrder={8,9,7,10,11,12,13,14,15,20,1,6,19,18,21,22,2,17,4,5,3,16}
  for variant=0,3 do
    local items,names={},{}
    for index,entry in ipairs(latestTrainCatalog) do
      local value=entry.aliases and entry.aliases[variant] or entry.name
      items[index]={name=value,level=3,remain=0}; names[index]=value
    end
    for _,direction in ipairs({"asc","desc"}) do
      local expected={}
      for index=1,#numberOrder do
        local position=direction=="asc" and index or #numberOrder-index+1
        expected[index]=items[numberOrder[position]]
      end
      local sorted=SkillSort.sorted(items,{primary="number",direction=direction,secondary="none"})
      sequence(sorted,expected); eq(#sorted,22)
      for index,item in ipairs(items) do
        eq(item.name,names[index]); eq(item.level,3); eq(item.remain,0)
        eq(SkillSort.skillId(item.name),latestTrainCatalog[index].id)
      end
    end
  end
end)

test("skill sort renamed skills and legacy labels share stable IDs and current canonical names",function()
  local cases={
    {id=4,canonical="Piercing Weapons",names={"Piercing Weapons","Piercing","Pole Weapons","Poles"}},
    {id=5,canonical="Thrown Weapons",names={"Thrown Weapons","Thrown","Throw Weapons","Throws"}},
    {id=7,canonical="Shield Use",names={"Shield Use","Shield Parry"}},
  }
  for _,case in ipairs(cases) do
    for _,value in ipairs(case.names) do
      local messy="\27[32m ** "..value:upper():gsub(" "," \t ").." \27[0m\r"
      eq(SkillSort.skillId(value),case.id); eq(SkillSort.skillId(messy),case.id)
      eq(SkillSort.canonicalName(messy),case.canonical)
      for _,remain in ipairs({0,17}) do
        eq(SkillSort.combatCategory({name=messy,remain=remain}),"combat")
        eq(Display.category({name=messy,remain=remain}),remain==0 and "ready" or "combat")
      end
    end
  end
  for _,value in ipairs({"Piercing Weapons Training","Thrown Weapons Training","Shield Usage","Future Piercing Weapons",
    "Pole","Throw","Shield","pole.*",string.rep("x",2049)}) do
    eq(SkillSort.skillId(value),nil); eq(SkillSort.canonicalName(value),nil)
    eq(SkillSort.combatCategory(value),"utility")
  end
  eq(SkillSort.canonicalName(nil),nil); eq(SkillSort.canonicalName({}),nil)
end)

test("skill sort uses current canonical alphabetical names and retains every legacy duplicate",function()
  local a={name="Pole Weapons",level=3,remain=17}
  local b={name="Piercing Weapons",level=3,remain=17}
  local c={name="Play Instruments",level=3,remain=17}
  local d={name="Shield Parry",level=3,remain=17}
  local e={name="Shield Use",level=3,remain=17}
  local f={name="Shield Training",level=3,remain=17}
  local g={name="Throw Weapons",level=3,remain=17}
  local h={name="Thrown Weapons",level=3,remain=17}
  local i={name="Throwing",level=3,remain=17}
  local j={name="Swimming",level=3,remain=17}
  local items={a,b,c,d,e,f,g,h,i,j,a}
  sequence(SkillSort.sorted(items,{primary="number",direction="asc",secondary="none"}),{a,b,a,g,h,d,e,j,c,f,i})
  sequence(SkillSort.sorted(items,{primary="number",direction="desc",secondary="none"}),{c,j,d,e,g,h,a,b,a,f,i})
  sequence(SkillSort.sorted(items,{primary="name",direction="asc",secondary="none"}),{a,b,a,c,f,d,e,j,i,g,h})
  sequence(SkillSort.sorted(items,{primary="name",direction="desc",secondary="none"}),{g,h,i,j,d,e,f,c,a,b,a})
  sequence(SkillSort.sorted(items),{a,b,a,c,f,d,e,j,i,g,h})
  sequence(items,{a,b,c,d,e,f,g,h,i,j,a})
  eq(a.name,"Pole Weapons"); eq(d.name,"Shield Parry"); eq(g.name,"Throw Weapons")
end)

test("skill sort renamed combat membership stays independent of zero use ready priority",function()
  local a={name="Piercing Weapons",level=3,remain=9}
  local b={name="Thrown Weapons",level=3,remain=0}
  local c={name="Shield Use",level=3,remain=0}
  local d={name="Swimming",level=3,remain=0}
  local e={name="Poles",level=3,remain=0}
  local f={name="Throws",level=3,remain=7}
  local g={name="Shield Parry",level=3,remain=4}
  local h={name="Piercing Weapons Training",level=3,remain=1}
  local items={a,b,c,d,e,f,g,h}
  sequence(SkillSort.sorted(items,{primary="category",direction="asc",secondary="ready",secondary_direction="asc"}),
    {e,c,b,a,g,f,d,h})
  sequence(SkillSort.sorted(items,{primary="category",direction="desc",secondary="ready",secondary_direction="asc"}),
    {d,h,e,c,b,a,g,f})
  sequence(SkillSort.sorted(items,{primary="ready",direction="asc",secondary="number",secondary_direction="asc"}),
    {e,b,c,d,a,f,g,h})
  sequence(SkillSort.sorted(items,{primary="ready",direction="desc",secondary="number",secondary_direction="asc"}),
    {a,f,g,h,e,b,c,d})
  sequence(items,{a,b,c,d,e,f,g,h})
end)

test("skill sort default is level descending uses ascending then canonical alphabetical",function()
  local a={name="Sharp Weapons",level=4,remain=400}
  local b={name="First Aid",level=4,remain=50}
  local c={name="Brawling",level=5,remain=0}
  local d={name="Dodging",level=4,remain=50}
  local items={a,b,c,d}
  sequence(SkillSort.sorted(items),{c,d,b,a})
  sequence(SkillSort.sorted(items,{primary="invalid",direction=false}),{c,d,b,a})
  sequence(items,{a,b,c,d})
end)

test("skill sort secondary directions are independent and none uses alphabetical fallback",function()
  local a={name="Swimming",level=2,remain=0}
  local b={name="Brawling",level=2,remain=4}
  local c={name="Dodging",level=1,remain=1}
  local items={a,b,c}
  sequence(SkillSort.sorted(items,{primary="level",direction="asc",secondary="uses",secondary_direction="desc"}),{c,b,a})
  sequence(SkillSort.sorted(items,{primary="level",direction="desc",secondary="uses",secondary_direction="desc"}),{b,a,c})
  sequence(SkillSort.sorted(items,{primary="level",secondary="none",secondary_direction="desc"}),{b,a,c})
end)

test("skill sort numbers are authoritative and unknown IDs stay last in either direction",function()
  local a={name="Future Zeta",number=1,level=999,remain=0}
  local b={name="* Sharps",number=999,level=1,remain=9}
  local c={name="Brawling",level=2,remain=9}
  local d={name="Future Alpha",number=2,level=1000,remain=0}
  local items={a,b,c,d}
  sequence(SkillSort.sorted(items,{primary="number",direction="asc",secondary="none"}),{c,b,d,a})
  sequence(SkillSort.sorted(items,{primary="number",direction="desc",secondary="none"}),{b,c,d,a})
  for _,item in ipairs(items) do item.level=1 end
  sequence(SkillSort.sorted(items,{secondary="number",secondary_direction="asc"}),{c,b,d,a})
  sequence(SkillSort.sorted(items,{secondary="number",secondary_direction="desc"}),{b,c,d,a})
  eq(a.number,1); eq(b.number,999); eq(d.number,2)
end)

test("skill sort ready uses numeric zero while category ignores readiness coloring",function()
  local a={name="Swimming",level=1,remain=0}
  local b={name="First Aid",level=1,remain=7}
  local c={name="Brawling",level=1,remain=0}
  local d={name="Future Art",level=1,remain="0"}
  local e={name="Alchemy",level=1}
  local items={a,b,c,d,e}
  sequence(SkillSort.sorted(items,{primary="ready",direction="asc",secondary="none"}),{c,a,e,b,d})
  sequence(SkillSort.sorted(items,{primary="ready",direction="desc",secondary="none"}),{e,b,d,c,a})
  sequence(SkillSort.sorted(items,{primary="category",direction="asc",secondary="none"}),{c,b,e,d,a})
  sequence(SkillSort.sorted(items,{primary="category",direction="desc",secondary="none"}),{e,d,a,c,b})
  eq(Display.category(a),"ready"); eq(Display.category(c),"ready")
  eq(SkillSort.combatCategory(a),"utility"); eq(SkillSort.combatCategory(c),"combat")
end)

test("skill sort canonical names defeat ANSI and display label ordering and preserve duplicate index",function()
  local a={name="\27[32m ** SHARPS \27[0m",level=2,remain=5}
  local b={name="Sharp Weapons",level=2,remain=5}
  local c={name="Sharp Vision",level=2,remain=5}
  local d={name=" sharp \t weapons ",level=2,remain=5}
  local items={a,c,b,d,a}
  sequence(SkillSort.sorted(items,{primary="name",direction="asc",secondary="none"}),{c,a,b,d,a})
  sequence(SkillSort.sorted(items,{primary="name",direction="desc",secondary="none"}),{a,b,d,a,c})
  sequence(SkillSort.sorted(items,{primary="level",secondary="none"}),{c,a,b,d,a})
  eq(a.name,"\27[32m ** SHARPS \27[0m"); eq(d.name," sharp \t weapons ")
end)

test("skill sort unknown names beyond display bounds still fall back alphabetically",function()
  local a={name="Zulu "..string.rep("a",2048),level=1,remain=1}
  local b={name="Alpha "..string.rep("z",2048),level=1,remain=1}
  eq(SkillSort.skillId(a.name),nil); eq(SkillSort.skillId(b.name),nil)
  sequence(SkillSort.sorted({a,b}),{b,a})
  sequence(SkillSort.sorted({a,b},{primary="name",direction="desc",secondary="none"}),{a,b})
end)

test("skill sort tolerates missing and nonfinite numeric fields without unstable comparisons",function()
  local a={name="Brawling",level=0/0,remain=math.huge}
  local b={name="Dodging",level="2",remain="3"}
  local c={name="Swimming",level=false,remain={}}
  local d={name="Future Art",level=-math.huge}
  sequence(SkillSort.sorted({c,d,b,a}),{b,a,d,c})
  local empty={}; local sorted=SkillSort.sorted(empty); assert(sorted~=empty); eq(#sorted,0)
  eq(#SkillSort.sorted(nil),0); eq(#SkillSort.sorted(false),0)
end)

-- Independent rank fixtures exercise conflicting keys, ties, known and unknown
-- IDs, duplicate canonical names and original index across every preference.
local fixture={
  {name="Swimming",level=2,remain=0},
  {name="\27[32m * SHARPS\27[0m",level=4,remain=30},
  {name="Future Zeta",level=4,remain=0},
  {name="Brawling",level=4,remain=30},
  {name="First Aid",level=2,remain=5},
  {name="Future Alpha",level=4,remain=5},
  {name=" sharp \t weapons ",level=4,remain=30},
  {name="Alchemy",level=2,remain=5},
  {name="Blunts",level=4,remain=0},
  {name="Sharp Vision",level=2,remain=5},
  {name="Brawling",level=4,remain=30},
}
local ranks={
  {name=9,number=23,category=1,ready=0},
  {name=8,number=2,category=0,ready=1},
  {name=6,category=1,ready=0},
  {name=3,number=1,category=0,ready=1},
  {name=4,number=42,category=0,ready=1},
  {name=5,category=1,ready=1},
  {name=8,number=2,category=0,ready=1},
  {name=1,number=24,category=1,ready=1},
  {name=2,number=3,category=0,ready=0},
  {name=7,category=1,ready=1},
  {name=3,number=1,category=0,ready=1},
}
local function rank(index,key,direction)
  local value
  if key=="level" then value=fixture[index].level
  elseif key=="uses" then value=fixture[index].remain
  else value=ranks[index][key] end
  if value==nil then return math.huge end
  return direction=="desc" and -value or value
end
local function expected(config)
  local order={}
  for index=1,#fixture do
    local tuple={rank(index,config.primary,config.direction)}
    if config.secondary~="none" then tuple[#tuple+1]=rank(index,config.secondary,config.secondary_direction) end
    tuple[#tuple+1]=ranks[index].name; tuple[#tuple+1]=ranks[index].number or math.huge; tuple[#tuple+1]=index
    local position=#order+1
    for at,entry in ipairs(order) do
      local before=false
      for column,value in ipairs(tuple) do
        if value~=entry.tuple[column] then before=value<entry.tuple[column]; break end
      end
      if before then position=at; break end
    end
    table.insert(order,position,{index=index,tuple=tuple})
  end
  local result={}; for index,entry in ipairs(order) do result[index]=fixture[entry.index] end
  return result
end
for _,primary in ipairs(keys) do
  for _,direction in ipairs({"asc","desc"}) do
    for _,secondary in ipairs(secondaryKeys) do
      for _,secondaryDirection in ipairs({"asc","desc"}) do
        local config={primary=primary,direction=direction,secondary=secondary,secondary_direction=secondaryDirection}
        test("skill sort "..primary.." "..direction.." then "..secondary.." "..secondaryDirection,function()
          configEq(assert(SkillSort.validate(config)),config)
          local originals={}; local snapshots={}
          for index,item in ipairs(fixture) do
            originals[index]=item; snapshots[index]={name=item.name,level=item.level,remain=item.remain}
          end
          local sorted=SkillSort.sorted(fixture,config); assert(sorted~=fixture)
          sequence(sorted,expected(config)); sequence(SkillSort.sorted(fixture,config),sorted)
          sequence(fixture,originals)
          for index,item in ipairs(fixture) do
            eq(item.name,snapshots[index].name); eq(item.level,snapshots[index].level); eq(item.remain,snapshots[index].remain)
            local count=0; for _ in pairs(item) do count=count+1 end; eq(count,3)
          end
          configEq(config,{primary=primary,direction=direction,secondary=secondary,secondary_direction=secondaryDirection})
        end)
      end
    end
  end
end

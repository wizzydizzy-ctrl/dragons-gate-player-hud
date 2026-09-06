local Catalog=require("map_catalog")

local function entry(overrides)
  local value={
    slug="spur-academy",name="Spurian Cadet Academy",author="Gia Afari",publisher="gia-afari",
    description="Academy and adjoining training rooms.",version="1.2.0",areas={"Academy","Training"},room_count=42,bytes=1234,
    download_url="https://raw.githubusercontent.com/wizzydizzy-ctrl/dragons-gate-map-library/main/maps/gia-afari/spur-academy.json",
    sha256=string.rep("a",64),
  }
  for key,item in pairs(overrides or {}) do value[key]=item end
  return value
end
local function catalog(maps) return {schema=1,maps=maps or {entry()}} end

test("map catalog validates and copies a strict schema 1 catalog",function()
  local source=catalog(); local result=assert(Catalog.validate(source))
  eq(result.schema,1); eq(result.maps[1].slug,"spur-academy"); eq(result.maps[1].room_count,42)
  result.maps[1].areas[1]="changed"; eq(source.maps[1].areas[1],"Academy")
end)

test("map catalog accepts optional scope metadata while keeping legacy entries full maps",function()
  local legacy=assert(Catalog.validate(catalog())).maps[1]; eq(legacy.scope,"full_map"); eq(#legacy.subareas,0)
  local scoped=assert(Catalog.validate(catalog({entry({scope="subarea",subareas={"Crypt","Lower Crypt"}})}))).maps[1]
  eq(scoped.scope,"subarea"); eq(scoped.subareas[2],"Lower Crypt")
  eq(Catalog.validate(catalog({entry({scope="district"})})),nil)
end)

test("map catalog accepts an empty dense maps array",function()
  local result=assert(Catalog.validate({schema=1,maps={}})); eq(#result.maps,0)
end)

test("map catalog rejects unknown missing and wrong-schema fields",function()
  local bad=catalog(); bad.extra=true; eq(Catalog.validate(bad),nil)
  bad=catalog(); bad.maps[1].author=nil; eq(Catalog.validate(bad),nil)
  bad=catalog(); bad.maps[1].surprise=true; eq(Catalog.validate(bad),nil)
  eq(Catalog.validate({schema=3,maps={}}),nil)
end)

test("map catalog requires dense bounded arrays",function()
  local bad=catalog(); bad.maps[2]=nil; bad.maps[3]=entry({slug="other",download_url="https://raw.githubusercontent.com/wizzydizzy-ctrl/dragons-gate-map-library/main/maps/gia-afari/other.json"}); eq(Catalog.validate(bad),nil)
  bad=catalog(); bad.maps[1].areas={[1]="A",[3]="C"}; eq(Catalog.validate(bad),nil)
  bad=catalog(); bad.maps[1].areas={}; eq(Catalog.validate(bad),nil)
end)

test("map catalog enforces text numeric and identity limits",function()
  eq(Catalog.validate(catalog({entry({slug="Bad_Slug"})})),nil)
  eq(Catalog.validate(catalog({entry({name=string.rep("n",101)})})),nil)
  eq(Catalog.validate(catalog({entry({description="bad\ntext"})})),nil)
  eq(Catalog.validate(catalog({entry({version="latest"})})),nil)
  eq(Catalog.validate(catalog({entry({room_count=0})})),nil)
  eq(Catalog.validate(catalog({entry({room_count=1.5})})),nil)
  eq(Catalog.validate(catalog({entry({bytes=0})})),nil)
  eq(Catalog.validate(catalog({entry({publisher="bad--name"})})),nil)
end)

test("map catalog permits only matching raw library download paths",function()
  eq(Catalog.validate(catalog({entry({download_url="https://example.com/map.json"})})),nil)
  eq(Catalog.validate(catalog({entry({download_url="http://raw.githubusercontent.com/wizzydizzy-ctrl/dragons-gate-map-library/main/maps/gia-afari/spur-academy.json"})})),nil)
  eq(Catalog.validate(catalog({entry({download_url="https://raw.githubusercontent.com/wizzydizzy-ctrl/dragons-gate-map-library/main/maps/other/spur-academy.json"})})),nil)
  eq(Catalog.validate(catalog({entry({download_url="https://raw.githubusercontent.com/wizzydizzy-ctrl/dragons-gate-map-library/main/maps/gia-afari/../evil.json"})})),nil)
  eq(Catalog.validate(catalog({entry({download_url="https://raw.githubusercontent.com/wizzydizzy-ctrl/dragons-gate-map-library/main/maps/gia-afari/spur-academy.json?raw=1"})})),nil)
end)

test("map catalog requires canonical sha256 and unique publisher slug",function()
  eq(Catalog.validate(catalog({entry({sha256=string.rep("A",64)})})),nil)
  eq(Catalog.validate(catalog({entry(),entry()})),nil)
end)

test("map catalog selects only validated entries",function()
  local selected=assert(Catalog.select(catalog(),"GIA-AFARI","spur-academy")); eq(selected.author,"Gia Afari")
  local missing,err=Catalog.select(catalog(),"gia-afari","missing"); eq(missing,nil); eq(err,"map not found")
  eq(Catalog.select({schema=1,maps={[2]=entry()}},"gia-afari","spur-academy"),nil)
end)

test("map catalog search matches visible metadata literally",function()
  local maps={entry(),entry({slug="temple",name="Temple District",author="Other Mapper",publisher="other-user",description="The city temple district.",areas={"Temple"},download_url="https://raw.githubusercontent.com/wizzydizzy-ctrl/dragons-gate-map-library/v1/maps/other-user/temple.json",sha256=string.rep("b",64)})}
  local matches=assert(Catalog.search(catalog(maps),"academy")); eq(#matches,1); eq(matches[1].slug,"spur-academy")
  matches=assert(Catalog.search(catalog(maps),"Gia Afari")); eq(#matches,1)
  matches=assert(Catalog.search(catalog(maps),".")); eq(#matches,2)
end)

test("map catalog filters by friendly scope name author area and subarea",function()
  local entries={entry(),entry({slug="crypt",name="Old Crypt",author="Retro",publisher="retro",scope="subarea",areas={"Cemetery"},subareas={"Lower Vault"},download_url="https://raw.githubusercontent.com/wizzydizzy-ctrl/dragons-gate-map-library/main/maps/retro/crypt.json",sha256=string.rep("b",64)})}
  local normalized=assert(Catalog.validate(catalog(entries))).maps
  local matches=Catalog.filterEntries(normalized,"retro","subarea"); eq(#matches,1); eq(matches[1].slug,"crypt")
  matches=Catalog.filterEntries(normalized,"lower vault","all"); eq(#matches,1)
  matches=Catalog.filterEntries(normalized,"gia","full_map"); eq(#matches,1); eq(Catalog.scopeLabel(matches[1]),"Full Map")
  eq(Catalog.scopeLabel(normalized[2]),"Subarea")
end)

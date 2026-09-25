local Sounds=require("chat_sounds")

test("chat sound defaults give every tab a distinct sound with only staff enabled",function()
  local defaults=Sounds.defaults(); local seen={}; eq(defaults.volume,60)
  for _,tab in ipairs(Sounds.tabOrder) do
    local entry=defaults.tabs[tab]; eq(entry.enabled,tab=="STAFF"); assert(Sounds.get(entry.sound)); eq(seen[entry.sound],nil); seen[entry.sound]=true
  end
  defaults.tabs.STAFF.enabled=false; eq(Sounds.defaults().tabs.STAFF.enabled,true)
end)
test("chat sound validation preserves explicit off and custom tab choices",function()
  local config=assert(Sounds.validate({volume=30,tabs={STAFF={enabled=false,sound="room"},QUEST={enabled=true,sound="dragon"}}}))
  eq(config.tabs.STAFF.enabled,false); eq(config.tabs.STAFF.sound,"room"); eq(config.tabs.QUEST.enabled,true); eq(config.tabs.ROOM.enabled,false)
  eq(Sounds.tabKey("whisper"),"PRIVATE"); eq(Sounds.tabKey("OWN"),"ROOM")
  for _,bad in ipairs({false,"yes",{volume=0},{volume=101},{volume=0/0},{volume=1.5},{volume="60"},{tabs=false},{tabs={STAFF={enabled="no"}}},{tabs={STAFF={sound="../../file"}}},{tabs={["<script>"]={}}},{tabs={STAFF=false}}}) do eq(Sounds.validate(bad),nil) end
  local many={}; for i=1,65 do many["TAB"..i]={} end; eq(Sounds.validate({tabs=many}),nil)
  local boundary={}; for i=1,55 do boundary["CUSTOM"..i]={enabled=false,sound="all"} end
  local normalized=assert(Sounds.validate({tabs=boundary})); assert(Sounds.validate(normalized))
  boundary.CUSTOM56={}; eq(Sounds.validate({tabs=boundary}),nil)
end)
test("sound selection never duplicates ALL PRIVATE and specific tab notifications",function()
  local config=Sounds.defaults(); config.tabs.ALL.enabled=true; config.tabs.PRIVATE.enabled=true
  config.tabs.ESP.enabled=true
  local sound,tab=Sounds.choose(config,"ESP",{}); eq(sound,"esp"); eq(tab,"ESP")
  config.tabs.ESP.enabled=false; sound,tab=Sounds.choose(config,"ESP",{}); eq(sound,"private"); eq(tab,"PRIVATE")
  config.tabs.PRIVATE.enabled=false; sound,tab=Sounds.choose(config,"ESP",{}); eq(sound,"all"); eq(tab,"ALL")
  eq(Sounds.choose(config,"ESP",{ESP=false}),nil)
  eq(Sounds.choose(config,"STAFF",{STAFF=false}),"staff")
  config.tabs.ROOM.enabled=true; eq(Sounds.choose(config,"OWN",{}),"room")
  config.tabs.PRIVATE.enabled=true; eq(Sounds.choose(config,"WHISPER",{}),"private")
  config.tabs.QUEST={enabled=true,sound="dragon"}; eq(Sounds.choose(config,"QUEST",{}),"dragon")
end)
test("sound playback is bounded per tab and preview does not change toggles",function()
  local adapter={now=100,played={}}
  function adapter:epoch() return self.now end
  function adapter:playChatSound(id,volume) self.played[#self.played+1]={id,volume}; return true end
  local sound=assert(Sounds.new(adapter))
  assert(sound:onEntry({category="STAFF"})); eq(#adapter.played,1)
  eq(sound:onEntry({category="STAFF"}),false); eq(#adapter.played,1)
  eq(sound:onEntry({category="ROOM"}),false)
  adapter.now=101; assert(sound:onEntry({category="STAFF"})); eq(#adapter.played,2)
  assert(sound:play("room")); eq(#adapter.played,3); eq(sound.config.tabs.ROOM.enabled,false)
  eq(sound:play("https://unsafe/file.wav"),nil)
  local candidate=Sounds.defaults(); candidate.tabs.STAFF.enabled=false; assert(sound:setConfig(candidate))
  adapter.now=103; eq(sound:onEntry({category="STAFF"}),false); eq(#adapter.played,3)
end)
test("missing or failing sound APIs never throw into chat",function()
  local sound=assert(Sounds.new({})); eq(sound:onEntry({category="STAFF"}),nil)
  sound=assert(Sounds.new({playChatSound=function() error("bad backend") end})); eq(sound:play("staff"),nil)
  sound=assert(Sounds.new({playChatSound=function() return false,"muted" end})); local ok,err=sound:play("staff"); eq(ok,nil); eq(err,"muted")
end)
test("sound cooldown uses fractional time across whole second boundaries",function()
  local now,count=100.99,0
  local sound=assert(Sounds.new({epoch=function() return math.floor(now) end,chatSoundTime=function() return now end,playChatSound=function() count=count+1; return true end}))
  assert(sound:onEntry({category="STAFF"})); now=101.01
  eq(sound:onEntry({category="STAFF"}),false); eq(count,1)
  now=102; assert(sound:onEntry({category="STAFF"})); eq(count,2)
end)
local function uint(data,offset,bytes)
  local value=0; for i=bytes-1,0,-1 do value=value*256+data:byte(offset+i) end; return value
end
test("nine locally generated tones are distinct bounded valid PCM WAV files",function()
  local seen={}
  for _,record in ipairs(Sounds.catalog) do
    local wav=assert(Sounds.wav(record.id)); eq(wav:sub(1,4),"RIFF"); eq(wav:sub(9,16),"WAVEfmt "); eq(wav:sub(37,40),"data")
    eq(uint(wav,5,4),#wav-8); eq(uint(wav,41,4),#wav-44)
    eq(uint(wav,21,2),1); eq(uint(wav,23,2),1); eq(uint(wav,25,4),22050); eq(uint(wav,35,2),16)
    assert(#wav>4000 and #wav<65536); eq(seen[wav],nil); seen[wav]=true; eq(Sounds.wav(record.id),wav)
    local peak=0; for i=45,#wav,2 do local n=uint(wav,i,2); if n>=32768 then n=n-65536 end; peak=math.max(peak,math.abs(n)) end
    assert(peak>1000 and peak<16000,"tone must be audible without clipping")
    assert(record.file:match("^chat%-%l+%-v1%.wav$"))
  end
  eq(Sounds.wav("../arbitrary"),nil)
end)

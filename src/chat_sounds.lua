local Sounds={}
Sounds.__index=Sounds
Sounds.tabOrder={"ALL","ROOM","PRIVATE","ESP","DRAGON","SECIAN","CONTACT","STAFF","COMBAT"}
Sounds.catalog={
  {id="all",label="Soft Bell",file="chat-all-v1.wav"},
  {id="room",label="Room Chime",file="chat-room-v1.wav"},
  {id="private",label="Quiet Knock",file="chat-private-v1.wav"},
  {id="esp",label="Crystal Rise",file="chat-esp-v1.wav"},
  {id="dragon",label="Dragon Call",file="chat-dragon-v1.wav"},
  {id="secian",label="Secian Twinkle",file="chat-secian-v1.wav"},
  {id="contact",label="Mind Echo",file="chat-contact-v1.wav"},
  {id="staff",label="Staff Three-Tone",file="chat-staff-v1.wav"},
  {id="combat",label="Combat Pulse",file="chat-combat-v1.wav"},
}
local byId={}; for _,sound in ipairs(Sounds.catalog) do byId[sound.id]=sound end
function Sounds.get(id) return type(id)=="string" and byId[id] or nil end
function Sounds.tabKey(value)
  if type(value)~="string" or #value>32 then return nil end
  local key=value:upper():match("^%s*(.-)%s*$")
  if not key:match("^[A-Z][A-Z0-9 _%-]*$") then return nil end
  if key=="OWN" then return "ROOM" end
  if key=="WHISPER" then return "PRIVATE" end
  return key
end
function Sounds.defaults()
  local result={volume=60,tabs={}}
  for _,tab in ipairs(Sounds.tabOrder) do result.tabs[tab]={enabled=tab=="STAFF",sound=tab:lower()} end
  return result
end
function Sounds.validate(config)
  local result=Sounds.defaults()
  if config==nil then return result end
  if type(config)~="table" then return nil,"sound settings must be a table" end
  if config.volume~=nil then
    local n=config.volume
    if type(n)~="number" or n~=n or n<1 or n>100 or n%1~=0 then return nil,"sound volume must be a whole number from 1 to 100" end
    result.volume=n
  end
  if config.tabs~=nil then
    if type(config.tabs)~="table" then return nil,"sound tabs must be a table" end
    local count,seen=#Sounds.tabOrder,{}
    for tab,value in pairs(config.tabs) do
      local key=Sounds.tabKey(tab)
      if not key or seen[key] or type(value)~="table" then return nil,"invalid sound tab settings" end
      seen[key]=true
      if not result.tabs[key] then count=count+1 end
      if count>64 then return nil,"too many sound tabs" end
      local entry=result.tabs[key] or {enabled=false,sound="all"}
      if value.enabled~=nil then
        if type(value.enabled)~="boolean" then return nil,"sound ON/OFF must be a boolean" end
        entry.enabled=value.enabled
      end
      if value.sound~=nil then
        if not Sounds.get(value.sound) then return nil,"choose a bundled alert sound" end
        entry.sound=value.sound
      end
      result.tabs[key]=entry
    end
  end
  return result
end

-- Original, bounded notification tones, generated locally on first use. No
-- downloaded media, user-supplied paths, or executable chat text is involved.
local tones={
  all={{660,.26}}, room={{440,.16},{554.37,.20}},
  private={{330,.10},{330,.13}}, esp={{659.25,.13},{987.77,.24}},
  dragon={{261.63,.16},{392,.28}}, secian={{1046.5,.09},{1318.51,.09},{1567.98,.16}},
  contact={{783.99,.16},{587.33,.22}}, staff={{659.25,.16},{880,.16},{1108.73,.30}},
  combat={{220,.12},{293.66,.12},{220,.12}},
}
local function little(n,bytes)
  local result={}; for i=1,bytes do result[i]=string.char(n%256); n=math.floor(n/256) end; return table.concat(result)
end
function Sounds.wav(id)
  if not Sounds.get(id) then return nil,"choose a bundled alert sound" end
  local rate,parts=22050,{}
  for _,note in ipairs(tones[id]) do
    local frequency,duration=note[1],note[2]
    local samples=math.floor(rate*duration)
    for i=0,samples-1 do
      local t=i/rate
      local envelope=math.min(1,t/.006)*math.min(1,(duration-t)/.02)*math.exp(-4*t/duration)
      local wave=math.sin(2*math.pi*frequency*t)+.18*math.sin(2*math.pi*frequency*2*t)
      local value=math.floor(6500*envelope*wave+.5)
      if value<0 then value=value+65536 end
      parts[#parts+1]=little(value,2)
    end
    parts[#parts+1]=string.rep("\0",math.floor(rate*.045)*2)
  end
  local data=table.concat(parts)
  return "RIFF"..little(36+#data,4).."WAVEfmt "..little(16,4)..little(1,2)..little(1,2)..little(rate,4)..little(rate*2,4)..little(2,2)..little(16,2).."data"..little(#data,4)..data
end

local private={WHISPER=true,ESP=true,DRAGON=true,SECIAN=true,CONTACT=true}
function Sounds.choose(config,category,allSources)
  local key=Sounds.tabKey(category)
  if not key or type(config)~="table" or type(config.tabs)~="table" then return nil end
  local function enabled(tab)
    local value=config.tabs[tab]
    if value and value.enabled==true and Sounds.get(value.sound) then return value.sound,tab end
  end
  local sound,tab=enabled(key)
  if sound then return sound,tab end
  local raw=type(category)=="string" and category:upper():match("^%s*(.-)%s*$") or ""
  if private[raw] and key~="PRIVATE" then sound,tab=enabled("PRIVATE"); if sound then return sound,tab end end
  if raw=="OWN" then raw="ROOM" end
  if type(allSources)~="table" or allSources[raw]~=false then return enabled("ALL") end
end
function Sounds.new(adapter,config)
  local validated,err=Sounds.validate(config)
  if not validated then return nil,err end
  return setmetatable({adapter=adapter,config=validated,lastPlayed={}},Sounds)
end
function Sounds:setConfig(config)
  local validated,err=Sounds.validate(config); if not validated then return nil,err end
  self.config=validated; return true
end
function Sounds:play(id)
  if not Sounds.get(id) then return nil,"choose a bundled alert sound" end
  if not self.adapter or type(self.adapter.playChatSound)~="function" then return nil,"Sound playback is unavailable in this Mudlet installation." end
  local ok,played,err=pcall(self.adapter.playChatSound,self.adapter,id,self.config.volume)
  if not ok or played==nil or played==false then return nil,err or "Could not play the alert. Check Mudlet's media mute and sound settings." end
  return true
end
function Sounds:onEntry(entry,allSources)
  if type(entry)~="table" then return false end
  local id,tab=Sounds.choose(self.config,entry.category,allSources)
  if not id then return false end
  local now=os.time()
  local clock=self.adapter and (self.adapter.chatSoundTime or self.adapter.epoch)
  if type(clock)=="function" then local ok,value=pcall(clock,self.adapter); if ok and type(value)=="number" and value==value and value~=math.huge and value~=-math.huge then now=value end end
  local last=self.lastPlayed[tab]
  -- A burst of wrapped/rapid messages must not build up an audio queue. The
  -- specific tab wins over PRIVATE/ALL, so each message selects one sound.
  if last and now>=last and now-last<1 then return false end
  self.lastPlayed[tab]=now
  return self:play(id)
end
return Sounds

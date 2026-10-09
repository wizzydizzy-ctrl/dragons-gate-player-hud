local Audio={}
Audio.__index=Audio
Audio.catalog={
  {id="three_tone",label="Three-Tone"},
  {id="chime",label="Chime"},
  {id="alarm",label="Alarm"},
  {id="horn",label="Horn"},
}
Audio.MAX_BYTES=10*1024*1024
Audio.MAX_SECONDS=60
Audio.MAX_NAME=120
local allowed={three_tone=true,chime=true,alarm=true,horn=true,custom=true}
local keys={alert="DGHUD.AutorollerAlert",preview="DGHUD.AutorollerPreview"}
local cacheName="autoroller-sounds-v1"

function Audio.defaults()
  return {enabled=true,sound="three_tone",volume=75,repeat_enabled=false}
end
local function cacheFile(value)
  return type(value)=="string" and #value==68 and value:sub(-4)==".wav"
    and value:sub(1,64):match("^[0-9a-fA-F]+$") and value:lower() or nil
end
local function displayName(value)
  if type(value)~="string" or #value>4096 or value=="" or value:find("[/\\:]") then return nil end
  -- This is a display label, never a filesystem path. ASCII also avoids hidden
  -- Unicode direction/control characters; the selected source path stays intact.
  local name=value:gsub("[^%w ._%-]","_"):gsub("%.%.","_"):gsub("^[ .%-]+",""):gsub("[ .]+$","")
  name=name:sub(1,Audio.MAX_NAME):gsub("[ .]+$","")
  if name=="" then return nil end
  return name
end
function Audio.validate(settings)
  local result=Audio.defaults()
  if settings==nil then return result end
  if type(settings)~="table" then return nil,"Audio settings must be a table." end
  for _,key in ipairs({"enabled","repeat_enabled"}) do
    if settings[key]~=nil then
      if type(settings[key])~="boolean" then return nil,"Audio ON/OFF settings must be boolean values." end
      result[key]=settings[key]
    end
  end
  if settings.sound~=nil then
    if type(settings.sound)~="string" or not allowed[settings.sound] then return nil,"Choose an autoroller alert sound." end
    result.sound=settings.sound
  end
  if settings.volume~=nil then
    local n=settings.volume
    if type(n)~="number" or n~=n or n<1 or n>100 or n%1~=0 then return nil,"Audio volume must be a whole number from 1 to 100." end
    result.volume=n
  end
  if settings.custom_file~=nil then
    result.custom_file=cacheFile(settings.custom_file)
    if not result.custom_file then return nil,"The saved custom sound identifier is invalid." end
  end
  if settings.custom_name~=nil then
    result.custom_name=displayName(settings.custom_name)
    if not result.custom_name then return nil,"The custom sound label must be a filename only." end
  end
  return result
end

local function little(n,count)
  local out={}; for i=1,count do out[i]=string.char(n%256); n=math.floor(n/256) end
  return table.concat(out)
end
local function uint(bytes,offset,count)
  local n=0; for i=count-1,0,-1 do n=n*256+bytes:byte(offset+i) end; return n
end
local notes={
  three_tone={{659.25,.16},{880,.16},{1108.73,.30}},
  chime={{880,.25},{1318.51,.40}},
  alarm={{880,.24},{660,.24},{880,.24},{660,.24}},
  horn={{196,.65}},
}
function Audio.wav(id)
  if not notes[id] then return nil,"Choose a built-in autoroller sound." end
  local rate,parts=22050,{}
  for _,note in ipairs(notes[id]) do
    local frequency,duration=note[1],note[2]
    for i=0,math.floor(rate*duration)-1 do
      local t=i/rate
      local envelope=math.min(1,t/.012)*math.min(1,(duration-t)/.035)
      if id=="chime" or id=="three_tone" then envelope=envelope*math.exp(-3*t/duration) end
      local phase=2*math.pi*frequency*t
      local wave=math.sin(phase)+.18*math.sin(2*phase)
      if id=="horn" then wave=math.sin(phase)+.35*math.sin(2*phase)+.2*math.sin(3*phase) end
      local sample=math.floor(8000*envelope*wave+.5)
      parts[#parts+1]=little(sample%65536,2)
    end
    parts[#parts+1]=string.rep("\0",math.floor(rate*.045)*2)
  end
  local data=table.concat(parts)
  return "RIFF"..little(36+#data,4).."WAVEfmt "..little(16,4)
    ..little(1,2)..little(1,2)..little(rate,4)..little(rate*2,4)
    ..little(2,2)..little(16,2).."data"..little(#data,4)..data
end

-- Only ordinary uncompressed RIFF/WAVE is accepted. Compressed, extensible,
-- truncated, and ambiguous files never reach Mudlet's media decoder.
function Audio.validateWav(bytes)
  if type(bytes)~="string" or #bytes>Audio.MAX_BYTES then return nil,"Choose a WAV file no larger than 10 MiB." end
  local invalid="The WAV file is corrupt or uses an unsupported audio format."
  if #bytes<44 or bytes:sub(1,4)~="RIFF" or bytes:sub(9,12)~="WAVE" or uint(bytes,5,4)~=#bytes-8 then return nil,invalid end
  local position,fmt,dataStart,dataSize,chunks=13,nil,nil,nil,0
  while position<=#bytes do
    chunks=chunks+1
    if chunks>4096 or position+7>#bytes then return nil,invalid end
    local id=bytes:sub(position,position+3)
    local size=uint(bytes,position+4,4)
    local start=position+8; local following=start+size+size%2
    if following>#bytes+1 then return nil,invalid end
    if id=="fmt " then
      if fmt or size<16 or size==17 or (size>=18 and uint(bytes,start+16,2)~=size-18) then return nil,invalid end
      fmt={format=uint(bytes,start,2),channels=uint(bytes,start+2,2),rate=uint(bytes,start+4,4),
        byteRate=uint(bytes,start+8,4),align=uint(bytes,start+12,2),bits=uint(bytes,start+14,2)}
    elseif id=="data" then
      if dataStart then return nil,invalid end
      dataStart,dataSize=start,size
    end
    position=following
  end
  if not fmt or not dataStart or dataSize==0 or fmt.channels<1 or fmt.channels>2 or fmt.rate<1 or fmt.rate>192000 then return nil,invalid end
  local pcm=fmt.format==1 and (fmt.bits==8 or fmt.bits==16 or fmt.bits==24 or fmt.bits==32)
  local floating=fmt.format==3 and (fmt.bits==32 or fmt.bits==64)
  if not pcm and not floating then return nil,invalid end
  if fmt.align~=fmt.channels*fmt.bits/8 or fmt.byteRate~=fmt.rate*fmt.align or dataSize%fmt.align~=0 then return nil,invalid end
  local duration=dataSize/fmt.byteRate
  if duration>Audio.MAX_SECONDS then return nil,"Choose a WAV file no longer than 60 seconds." end
  if floating then
    local width=fmt.bits/8
    for p=dataStart,dataStart+dataSize-1,width do
      local exponent
      if width==4 then exponent=(bytes:byte(p+3)%128)*2+math.floor(bytes:byte(p+2)/128)
      else exponent=(bytes:byte(p+7)%128)*16+math.floor(bytes:byte(p+6)/16) end
      if exponent==(width==4 and 255 or 2047) then return nil,invalid end
    end
  end
  return duration
end

local function pathParts(value)
  if type(value)~="string" or value=="" or #value>4096 or value:find("[%z\1-\31\127]") or value:find("://",1,true) then return nil end
  local path=value:gsub("\\","/")
  local root,rest="",path
  if path:match("^%a:/") then root,rest=path:sub(1,3),path:sub(4)
  elseif path:sub(1,2)=="//" then
    root,rest=path:match("^(//[^/]+/[^/]+)/?(.*)$")
    if not root then return nil end
  elseif path:sub(1,1)=="/" then root,rest="/",path:sub(2) end
  if rest:find(":",1,true) or path:find('[<>|?*"]') then return nil end
  local parts={}
  for part in rest:gmatch("[^/]+") do
    if part==".." then return nil end
    if part~="." then parts[#parts+1]=part end
  end
  if #parts==0 then return nil end
  return root,parts
end
local function joined(root,parts,count)
  local prefix=root
  for i=1,count do prefix=prefix..((prefix=="" or prefix:sub(-1)=="/") and "" or "/")..parts[i] end
  return prefix
end
local function succeeded(fn,...)
  if type(fn)~="function" then return nil end
  local ok,result,err=pcall(fn,...)
  if not ok or result==false or (result==nil and err~=nil) then return nil end
  return true
end
function Audio.new(options)
  if options~=nil and type(options)~="table" then return nil,"Audio options must be a table." end
  options=options or {}
  return setmetatable({base=options.base,fs=options.fs or rawget(_G,"lfs"),io=options.io or io,os=options.os or os,
    playSoundFile=options.playSoundFile or rawget(_G,"playSoundFile"),stopSounds=options.stopSounds or rawget(_G,"stopSounds"),
    invokeFileDialog=options.invokeFileDialog or rawget(_G,"invokeFileDialog"),generated={}},Audio)
end
function Audio:_mode(path)
  if not self.fs or type(self.fs.symlinkattributes)~="function" then return nil,"Safe audio filesystem inspection is unavailable." end
  -- Requesting the full table can fail on Windows when it includes link targets.
  local ok,mode,err,code=pcall(self.fs.symlinkattributes,path,"mode")
  if not ok then return nil,"Could not safely inspect the audio file." end
  if mode==nil and err~=nil then
    local message=tostring(err):lower()
    if code~=2 and not message:find("no such file",1,true) and not message:find("cannot find the file",1,true)
      and not message:find("cannot find the path",1,true) then return nil,"Could not safely inspect the audio file." end
  end
  if mode~=nil and type(mode)~="string" then return nil,"Could not safely inspect the audio file." end
  return mode
end
function Audio:_parents(path,create)
  local root,parts=pathParts(path)
  if not root then return nil,"Choose a regular local WAV file or a safe audio cache directory." end
  for i=1,#parts do
    local current=joined(root,parts,i)
    local mode,err=self:_mode(current); if err then return nil,err end
    if mode==nil and create then
      if not self.fs or not succeeded(self.fs.mkdir,current) then return nil,"Could not create the private audio cache." end
      mode,err=self:_mode(current); if err then return nil,err end
    end
    if mode~="directory" then return nil,"Audio paths must use regular directories without symbolic links." end
  end
  return joined(root,parts,#parts)
end
function Audio:_read(path)
  local root,parts=pathParts(path)
  if not root then return nil,"Choose a regular local WAV file." end
  if #parts>1 then
    local parent,err=self:_parents(joined(root,parts,#parts-1),false); if not parent then return nil,err end
  end
  local mode,err=self:_mode(path); if err then return nil,err end
  if mode~="file" then return nil,"The audio file is unavailable or is not a regular file." end
  if not self.io or type(self.io.open)~="function" then return nil,"Audio file access is unavailable." end
  local opened,file=pcall(self.io.open,path,"rb")
  if not opened or not file then return nil,"Could not read the selected audio file." end
  local read,bytes,readErr=pcall(function() return file:read(Audio.MAX_BYTES+1) end)
  local closed=succeeded(function() return file:close() end)
  if not read or type(bytes)~="string" or readErr~=nil or not closed then return nil,"Could not read the selected audio file." end
  local current,inspectErr=self:_mode(path)
  if inspectErr or current~="file" then return nil,"The audio file changed while being read." end
  local duration,wavErr=Audio.validateWav(bytes)
  if not duration then return nil,wavErr end
  return bytes,nil,duration
end
function Audio:_directory(create)
  if self.base==nil then
    local loaded,adapter=pcall(require,"mudlet_adapter")
    if loaded and type(adapter)=="table" and type(adapter.dataBase)=="function" then
      local ok,base=pcall(adapter.dataBase); if ok then self.base=base end
    end
  end
  local root,parts=pathParts(self.base)
  if not root then return nil,"The private audio cache directory is unavailable." end
  return self:_parents(joined(root,parts,#parts).."/"..cacheName,create)
end
local SHA256
local function digest(bytes)
  if not SHA256 then local ok,module=pcall(require,"sha256"); if ok then SHA256=module end end
  if type(SHA256)~="table" or type(SHA256.hex)~="function" then return nil,"Audio checksum verification is unavailable." end
  local ok,value=pcall(SHA256.hex,bytes)
  if not ok or not cacheFile(tostring(value)..".wav") then return nil,"Audio checksum verification failed." end
  return value:lower()
end
function Audio:_cache(bytes,builtinId)
  local hash,err=digest(bytes); if not hash then return nil,err end
  local directory,dirErr=self:_directory(true); if not directory then return nil,dirErr end
  local name=hash..".wav"; local path=directory.."/"..name
  local function existing()
    local mode,modeErr=self:_mode(path); if modeErr then return nil,modeErr end
    if mode==nil then return false end
    if mode~="file" then return nil,"The cached sound is not a regular file; choose another sound." end
    local saved=self:_read(path)
    if saved~=bytes then return nil,"The cached sound does not match its checksum; choose another sound." end
    return true
  end
  local present,presentErr=existing()
  if present==nil then return nil,presentErr end
  if present then return path,nil,name end
  -- mkdir reserves a new directory without opening/truncating an existing
  -- file. Hard-link publication is atomic and cannot replace a destination.
  -- If links are unavailable, only generated built-ins may remain in this
  -- reserved namespace. Custom imports must publish their hash.wav directly.
  local builtin=notes[builtinId]~=nil
  local stage=builtin and directory.."/builtin-"..hash or path..".pending"
  local temporary=stage.."/sound.wav"
  if not succeeded(self.fs.mkdir,stage) then
    if builtin and self:_read(temporary)==bytes then return temporary,nil,name end
    return nil,"The audio cache is busy, changed, or unavailable; choose another sound."
  end
  local created=false
  local function cleanup()
    local mode=self:_mode(temporary)
    if created and mode=="file" then succeeded(self.os and self.os.remove,temporary) end
    succeeded(self.fs.rmdir,stage)
  end
  local safe=self:_parents(stage,false)
  local mode,modeErr=self:_mode(temporary)
  if not safe or mode~=nil or modeErr then cleanup(); return nil,"Could not safely stage the audio file." end
  local opened,file=pcall(self.io.open,temporary,"wb")
  if not opened or not file then cleanup(); return nil,"Could not save the custom audio file." end
  created=true
  local wrote=succeeded(function() return file:write(bytes) end)
  local closed=succeeded(function() return file:close() end)
  if not wrote or not closed or self:_read(temporary)~=bytes then cleanup(); return nil,"Could not verify the saved audio file." end
  local installed
  if self:_parents(directory,false) then installed=succeeded(self.fs.link,temporary,path,false) end
  -- Windows rename fails if the destination exists. Never use POSIX rename,
  -- which could silently replace a competing file between inspection and move.
  if not installed and package.config:sub(1,1)=="\\" then
    local occupied=self:_mode(path)
    if occupied==nil and self:_parents(directory,false) then installed=succeeded(self.os and self.os.rename,temporary,path) end
  end
  local verified,verifyErr=existing()
  if verified==false and builtin and self:_read(temporary)==bytes then return temporary,nil,name end
  cleanup()
  if not verified then return nil,verifyErr or "Could not safely install the audio file." end
  return path,nil,name
end
function Audio:chooseCustom()
  if type(self.invokeFileDialog)~="function" then return nil,"The WAV file chooser is unavailable." end
  local ok,path=pcall(self.invokeFileDialog,true,"Choose an autoroller alert WAV file (10 MiB / 60 seconds maximum)")
  if not ok then return nil,"Could not open the WAV file chooser." end
  if path==nil or path==false or path=="" then return nil,"cancelled" end
  local root,parts=pathParts(path)
  if not root or not parts[#parts]:lower():match("%.wav$") then return nil,"Choose a regular local .wav file." end
  local bytes,err=self:_read(path); if not bytes then return nil,err end
  local cached,cacheErr,name=self:_cache(bytes); if not cached then return nil,cacheErr end
  return {custom_file=name,custom_name=displayName(parts[#parts]) or "Custom sound.wav"}
end
function Audio:stop(preview)
  if type(self.stopSounds)~="function" then return nil,"Sound stopping is unavailable in this Mudlet installation." end
  local key=preview==true and keys.preview or keys.alert
  if not succeeded(self.stopSounds,{key=key,tag=key}) then return nil,"Could not stop the autoroller sound." end
  return true
end
function Audio:play(settings,preview)
  local config,err=Audio.validate(settings); if not config then return nil,err end
  if config.enabled==false and preview~=true then return false end
  if type(self.playSoundFile)~="function" then return nil,"Sound playback is unavailable in this Mudlet installation." end
  local path,duration,warning,usingCustom
  if config.sound=="custom" then
    local directory=self:_directory(false)
    if directory and config.custom_file then
      local candidate=directory.."/"..config.custom_file
      local bytes,_,seconds=self:_read(candidate)
      if bytes and digest(bytes)==config.custom_file:sub(1,64) then path,duration,usingCustom=candidate,seconds,true end
    end
    if not path then warning="Your custom sound is unavailable or changed. Playing Three-Tone; choose the WAV file again in audio settings." end
  end
  local function builtin(id)
    local bytes=self.generated[id]
    if not bytes then bytes=Audio.wav(id); self.generated[id]=bytes end
    local cached,cacheErr=self:_cache(bytes,id)
    if not cached then return nil,cacheErr end
    path,duration=cached,Audio.validateWav(bytes)
    return true
  end
  if not path then
    local prepared,cacheErr=builtin(config.sound=="custom" and "three_tone" or config.sound)
    if not prepared then return nil,cacheErr end
  end
  local key=preview==true and keys.preview or keys.alert
  -- Media mute is owned by Mudlet. Only relative volume is supplied, with one
  -- loop; repeating alerts are scheduled by the controller using the duration.
  local function playback()
    local stopped,stopErr=self:stop(preview)
    if not stopped then return nil,stopErr end
    if not succeeded(self.playSoundFile,{name=path,volume=config.volume,loops=1,key=key,tag=key}) then
      return nil,"Could not play the autoroller sound. Check Mudlet's media mute and sound settings.",true
    end
    return true
  end
  local played,playErr,rejected=playback()
  if not played and usingCustom and rejected then
    warning="Mudlet could not play your custom WAV file. Playing Three-Tone; choose another WAV file in audio settings."
    local prepared,cacheErr=builtin("three_tone")
    if not prepared then return nil,cacheErr end
    played,playErr=playback()
  end
  if not played then return nil,playErr end
  return true,warning,duration
end
return Audio

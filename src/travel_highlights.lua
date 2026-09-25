-- Pure text recognition. Positions are 1-based byte offsets in the original
-- ANSI-free server lines; rendering, colors, and console line lookup belong to
-- the caller. No game commands, output replacement, or Mudlet APIs are used.
local Travel={}; Travel.__index=Travel
local MAX_LINES,MAX_BYTES=4,2048
local nouns={
  door=true,doors=true,doorway=true,doorways=true,gate=true,gates=true,
  arch=true,arches=true,archway=true,archways=true,portal=true,portals=true,
  staircase=true,staircases=true,stairway=true,stairways=true,stairs=true,
  ladder=true,ladders=true,trapdoor=true,trapdoors=true,bridge=true,bridges=true,
  tunnel=true,tunnels=true,passage=true,passages=true,passageway=true,passageways=true,
  entrance=true,entrances=true,exit=true,exits=true,path=true,paths=true,
  shop=true,shops=true,store=true,stores=true,pawnshop=true,pawnshops=true,
  tavern=true,taverns=true,hole=true,holes=true,
}
local articles={a=true,an=true,the=true,some=true}
local prepositions={to=true,into=true,through=true,of=true,["in"]=true,on=true,at=true,
  from=true,["for"]=true,with=true,near=true,beside=true,under=true,behind=true,
  beyond=true,above=true,below=true,leading=true}
local verbs={guarding=true,blocking=true,holding=true,carrying=true,wearing=true,
  standing=true,sitting=true,waiting=true,watching=true,opens=true,closes=true,
  walks=true,runs=true,enters=true,leaves=true,arrives=true,goes=true,
  says=true,say=true,asks=true,ask=true,shouts=true,shout=true,
  whispers=true,whisper=true,tells=true,tell=true,sends=true,
  exclaims=true,yells=true,thinks=true,reports=true,reads=true,depicts=true,
  is=true,are=true,was=true,were=true,has=true,have=true,can=true,will=true}
local commands={look=true,enter=true,go=true,move=true,climb=true,
  buy=true,sell=true,value=true,list=true,inventory=true,
  obvious=true,hp=true,health=true}
local speech={say=true,says=true,ask=true,asks=true,shout=true,shouts=true,
  whisper=true,whispers=true,tell=true,tells=true,sends=true,exclaim=true,
  exclaims=true,yell=true,yells=true,thinks=true,reports=true}
local movement={walk=true,walks=true,run=true,runs=true,enter=true,enters=true,
  leave=true,leaves=true,arrives=true,move=true,moves=true,climb=true,climbs=true,
  follow=true,follows=true}

local function narrative(line)
  local clause=line:lower():match("^%s*([^.!?]*)") or ""
  local prefix={}
  for word in clause:gmatch("%a+") do
    if #prefix>0 and #prefix<=5 and (speech[word] or movement[word]) then return true end
    if word=="who" or word=="where" or word=="which" or word=="when" or word=="can" then return false end
    prefix[#prefix+1]=word
  end
  return false
end

local function trimRange(text,first,last)
  while first<=last and text:sub(first,first):match("%s") do first=first+1 end
  while last>=first and text:sub(last,last):match("%s") do last=last-1 end
  return first,last
end

local function boundary(line)
  if type(line)~="string" or #line>MAX_BYTES or not line:find("%S") then return true end
  -- Reject control sequences rather than stripping them and shifting offsets.
  if line:find("[%z\1-\8\11\12\14-\31\127\n]") or line:find("\r.") then return true end
  if line:find('[%[%]<>`=]') or line:match("^%s*[%w_%-']+%s*:") then return true end
  local first=line:match("^%s*(%S)")
  if first=="'" or first=="(" or first==")" or first=="*" or first=="#" then return true end
  local lower=line:lower()
  local word=lower:match("^%s*(%a+)")
  if commands[word] then return true end
  if word=="shop" or word=="store" then
    local following=lower:match("^%s*%a+%s+(%a+)")
    if not following or ({list=true,buy=true,sell=true,value=true,haggle=true,unlock=true})[following] then return true end
  end
  return narrative(line)
end

local quoteState

local function terminal(text)
  local first=text:find("%f[%a]is%s+here%.?%s*$")
  return first or text:find("%f[%a]are%s+here%.?%s*$")
end

local function tailStart(text,last)
  local first=1
  for index=1,last do
    if text:sub(index,index):match("[.!?]") then first=index+1 end
  end
  return trimRange(text,first,last)
end

-- A travel noun must be the head of the object, before a location/destination
-- modifier. Merely mentioning a gate in a merchant or loot description fails.
local function travelPhrase(text,first,last,initial)
  first,last=trimRange(text,first,last)
  local phrase=text:sub(first,last):lower()
  local words={}
  for word in phrase:gmatch("%S+") do words[#words+1]=word end
  if #words==0 or (initial and not articles[words[1]]) then return nil end
  local headStart=articles[words[1]] and 2 or 1
  local headEnd=#words
  for index=headStart,#words do
    local word=words[index]
    if verbs[word] then return nil end
    if prepositions[word] and headEnd==#words then headEnd=index-1 end
  end
  for index=headStart,headEnd do
    if articles[words[index]] then return nil end
  end
  if not nouns[words[headEnd]] then return nil end
  return {start=first,length=last-first+1,kind="portal"}
end

local function subjectSegments(text,first,last)
  local result={}
  local cursor,initial=first,true
  local function add(stop)
    local item=travelPhrase(text,cursor,stop,initial)
    if item then result[#result+1]=item end
    initial=false
  end
  local index=first
  while index<=last do
    if text:sub(index,index)=="," then
      add(index-1); cursor=index+1
    elseif text:sub(index,index+2):lower()=="and"
      and (index==first or text:sub(index-1,index-1):match("%s"))
      and text:sub(index+3,index+3):match("%s") then
      local nextWord=text:sub(index+4,last):lower():match("^%s*(%a+)")
      -- Preserve adjective pairs such as 'black and white door'. A new
      -- determiner or a bare travel noun starts the next list item.
      if articles[nextWord] or nouns[nextWord] or text:sub(cursor,index-1):match("^%s*$") then
        add(index-1); cursor=index+3; index=index+2
      end
    end
    index=index+1
  end
  add(last)
  return #result>0 and result or nil
end

local function parseConfirmed(line,initialQuote)
  if boundary(line) then return nil end
  local lower=line:lower()
  local ending=terminal(lower)
  if not ending then return nil end
  local first,last=tailStart(line,ending-1)
  if quoteState(line:sub(1,first-1),initialQuote) or line:sub(first,last):find('"',1,true)
    or line:sub(first,last):find("“",1,true) or line:sub(first,last):find("”",1,true)
    or line:sub(first,last):find("‘",1,true) then return nil end
  local article=lower:sub(first,last):match("^(%a+)%s")
  if not articles[article] then return nil end
  return subjectSegments(line,first,last)
end

function Travel.parse(line) return parseConfirmed(line) end

local function pendingStart(line,initialQuote)
  if boundary(line) or terminal(line:lower()) then return nil end
  local first,last=tailStart(line,#line)
  if quoteState(line:sub(1,first-1),initialQuote) then return nil end
  local phrase=line:sub(first,last):lower()
  local article=phrase:match("^(%a+)")
  if not articles[article] then return nil end
  return first
end

function Travel.new()
  return setmetatable({lines={},bytes=0,quote=nil,quoteLines=0,quoteBytes=0,rejected=false},Travel)
end

function Travel:reset()
  self.lines={}; self.bytes=0; self.quote=nil; self.quoteLines=0; self.quoteBytes=0
  self.rejected=false
  self.chatQuote=false; self.initialQuote=nil
end

quoteState=function(line,previous)
  -- Literal comparisons retain UTF-8 apostrophes and all original byte indexes.
  local quote=previous
  local index=1
  while index<=#line do
    if line:sub(index,index)=='"' then
      if quote=='"' then quote=nil elseif not quote then quote='"' end
    elseif line:sub(index,index+2)=="“" then
      if not quote then quote="”" end
      index=index+2
    elseif line:sub(index,index+2)=="”" then
      if quote=="”" then quote=nil end
      index=index+2
    end
    index=index+1
  end
  return quote
end

local function mappedSegments(parts,lines)
  local result={}
  for _,part in ipairs(parts) do
    local position=1
    for index,source in ipairs(lines) do
      local first=math.max(part.start,position)
      local last=math.min(part.start+part.length-1,position+#source-1)
      first,last=trimRange(source,first-position+1,last-position+1)
      if first<=last then
        local item={start=first,length=last-first+1,kind="portal",source_line=source}
        if index<#lines then item.line_offset=index-#lines end
        result[#result+1]=item
      end
      position=position+#source+1
    end
  end
  return #result>0 and result or nil
end

function Travel:onLine(line)
  if type(line)~="string" or #line>MAX_BYTES or not line:find("%S") then self:reset(); return nil end
  -- Do not mistake the middle of a wrapped quotation for standalone room text.
  local initialQuote
  if self.quote then
    local oldQuote=self.quote
    local chat=self.chatQuote
    local count,bytes=self.quoteLines+1,self.quoteBytes+#line+1
    self:reset()
    if not line:find("[%[%]<>]") and count<=MAX_LINES and bytes<=MAX_BYTES then
      self.quote=quoteState(line,oldQuote); self.quoteLines=count; self.quoteBytes=bytes
      self.chatQuote=chat
      if not self.quote and not chat then initialQuote=oldQuote end
    end
    if not initialQuote then return nil end
  end
  local quote=quoteState(line,initialQuote)
  if self.rejected then
    self:reset()
    if line:match("^%s*%l") and not boundary(line) then return nil end
  end
  if boundary(line) then
    self:reset()
    if quote then self.quote=quote; self.quoteLines=1; self.quoteBytes=#line end
    self.chatQuote=true
    if not line:find("[.!?]%s*$") then self.rejected=true end
    return nil
  end
  if quote then
    self:reset(); self.quote=quote; self.quoteLines=1; self.quoteBytes=#line; return nil
  end
  local previous=self.lines[#self.lines]
  local beginsArticle=articles[line:lower():match("^%s*(%a+)")]
  local lastWord=previous and previous:lower():match("(%a+)%s*$")
  -- A fresh subject without a preceding list separator is a new clause.
  if previous and beginsArticle and line:match("^%s*%u") and not previous:lower():match(",%s*$")
    and lastWord~="and" and not prepositions[lastWord] then self:reset() end
  if #self.lines>=MAX_LINES or self.bytes+#line+(#self.lines>0 and 1 or 0)>MAX_BYTES then self:reset() end
  local lines={}
  for index,source in ipairs(self.lines) do lines[index]=source end
  lines[#lines+1]=line
  local joined=table.concat(lines," ")
  if terminal(joined:lower()) then
    local parts=parseConfirmed(joined,self.initialQuote or initialQuote)
    self:reset()
    return parts and mappedSegments(parts,lines) or nil
  end
  -- A completed unrelated sentence ends the pending clause. Only the current
  -- line may seed a new candidate; no sliding window revives stale fragments.
  if line:find("[.!?]") then lines={line}; joined=line; self.initialQuote=nil end
  if pendingStart(joined,self.initialQuote or initialQuote) then
    self.lines=lines; self.bytes=#joined; self.initialQuote=self.initialQuote or initialQuote
  else
    self:reset()
    if pendingStart(line,initialQuote) then self.lines={line}; self.bytes=#line; self.initialQuote=initialQuote end
  end
  return nil
end

return Travel

local Diagnostics={}; Diagnostics.__index=Diagnostics
local function clean(value,limit)
  value=tostring(value==nil and "none" or value):gsub("[%z\1-\31\127]"," "):gsub("%s+"," ")
  limit=limit or 240; return #value>limit and value:sub(1,limit).."..." or value
end
local function boolean(value) return value==true and "true" or "false" end
function Diagnostics.new(version,edition,clock) return setmetatable({version=version,edition=edition,clock=clock or os.time,events={}},Diagnostics) end
function Diagnostics:record(kind,message)
  self.events[#self.events+1]={time=self.clock(),kind=clean(kind,40),message=clean(message,300)}
  while #self.events>20 do table.remove(self.events,1) end
end
function Diagnostics:render(context)
  context=type(context)=="table" and context or {}; local settings=context.settings or {}; local transitions=settings.transition_submaps or {}
  local lines={"DGHUD mapper diagnostic v1","generated_epoch="..clean(self.clock(),24),"hud_version="..clean(self.version,32),"edition="..clean(self.edition,16),"mudlet_version="..clean(context.mudlet_version,40),"mapper_enabled="..boolean(context.enabled),"current_room="..clean(context.current_room,24),"owned_room_count="..clean(context.owned_room_count,24),"owned_area_count="..clean(context.owned_area_count,24),"pending_cleanup="..clean(context.pending_cleanup,48),"walking="..boolean(context.walking),"pending_automap="..boolean(context.pending_automap),"pending_special="..boolean(context.pending_special),"last_status="..clean(context.last_status,300),"last_error="..clean(context.last_error,300),"walk_timeout="..clean(settings.walk_timeout,16),"special_timeout="..clean(settings.special_timeout,16)}
  for _,key in ipairs({"gate","portal","door","arch","path","other"}) do lines[#lines+1]="submap_"..key.."="..boolean(transitions[key]~=false) end
  lines[#lines+1]="events="..tostring(#self.events); for index,event in ipairs(self.events) do lines[#lines+1]=string.format("event_%02d=%s|%s|%s",index,clean(event.time,24),event.kind,event.message) end
  lines[#lines+1]="privacy=No credentials, chat, room descriptions, character name, IP address, or command history included."
  return table.concat(lines,"\n").."\n"
end
return Diagnostics

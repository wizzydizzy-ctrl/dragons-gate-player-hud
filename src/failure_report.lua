local FailureReport={}; FailureReport.__index=FailureReport
local LIMITS={events=20,message=500,context_fields=24,context_value=160,payload=16000}
local ALLOWED_CONTEXT={operation=true,stage=true,scope=true,http_status=true,map_scope=true,room_count=true,catalog_schema=true,mudlet_version=true}
local function sanitize(value,limit)
  value=tostring(value==nil and "unknown" or value):gsub("\27%[[%d;]*[A-Za-z]",""):gsub("[%z\1-\31\127]"," ")
  value=value:gsub("https?://[^%s]+","[url removed]"):gsub("[%w%._%%+%-]+@[%w%.%-]+%.[A-Za-z][A-Za-z]+","[email removed]"):gsub("%f[%d]%d+%.%d+%.%d+%.%d+%f[%D]","[ip removed]")
  value=value:gsub("[A-Za-z]:[\\/][^%s]+","[path removed]"):gsub("/[Uu]sers/[^%s]+","[path removed]")
  value=value:gsub("[Tt]oken%s*[:=]%s*[^%s]+","token=[redacted]"):gsub("[Aa]uthori[sz]ation%s*[:=]%s*[^%s]+","authorization=[redacted]"):gsub("[Aa]pi[_%-]?[Kk]ey%s*[:=]%s*[^%s]+","api_key=[redacted]"):gsub("[Pp]assword%s*[:=]%s*[^%s]+","password=[redacted]")
  value=value:gsub('"[^"\n]-"','"[quoted text removed]"'):gsub("%s+"," "):match("^%s*(.-)%s*$") or ""; limit=limit or LIMITS.message
  return #value>limit and value:sub(1,limit).."..." or value
end
local function safeContext(context)
  local out={}; local count=0; if type(context)~="table" then return out end
  for key,value in pairs(context) do if ALLOWED_CONTEXT[key] and (type(value)=="string" or type(value)=="number" or type(value)=="boolean") and count<LIMITS.context_fields then out[key]=sanitize(value,LIMITS.context_value); count=count+1 end end
  return out
end
function FailureReport.new(options) options=type(options)=="table" and options or {}; return setmetatable({version=sanitize(options.version,32),edition=sanitize(options.edition,16),clock=options.clock or os.time,save=options.save,submit=options.submit,events={},last=nil,submitting=false},FailureReport) end
function FailureReport:build(category,message,context)
  local report={format="DGHUD-failure-report",schema=1,generated_epoch=tonumber(self.clock()) or 0,hud_version=self.version,edition=self.edition,category=sanitize(category,48),message=sanitize(message),context=safeContext(context),events={}}
  for index,event in ipairs(self.events) do report.events[index]={epoch=event.epoch,category=event.category,message=event.message} end; return report
end
function FailureReport:record(category,message,context)
  local event={epoch=tonumber(self.clock()) or 0,category=sanitize(category,48),message=sanitize(message)}; self.events[#self.events+1]=event; while #self.events>LIMITS.events do table.remove(self.events,1) end
  local report=self:build(category,message,context); self.last=report; if type(self.save)=="function" then pcall(self.save,report) end; return report
end
function FailureReport:submitReport(report,done)
  report=report or self.last; if type(report)~="table" then return nil,"no failure report is available" end; if self.submitting then return nil,"failure report submission is already running" end; if type(self.submit)~="function" then return nil,"anonymous failure reporting is unavailable" end
  self.submitting=true; local settled=false; local function finish(result,err) if settled then return end; settled=true; self.submitting=false; if type(done)=="function" then pcall(done,result,err) end end
  local ok,started,err=pcall(self.submit,report,finish); if not ok then finish(nil,sanitize(started)); return nil,sanitize(started) end; if not started then finish(nil,err); return nil,err end; return true
end
function FailureReport:captureAndSubmit(category,message,context,done) local report=self:record(category,message,context); local started,err=self:submitReport(report,done); return report,started,err end
function FailureReport:lastReport() return self.last end
FailureReport.sanitize=sanitize; FailureReport.limits=LIMITS
return FailureReport

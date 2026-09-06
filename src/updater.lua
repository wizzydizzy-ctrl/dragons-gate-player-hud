local SHA256=require("sha256"); local Release=require("release")
local Updater={}; Updater.__index=Updater
local function errorMessage(value) local text=tostring(value or "unknown error"); return text:match(":%d+:%s*(.*)$") or text end
function Updater.new(adapter,settings) return setmetatable({adapter=adapter,settings=settings or {},lock=nil,expected_path=nil},Updater) end
local function updateNow(self)
  if self.adapter.updateClock then return self.adapter:updateClock() end
  return os.time()
end
function Updater:beginTiming()
  self.update_started_at=updateNow(self)
end
function Updater:stage(name)
  if not self.update_started_at then self:beginTiming() end
  local elapsed=math.max(0,updateNow(self)-self.update_started_at)
  if self.adapter.reportUpdateStage then self.adapter:reportUpdateStage(name,elapsed) end
end
function Updater:acquire(operation) if self.lock then return nil,self.lock.." already in progress" end; self.lock=operation; return true end
function Updater:release() self.lock=nil; self.expected_path=nil; self.refresh_after_install=nil; self.update_started_at=nil end
function Updater:acceptDownload(path) return type(path)=="string" and path==self.expected_path end
function Updater:installVerified(payload,expected)
  if type(payload)~="string" or SHA256.hex(payload)~=tostring(expected):lower() then return nil,"package checksum mismatch" end
  if not self.adapter.replacePackage then return nil,"package adapter unavailable" end
  local ok,err=self.adapter:replacePackage(payload,"DragonsGateHUD"); if not ok then return nil,err or "package installation failed" end
  if self.adapter.healthCheck then local healthy,healthErr=self.adapter:healthCheck(); if not healthy then if self.adapter.rollback then self.adapter:rollback("DragonsGateHUD") end; return nil,healthErr or "post-install health check failed" end end
  return true
end
function Updater:installVerifiedAsync(payload,expected,done,preverified)
  done=done or function() end
  if type(payload)~="string" or (preverified~=true and SHA256.hex(payload)~=tostring(expected):lower()) then done(nil,"package checksum mismatch"); return nil,"package checksum mismatch" end
  if not self.adapter.replacePackageAsync then done(nil,"package adapter unavailable"); return nil,"package adapter unavailable" end
  self.adapter:replacePackageAsync(payload,"DragonsGateHUD",function(ok,err)
    if not ok then
      local message=err or "package installation failed"
      if self.adapter.rollbackAsync then self.adapter:rollbackAsync("DragonsGateHUD",function(restored,rollbackErr)
        if not restored and rollbackErr then message=message.."; rollback failed: "..tostring(rollbackErr) end
        done(nil,message)
      end) else done(nil,message) end
      return
    end
    if self.adapter.healthCheck then
      local healthy,healthErr=self.adapter:healthCheck()
      if not healthy then
        local message=healthErr or "post-install health check failed"
        if self.adapter.rollbackAsync then self.adapter:rollbackAsync("DragonsGateHUD",function() done(nil,message) end)
        else done(nil,message) end
        return
      end
    end
    if self.refresh_after_install and self.adapter.refreshCharacterData then self.adapter:refreshCharacterData() end
    done(true)
  end)
  return true
end
function Updater:validateManifest(manifest)
  local github=self.settings.github or {}; local update=self.settings.update or {}
  local valid,why=Release.validateManifest(manifest,{owner=github.owner,repository=github.repository,package_limit=update.package_limit})
  if not valid then return nil,why end
  local running=self.adapter.mudletVersion and self.adapter:mudletVersion() or nil
  return Release.validateMinimumMudlet(manifest.minimum_mudlet,running)
end
function Updater:check()
  local ok,err=self:acquire("check"); if not ok then return nil,err end
  if not self.adapter.fetchManifest then self:release(); return nil,"manifest adapter unavailable" end
  local success,result=pcall(self.adapter.fetchManifest,self.adapter,self.settings); self:release(); if not success then return nil,result end; return result
end
function Updater:update(done,validatedManifest,manifestRaw)
  local ok,err=self:acquire("update"); if not ok then return nil,err end
  if not self.adapter.startUpdate then self:release(); return nil,"update adapter unavailable" end
  if not self.update_started_at then self:beginTiming() end
  self.refresh_after_install=self.adapter.isCharacterActive and self.adapter:isCharacterActive() or false
  local completed=false
  local function finish(updated,message)
    if completed then return end; completed=true
    if not updated and message and self.adapter.reportUpdateFailure then self.adapter:reportUpdateFailure(message) end
    self:release(); if done then done(updated,message) end
  end
  local success,result,message=pcall(self.adapter.startUpdate,self.adapter,self,finish,validatedManifest,manifestRaw); if not success then self:release(); return nil,result end
  if result==nil then self:release(); return nil,message end; return true
end
function Updater:checkAtCharacterEntry(done)
  done=done or function() end
  local ok,err=self:acquire("startup check"); if not ok then return nil,err end
  self:beginTiming(); self:stage("Checking")
  if not self.adapter.checkLatestAsync then self:release(); done(false,"manifest adapter unavailable"); return nil,"manifest adapter unavailable" end
  local completed=false
  local function finish(updated,message)
    if completed then return end; completed=true
    self:release(); done(updated==true,message)
  end
  local function checked(manifest,message,manifestRaw)
    if completed then return end
    if not manifest then
      if self.adapter.reportUpdateCheckFailure then self.adapter:reportUpdateCheckFailure(message or "version check failed") end
      finish(false,message or "version check failed"); return
    end
    local valid,why=self:validateManifest(manifest)
    if not valid then
      if self.adapter.reportUpdateCheckFailure then self.adapter:reportUpdateCheckFailure(why) end
      finish(false,why); return
    end
    local current=self.settings.version
    local compared,comparison=pcall(Release.compareVersions,manifest.version,current)
    if not compared then
      local whyCompare="installed version is invalid"
      if self.adapter.reportUpdateCheckFailure then self.adapter:reportUpdateCheckFailure(whyCompare) end
      finish(false,whyCompare); return
    end
    if comparison<=0 then finish(false); return end
    self.lock=nil
    local started,startErr=self:update(function(updated,updateErr) finish(updated,updateErr) end,manifest,manifestRaw)
    if not started then finish(false,startErr) end
  end
  local callOk,started,startErr=pcall(self.adapter.checkLatestAsync,self.adapter,self,checked)
  if not callOk then startErr=errorMessage(started); started=nil end
  if started==nil and not completed then
    if self.adapter.reportUpdateCheckFailure then self.adapter:reportUpdateCheckFailure(startErr or "version check failed") end
    finish(false,startErr or "version check failed"); return nil,startErr
  end
  return true
end
function Updater:cancel() if self.adapter.cancelUpdate then self.adapter:cancelUpdate() end; self:release(); return true end
return Updater

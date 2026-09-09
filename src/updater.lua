local SHA256; local Release=require("release")
local function sha256Hex(payload)
  if not SHA256 then SHA256=require("sha256") end
  return SHA256.hex(payload)
end
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
  if type(payload)~="string" or sha256Hex(payload)~=tostring(expected):lower() then return nil,"package checksum mismatch" end
  if not self.adapter.replacePackage then return nil,"package adapter unavailable" end
  local ok,err=self.adapter:replacePackage(payload,"DragonsGateHUD"); if not ok then return nil,err or "package installation failed" end
  if self.adapter.healthCheck then local healthy,healthErr=self.adapter:healthCheck(); if not healthy then if self.adapter.rollback then self.adapter:rollback("DragonsGateHUD") end; return nil,healthErr or "post-install health check failed" end end
  return true
end
function Updater:installVerifiedAsync(payload,expected,done,preverified)
  done=done or function() end
  if type(payload)~="string" or (preverified~=true and sha256Hex(payload)~=tostring(expected):lower()) then done(nil,"package checksum mismatch"); return nil,"package checksum mismatch" end
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
function Updater:check(done)
  done=done or function() end
  local ok,err=self:acquire("check"); if not ok then return nil,err end
  if not self.adapter.checkLatestAsync then self:release(); done(nil,"manifest adapter unavailable"); return nil,"manifest adapter unavailable" end
  local completed=false
  local function finish(result,message) if completed then return end; completed=true; self:release(); done(result,message) end
  local function checked(manifest,message)
    if not manifest then finish(nil,message or "version check failed"); return end
    local valid,why=self:validateManifest(manifest); if not valid then finish(nil,why); return end
    local compared,comparison=pcall(Release.compareVersions,manifest.version,self.settings.version)
    if not compared then finish(nil,"installed version is invalid"); return end
    local current=comparison<=0
    if self.adapter.reportVersionStatus then self.adapter:reportVersionStatus(self.settings.version,manifest.version,current) end
    finish({installed=self.settings.version,latest=manifest.version,current=current})
  end
  local callOk,started,startErr=pcall(self.adapter.checkLatestAsync,self.adapter,self,checked)
  if not callOk then startErr=errorMessage(started); started=nil end
  if started==nil and not completed then finish(nil,startErr or "version check failed"); return nil,startErr end
  return true
end
function Updater:update(done,validatedManifest,manifestRaw)
  local ok,err=self:acquire("update"); if not ok then return nil,err end
  if not self.update_started_at then self:beginTiming() end
  self.refresh_after_install=self.adapter.isCharacterActive and self.adapter:isCharacterActive() or false
  local completed=false
  local function finish(updated,message)
    if completed then return end; completed=true
    if not updated and message and self.adapter.reportUpdateFailure then self.adapter:reportUpdateFailure(message) end
    self:release(); if done then done(updated,message) end
  end
  local function install(manifest,raw)
    if not self.adapter.startUpdate then finish(false,"update adapter unavailable"); return nil,"update adapter unavailable" end
    local success,result,message=pcall(self.adapter.startUpdate,self.adapter,self,finish,manifest,raw)
    if not success then finish(false,result); return nil,result end
    if result==nil then finish(false,message); return nil,message end
    return true
  end
  if validatedManifest then return install(validatedManifest,manifestRaw) end
  if not self.adapter.checkLatestAsync then finish(false,"manifest adapter unavailable"); return nil,"manifest adapter unavailable" end
  self:stage("Checking")
  local function checked(manifest,message,raw)
    if not manifest then finish(false,message or "version check failed"); return end
    local valid,why=self:validateManifest(manifest); if not valid then finish(false,why); return end
    local compared,comparison=pcall(Release.compareVersions,manifest.version,self.settings.version)
    if not compared then finish(false,"installed version is invalid"); return end
    if comparison<=0 then
      if self.adapter.reportVersionStatus then self.adapter:reportVersionStatus(self.settings.version,manifest.version,true) end
      finish(false); return
    end
    install(manifest,raw)
  end
  local callOk,started,startErr=pcall(self.adapter.checkLatestAsync,self.adapter,self,checked)
  if not callOk then startErr=errorMessage(started); started=nil end
  if started==nil and not completed then finish(false,startErr or "version check failed"); return nil,startErr end
  return true
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
    -- Login checks must never replace the running package. Mudlet can destroy
    -- callbacks owned by a package while uninstalling it, which can leave the
    -- profile without a HUD if activation fails. Report the available version
    -- and keep the verified current HUD running until the player explicitly
    -- uses `dghud update`.
    if self.adapter.reportVersionStatus then self.adapter:reportVersionStatus(current,manifest.version,false) end
    finish(false,"update available; run dghud update")
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

local Release={}
local function versionParts(value) local a,b,c=tostring(value or ""):match("^v?(%d+)%.(%d+)%.(%d+)$"); if not a then return nil end; return {tonumber(a),tonumber(b),tonumber(c)} end
function Release.version(value)
  if type(value)=="table" then
    local major=value.major or value[1]; local minor=value.minor or value[2]; local patch=value.patch or value.revision or value[3]
    if tonumber(major) and tonumber(minor) and tonumber(patch) then return tostring(major).."."..tostring(minor).."."..tostring(patch) end
    return nil
  end
  return tostring(value or ""):match("v?(%d+%.%d+%.%d+)")
end
function Release.compareVersions(a,b) local x,y=versionParts(a),versionParts(b); assert(x and y,"invalid semantic version"); for i=1,3 do if x[i]<y[i] then return -1 elseif x[i]>y[i] then return 1 end end; return 0 end
function Release.validateMinimumMudlet(minimum,running)
  local actual=Release.version(running); if not actual then return true end
  local ok,comparison=pcall(Release.compareVersions,actual,minimum); if not ok then return nil,"invalid Mudlet compatibility version" end
  if comparison<0 then return nil,"Mudlet "..actual.." is older than required version "..tostring(minimum) end
  return true
end
function Release.validateAssetUrl(url,owner,repository,version)
  if type(url)~="string" or not url:match("^https://") then return nil,"asset URL must use HTTPS" end
  if not versionParts(version) then return nil,"invalid release version" end
  local expected="https://github.com/"..tostring(owner).."/"..tostring(repository).."/releases/download/v"..tostring(version).."/DragonsGateHUD.mpackage"
  if url~=expected then return nil,"asset URL is outside the configured versioned release" end
  return true
end
function Release.validateManifest(manifest,policy)
  if type(manifest)~="table" or type(policy)~="table" then return nil,"manifest and policy are required" end
  if manifest.package~="DragonsGateHUD" then return nil,"unexpected package identity" end
  if not versionParts(manifest.version) or not versionParts(manifest.minimum_mudlet) then return nil,"invalid version" end
  if manifest.view_schema~=nil and (tonumber(manifest.view_schema)~=manifest.view_schema or manifest.view_schema<1 or manifest.view_schema%1~=0) then return nil,"invalid view schema" end
  if type(manifest.sha256)~="string" or not manifest.sha256:match("^[0-9a-fA-F]+$") or #manifest.sha256~=64 then return nil,"invalid SHA-256" end
  local size=tonumber(manifest.archive_size); if not size or size<1 or size>(policy.package_limit or 10485760) then return nil,"archive exceeds size policy" end
  local ok,err=Release.validateAssetUrl(manifest.archive_url,policy.owner,policy.repository,manifest.version); if not ok then return nil,err end
  return true
end
return Release

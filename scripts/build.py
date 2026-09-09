#!/usr/bin/env python3
import argparse, hashlib, html, json, re, zipfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
MODULES=['defaults','command_parser','command_collector','game_clock','chat_parser','chat_history','chat_storage','chat_controller','output_colorizer','posture_tracker','needs_tracker','autoroller','navigation','mapper_model','map_adapter','map_transfer','map_catalog','map_collections','map_cleanup','map_diagnostics','failure_report','automapper','special_transition','map_walker','state','settings','sha256','release','events','layout','view','mudlet_adapter','main','updater']
def source_version():
    match=re.search(r'\bversion\s*=\s*["\']([^"\']+)["\']',(ROOT/'src/defaults.lua').read_text())
    if not match: raise ValueError('could not determine defaults.version')
    return match.group(1)
def script_node(name,code):
    return f'''<Script isActive="yes" isFolder="no"><name>{html.escape(name)}</name><packageName>DragonsGateHUD</packageName><script>{html.escape(code)}</script><eventHandlerList/></Script>'''
def recovery_script_node(code):
    return f'''<Script isActive="yes" isFolder="no"><name>DGHUD Recovery Runtime</name><packageName>DGHUDRecovery</packageName><script>{html.escape(code)}</script><eventHandlerList/></Script>'''
def runtime_source():
    readiness='DGHUD = DGHUD or {}\nDGHUD.healthCheck = function() return nil, "HUD startup is still loading" end'
    module_loaders=[]
    for module in MODULES:
        code=(ROOT/'src'/f'{module}.lua').read_text()
        module_loaders.append(f'package.preload["{module}"] = function(...)\n{code}\nend')
    return '\n'.join([readiness,*module_loaders,(ROOT/'src/entry.lua').read_text()])
def bootstrap_code():
    return '''DGHUD = DGHUD or {}
DGHUD.healthCheck = function() return nil, "HUD startup is still loading" end
local path=getMudletHomeDir().."/DragonsGateHUD/DGHUDRuntime.lua"
local file,openErr=io.open(path,"rb")
if not file then error("DGHUD runtime resource is unavailable: "..tostring(openErr),0) end
local payload=file:read("*a"); file:close()
if type(payload)~="string" or #payload<1 or #payload>2097152 then error("DGHUD runtime resource has an invalid size",0) end
local loader=loadstring or load
local chunk,loadErr=loader(payload,"@"..path)
if not chunk then error("DGHUD runtime could not be loaded: "..tostring(loadErr),0) end
local ok,runErr=pcall(chunk)
if not ok then error("DGHUD runtime failed: "..tostring(runErr),0) end'''
def recovery_code(owner,repository,version):
    url=f'https://github.com/{owner}/{repository}/releases/latest/download/DragonsGateHUD.mpackage'
    return f'''local previous=rawget(_G,"DGHUDRecovery")
local runtime={{version={version!r}}}
local function recover()
if runtime.running then cecho("\\n<yellow>[DGHUD Recovery]<reset> Recovery is already running.\\n"); return end
runtime.running=true
local url={url!r}
local base=getMudletHomeDir().."/DGHUDUpdater"; local recovery=base.."/recovery"
pcall(function() lfs.mkdir(base); lfs.mkdir(recovery) end)
local path=recovery.."/DragonsGateHUD.mpackage"
local handlers={{}}; local timers={{}}; local timeout
local function stopWatchers() for _,id in ipairs(handlers) do killAnonymousEventHandler(id) end; handlers={{}}; if timeout then killTimer(timeout); timeout=nil end end
local function finish() stopWatchers(); for _,id in ipairs(timers) do killTimer(id) end; timers={{}}; runtime.running=false end
local function fail(message) finish(); cecho("\\n<red>[DGHUD Recovery]<reset> "..tostring(message).."\\n") end
local function hasHUDPackage() for _,name in ipairs(getPackages() or {{}}) do if name=="DragonsGateHUD" then return true end end; return false end
handlers[#handlers+1]=registerAnonymousEventHandler("sysDownloadError",function(_,message,failedUrl) if failedUrl==url then fail("Download failed: "..tostring(message)) end end)
handlers[#handlers+1]=registerAnonymousEventHandler("sysDownloadDone",function(_,downloaded)
  if downloaded~=path then return end; stopWatchers(); cecho("\\n<gold>[DGHUD Recovery]<reset> Replacing only the DragonsGateHUD package…\\n")
  local retired=rawget(_G,"DGHUD")
  local function clearHandoff() local hud=rawget(_G,"DGHUD"); if hud==retired and type(hud)=="table" then hud._update_reinstall_pending=nil; if type(hud.controller)=="table" then hud.controller.update_handoff=nil; hud.controller.update_preserve_view=nil end end end
  local function awaitHealthy(remaining)
    local hud=rawget(_G,"DGHUD"); local healthy=false
    if hasHUDPackage() and type(hud)=="table" and hud~=retired and type(hud.healthCheck)=="function" then local ok,value=pcall(hud.healthCheck); healthy=ok and value==true end
    if healthy then finish(); cecho("\\n<green>[DGHUD Recovery]<reset> Reinstalled and verified DragonsGateHUD. Your personal Mudlet content was preserved.\\n"); return end
    if remaining<=0 then clearHandoff(); fail("Reinstall was accepted, but the HUD did not start. Close and reopen this profile, then run dghud recover again."); return end
    timers[#timers+1]=tempTimer(0.25,function() awaitHealthy(remaining-1) end)
  end
  local function installClean() local installed=installPackage(path); if installed==nil then clearHandoff(); fail("Reinstall failed. Close and reopen this profile, then run dghud recover again."); return end; awaitHealthy(120) end
  local function removeThenInstall(remaining)
    if not hasHUDPackage() then installClean(); return end
    local hud=rawget(_G,"DGHUD"); if type(hud)=="table" then hud._update_reinstall_pending=true; if type(hud.controller)=="table" then local controller=hud.controller; controller.update_handoff=true; local schema=hud.settings and tonumber(hud.settings.view_schema); if schema and controller.view and controller.view.root then hud._view_handoff={{schema=schema,view=controller.view}}; controller.update_preserve_view=true end end end
    if uninstallPackage("DragonsGateHUD") then installClean(); return end
    if remaining<=0 then clearHandoff(); fail("Could not remove the broken HUD package after waiting for Mudlet to finish saving."); return end
    timers[#timers+1]=tempTimer(0.10,function() removeThenInstall(remaining-1) end)
  end
  removeThenInstall(300)
end)
timeout=tempTimer(45,function() fail("Download timed out. Check your connection and run dghud recover again.") end)
cecho("\\n<gold>[DGHUD Recovery]<reset> Downloading a clean HUD package…\\n"); downloadFile(path,url)
end
runtime.run=recover
local aliasOK,alias=pcall(tempAlias,"^dghud recover$",recover)
if not aliasOK or type(alias)~="number" or alias<1 then
  cecho("\\n<red>[DGHUD Recovery]<reset> Emergency command registration failed. Reinstall DGHUDRecovery.mpackage.\\n")
  return
end
runtime.alias=alias
DGHUDRecovery=runtime
if type(previous)=="table" and type(previous.alias)=="number" and previous.alias~=alias then pcall(killAlias,previous.alias) end'''
def build(output,owner,repository,version):
    expected=source_version()
    if version != expected: raise ValueError(f'build version {version} does not match defaults.version {expected}')
    output.mkdir(parents=True,exist_ok=True)
    # Keep the large runtime out of Mudlet's saved profile XML. Package updates
    # otherwise force Mudlet to serialize more than half a megabyte of script
    # source during install. The small registered loader reads the runtime from
    # this package's own extracted, update-verified resource directory.
    runtime=runtime_source()
    nodes=[script_node('DGHUD Bootstrap',bootstrap_code())]
    xml=('''<?xml version="1.0" encoding="UTF-8"?><MudletPackage version="1.001"><PackageInfo><packageName>DragonsGateHUD</packageName><title>Dragons Gate GMCP HUD</title><version>'''+html.escape(version)+'''</version><author>Dragons Gate HUD contributors</author></PackageInfo><ScriptPackage><ScriptGroup isActive="yes" isFolder="yes"><name>DragonsGateHUD</name><packageName>DragonsGateHUD</packageName>'''+''.join(nodes)+'''</ScriptGroup></ScriptPackage></MudletPackage>''')
    package=output/'DragonsGateHUD.mpackage'
    with zipfile.ZipFile(package,'w',zipfile.ZIP_DEFLATED) as z:
        info=zipfile.ZipInfo('DragonsGateHUD.xml',(2026,1,1,0,0,0)); info.compress_type=zipfile.ZIP_DEFLATED; z.writestr(info,xml)
        info=zipfile.ZipInfo('DGHUDRuntime.lua',(2026,1,1,0,0,0)); info.compress_type=zipfile.ZIP_DEFLATED; z.writestr(info,runtime)
        info=zipfile.ZipInfo('config.lua',(2026,1,1,0,0,0)); info.compress_type=zipfile.ZIP_DEFLATED; z.writestr(info,'mpackage = "DragonsGateHUD"\n')
    digest=hashlib.sha256(package.read_bytes()).hexdigest()
    defaults_text=(ROOT/'src/defaults.lua').read_text()
    view_schema_match=re.search(r'\bview_schema\s*=\s*(\d+)',defaults_text)
    if not view_schema_match: raise ValueError('could not determine defaults.view_schema')
    manifest={'package':'DragonsGateHUD','version':version,'minimum_mudlet':'5.0.0','view_schema':int(view_schema_match.group(1)),'archive_url':f'https://github.com/{owner}/{repository}/releases/download/v{version}/DragonsGateHUD.mpackage','archive_size':package.stat().st_size,'sha256':digest}
    (output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    recovery_version='1.4.0'
    recovery_xml=('''<?xml version="1.0" encoding="UTF-8"?><MudletPackage version="1.001"><PackageInfo><packageName>DGHUDRecovery</packageName><title>DGHUD Emergency Recovery</title><version>'''+recovery_version+'''</version><author>Dragons Gate HUD contributors</author></PackageInfo><ScriptPackage><ScriptGroup isActive="yes" isFolder="yes"><name>DGHUDRecovery</name><packageName>DGHUDRecovery</packageName>'''+recovery_script_node(recovery_code(owner,repository,recovery_version))+'''</ScriptGroup></ScriptPackage></MudletPackage>''')
    with zipfile.ZipFile(output/'DGHUDRecovery.mpackage','w',zipfile.ZIP_DEFLATED) as z:
        info=zipfile.ZipInfo('DGHUDRecovery.xml',(2026,1,1,0,0,0)); info.compress_type=zipfile.ZIP_DEFLATED; z.writestr(info,recovery_xml)
        info=zipfile.ZipInfo('config.lua',(2026,1,1,0,0,0)); info.compress_type=zipfile.ZIP_DEFLATED; z.writestr(info,'mpackage = "DGHUDRecovery"\n')
def main():
    p=argparse.ArgumentParser(); p.add_argument('--output',type=Path,default=ROOT/'dist'); p.add_argument('--owner',default='GITHUB_OWNER'); p.add_argument('--repository',default='dragons-gate-hud'); p.add_argument('--version',default=source_version()); a=p.parse_args(); build(a.output,a.owner,a.repository,a.version)
if __name__=='__main__': main()

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
def recovery_alias_node(code):
    return f'''<Alias isActive="yes" isFolder="no"><name>DGHUD Emergency Recovery</name><packageName>DGHUDRecovery</packageName><script>{html.escape(code)}</script><command></command><regex>^dghud recover$</regex></Alias>'''
def recovery_code(owner,repository):
    url=f'https://github.com/{owner}/{repository}/releases/latest/download/DragonsGateHUD.mpackage'
    return f'''DGHUDRecovery = DGHUDRecovery or {{}}
if DGHUDRecovery.running then cecho("\\n<yellow>[DGHUD Recovery]<reset> Recovery is already running.\\n"); return end
DGHUDRecovery.running=true
local url={url!r}
local path=getMudletHomeDir().."/DGHUDRecovery-DragonsGateHUD.mpackage"
local handlers={{}}; local timeout
local function cleanup() for _,id in ipairs(handlers) do killAnonymousEventHandler(id) end; if timeout then killTimer(timeout) end; DGHUDRecovery.running=false end
local function fail(message) cleanup(); cecho("\\n<red>[DGHUD Recovery]<reset> "..tostring(message).."\\n") end
handlers[#handlers+1]=registerAnonymousEventHandler("sysDownloadError",function(_,message,failedUrl) if failedUrl==url then fail("Download failed: "..tostring(message)) end end)
handlers[#handlers+1]=registerAnonymousEventHandler("sysDownloadDone",function(_,downloaded)
  if downloaded~=path then return end; cleanup(); cecho("\\n<gold>[DGHUD Recovery]<reset> Replacing only the DragonsGateHUD package…\\n")
  local found=false; for _,name in ipairs(getPackages() or {{}}) do if name=="DragonsGateHUD" then found=true; break end end
  if found then
    if DGHUD then DGHUD._update_reinstall_pending=true; if DGHUD.controller then DGHUD.controller.update_handoff=true end end
    local removed=uninstallPackage("DragonsGateHUD")
    if removed==nil then if DGHUD then DGHUD._update_reinstall_pending=nil; if DGHUD.controller then DGHUD.controller.update_handoff=nil end end; fail("Could not remove the broken HUD package."); return end
  end
  tempTimer(0.15,function() local installed=installPackage(path); if installed==nil then cecho("\\n<red>[DGHUD Recovery]<reset> Reinstall failed. Close and reopen this profile, then run dghud recover again.\\n") else cecho("\\n<green>[DGHUD Recovery]<reset> Reinstalled DragonsGateHUD. Your personal content and saved DGHUD settings were preserved.\\n") end end)
end)
timeout=tempTimer(45,function() fail("Download timed out. Check your connection and run dghud recover again.") end)
cecho("\\n<gold>[DGHUD Recovery]<reset> Downloading a clean HUD package…\\n"); downloadFile(path,url)'''
def build(output,owner,repository,version):
    expected=source_version()
    if version != expected: raise ValueError(f'build version {version} does not match defaults.version {expected}')
    output.mkdir(parents=True,exist_ok=True)
    # Block updater success while Mudlet is between package registration and
    # full runtime activation. DGHUD Start replaces this loading gate only
    # after constructing the controller and then enforces start() success.
    readiness='DGHUD = DGHUD or {}\nDGHUD.healthCheck = function() return nil, "HUD startup is still loading" end'
    nodes=[script_node('DGHUD Install Readiness',readiness)]
    module_loaders=[]
    for module in MODULES:
        code=(ROOT/'src'/f'{module}.lua').read_text()
        module_loaders.append(f'package.preload["{module}"] = function(...)\n{code}\nend')
    # Mudlet pays a substantial registration cost per package Script object.
    # Keep all modules independently lazy-loaded while registering one loader.
    nodes.append(script_node('DGHUD Modules','\n'.join(module_loaders)))
    nodes.append(script_node('DGHUD Start',(ROOT/'src/entry.lua').read_text()))
    xml=('''<?xml version="1.0" encoding="UTF-8"?><MudletPackage version="1.001"><PackageInfo><packageName>DragonsGateHUD</packageName><title>Dragons Gate GMCP HUD</title><version>'''+html.escape(version)+'''</version><author>Dragons Gate HUD contributors</author></PackageInfo><ScriptPackage><ScriptGroup isActive="yes" isFolder="yes"><name>DragonsGateHUD</name><packageName>DragonsGateHUD</packageName>'''+''.join(nodes)+'''</ScriptGroup></ScriptPackage></MudletPackage>''')
    package=output/'DragonsGateHUD.mpackage'
    with zipfile.ZipFile(package,'w',zipfile.ZIP_DEFLATED) as z:
        info=zipfile.ZipInfo('DragonsGateHUD.xml',(2026,1,1,0,0,0)); info.compress_type=zipfile.ZIP_DEFLATED; z.writestr(info,xml)
    digest=hashlib.sha256(package.read_bytes()).hexdigest()
    defaults_text=(ROOT/'src/defaults.lua').read_text()
    view_schema_match=re.search(r'\bview_schema\s*=\s*(\d+)',defaults_text)
    if not view_schema_match: raise ValueError('could not determine defaults.view_schema')
    manifest={'package':'DragonsGateHUD','version':version,'minimum_mudlet':'5.0.0','view_schema':int(view_schema_match.group(1)),'archive_url':f'https://github.com/{owner}/{repository}/releases/download/v{version}/DragonsGateHUD.mpackage','archive_size':package.stat().st_size,'sha256':digest}
    (output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
    recovery_xml=('''<?xml version="1.0" encoding="UTF-8"?><MudletPackage version="1.001"><PackageInfo><packageName>DGHUDRecovery</packageName><title>DGHUD Emergency Recovery</title><version>1.0.0</version><author>Dragons Gate HUD contributors</author></PackageInfo><AliasPackage><AliasGroup isActive="yes" isFolder="yes"><name>DGHUDRecovery</name><packageName>DGHUDRecovery</packageName>'''+recovery_alias_node(recovery_code(owner,repository))+'''</AliasGroup></AliasPackage></MudletPackage>''')
    with zipfile.ZipFile(output/'DGHUDRecovery.mpackage','w',zipfile.ZIP_DEFLATED) as z:
        info=zipfile.ZipInfo('DGHUDRecovery.xml',(2026,1,1,0,0,0)); info.compress_type=zipfile.ZIP_DEFLATED; z.writestr(info,recovery_xml)
def main():
    p=argparse.ArgumentParser(); p.add_argument('--output',type=Path,default=ROOT/'dist'); p.add_argument('--owner',default='GITHUB_OWNER'); p.add_argument('--repository',default='dragons-gate-hud'); p.add_argument('--version',default=source_version()); a=p.parse_args(); build(a.output,a.owner,a.repository,a.version)
if __name__=='__main__': main()

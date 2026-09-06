#!/usr/bin/env python3
import argparse, hashlib, html, json, re, zipfile
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
MODULES=['defaults','command_parser','command_collector','game_clock','chat_parser','chat_history','chat_storage','chat_controller','output_colorizer','posture_tracker','autoroller','navigation','mapper_model','map_adapter','map_transfer','map_catalog','map_cleanup','map_diagnostics','failure_report','automapper','special_transition','map_walker','state','settings','sha256','release','events','layout','view','mudlet_adapter','main','updater']
def source_version():
    match=re.search(r'\bversion\s*=\s*["\']([^"\']+)["\']',(ROOT/'src/defaults.lua').read_text())
    if not match: raise ValueError('could not determine defaults.version')
    return match.group(1)
def script_node(name,code):
    return f'''<Script isActive="yes" isFolder="no"><name>{html.escape(name)}</name><packageName>DragonsGateHUD</packageName><script>{html.escape(code)}</script><eventHandlerList/></Script>'''
def build(output,owner,repository,version):
    expected=source_version()
    if version != expected: raise ValueError(f'build version {version} does not match defaults.version {expected}')
    output.mkdir(parents=True,exist_ok=True)
    nodes=[]
    for module in MODULES:
        code=(ROOT/'src'/f'{module}.lua').read_text()
        nodes.append(script_node('DGHUD Module - '+module,f'package.preload["{module}"] = function(...)\n{code}\nend'))
    nodes.append(script_node('DGHUD Start',(ROOT/'src/entry.lua').read_text()))
    xml=('''<?xml version="1.0" encoding="UTF-8"?><MudletPackage version="1.001"><PackageInfo><packageName>DragonsGateHUD</packageName><title>Dragons Gate GMCP HUD</title><version>'''+html.escape(version)+'''</version><author>Dragons Gate HUD contributors</author></PackageInfo><ScriptPackage><ScriptGroup isActive="yes" isFolder="yes"><name>DragonsGateHUD</name><packageName>DragonsGateHUD</packageName>'''+''.join(nodes)+'''</ScriptGroup></ScriptPackage></MudletPackage>''')
    package=output/'DragonsGateHUD.mpackage'
    with zipfile.ZipFile(package,'w',zipfile.ZIP_DEFLATED) as z:
        info=zipfile.ZipInfo('DragonsGateHUD.xml',(2026,1,1,0,0,0)); info.compress_type=zipfile.ZIP_DEFLATED; z.writestr(info,xml)
    digest=hashlib.sha256(package.read_bytes()).hexdigest()
    manifest={'package':'DragonsGateHUD','version':version,'minimum_mudlet':'5.0.0','archive_url':f'https://github.com/{owner}/{repository}/releases/download/v{version}/DragonsGateHUD.mpackage','archive_size':package.stat().st_size,'sha256':digest}
    (output/'manifest.json').write_text(json.dumps(manifest,indent=2)+'\n')
def main():
    p=argparse.ArgumentParser(); p.add_argument('--output',type=Path,default=ROOT/'dist'); p.add_argument('--owner',default='GITHUB_OWNER'); p.add_argument('--repository',default='dragons-gate-hud'); p.add_argument('--version',default=source_version()); a=p.parse_args(); build(a.output,a.owner,a.repository,a.version)
if __name__=='__main__': main()

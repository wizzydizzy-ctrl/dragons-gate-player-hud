import hashlib, json, re, subprocess, sys, tempfile, unittest, zipfile
from xml.etree import ElementTree
from pathlib import Path

ROOT=Path(__file__).resolve().parents[1]
class BuildTest(unittest.TestCase):
    def run_lua(self, source, cwd):
        completed=subprocess.run(['lua','-'],input=source,text=True,cwd=cwd,capture_output=True)
        self.assertEqual(completed.returncode,0,completed.stdout+completed.stderr)

    def test_build_emits_verified_owned_package(self):
        with tempfile.TemporaryDirectory() as td:
            subprocess.run([sys.executable,str(ROOT/'scripts/build.py'),'--output',td,'--owner','ricwall','--repository','dragons-gate-hud'],check=True)
            package=Path(td)/'DragonsGateHUD.mpackage'; manifest=json.loads((Path(td)/'manifest.json').read_text())
            recovery=Path(td)/'DGHUDRecovery.mpackage'; self.assertTrue(recovery.exists())
            with zipfile.ZipFile(recovery) as z:
                self.assertEqual(z.read('config.lua'),b'mpackage = "DGHUDRecovery"\n')
                recovery_xml=z.read('DGHUDRecovery.xml').decode()
                self.assertIn('<packageName>DGHUDRecovery</packageName>',recovery_xml)
                self.assertIn('<version>1.4.0</version>',recovery_xml)
                self.assertIn('local runtime={version=&#x27;1.4.0&#x27;}',recovery_xml)
                self.assertIn('^dghud recover$',recovery_xml)
                self.assertIn('pcall(tempAlias',recovery_xml)
                self.assertIn('runtime.alias=alias',recovery_xml)
                self.assertNotIn('<AliasPackage>',recovery_xml)
                self.assertIn('hud._update_reinstall_pending=true',recovery_xml)
                self.assertIn('https://github.com/ricwall/dragons-gate-hud/releases/latest/download/DragonsGateHUD.mpackage',recovery_xml)
                recovery_script=ElementTree.fromstring(recovery_xml).findtext('.//Script/script')
                self.assertIn('hud._view_handoff={schema=schema,view=controller.view}',recovery_script)
                self.assertIn('controller.update_preserve_view=true',recovery_script)
                self.assertIn('recovery.."/DragonsGateHUD.mpackage"',recovery_script)
                self.assertNotIn('tempTimer(0.15',recovery_script)
                self.assertIn('hud~=retired',recovery_script)
                self.assertIn('Reinstalled and verified DragonsGateHUD',recovery_script)
                self.assertIn('removeThenInstall(300)',recovery_script)
                self.assertNotIn('Reinstalled DragonsGateHUD.',recovery_script)
            self.assertEqual(manifest['package'],'DragonsGateHUD')
            self.assertEqual(manifest['view_schema'],1)
            self.assertEqual(manifest['sha256'],hashlib.sha256(package.read_bytes()).hexdigest())
            with zipfile.ZipFile(package) as z:
                names=z.namelist(); self.assertEqual(names,['DragonsGateHUD.xml','DGHUDRuntime.lua','config.lua'])
                self.assertEqual(z.read('config.lua'),b'mpackage = "DragonsGateHUD"\n')
                xml=z.read(names[0]).decode(); self.assertIn('<name>DragonsGateHUD</name>',xml)
                runtime=z.read('DGHUDRuntime.lua').decode()
                self.assertIn('DGHUD.start',runtime)
                self.assertNotIn('package.preload[&quot;layout&quot;]',xml)
                self.assertIn('package.preload["layout"]',runtime)
                self.assertIn('package.preload["chat_controller"]',runtime)
                self.assertNotIn('&lt;/green&gt;',xml)
                self.assertIn('[DGHUD Update]<reset> Installed version',runtime)
                self.assertIn('if not SHA256 then SHA256=require("sha256") end',runtime)
                self.assertIn('Adapter.prepareDataDirectory()',runtime)
                self.assertIn('/DGHUDData',runtime)
                root=ElementTree.fromstring(xml)
                scripts={node.findtext('name'):node.findtext('script') for node in root.findall('.//Script')}
                self.assertEqual(list(scripts),['DGHUD Bootstrap'])
                bootstrap=scripts['DGHUD Bootstrap']
                self.assertIn('/DragonsGateHUD/DGHUDRuntime.lua',bootstrap)
                self.assertIn('HUD startup is still loading',bootstrap)
                self.assertLess(len(xml),20000)
                probe_home=Path(td)/'bootstrap-probe'; probe_package=probe_home/'DragonsGateHUD'; probe_package.mkdir(parents=True)
                (probe_package/'DGHUDRuntime.lua').write_text('DGHUD_BOOTSTRAP_PROBE=true\n')
                self.run_lua('getMudletHomeDir=function() return '+json.dumps(str(probe_home))+' end\n'+bootstrap+'\nassert(DGHUD_BOOTSTRAP_PROBE)\n',td)
                entry=(ROOT/'src/entry.lua').read_text()
                self.assertTrue(runtime.endswith(entry))
                module_bundle=runtime[:-len(entry)]
                required=set()
                for path in (ROOT/'src').glob('*.lua'):
                    required.update(re.findall(r'require\(["\']([^"\']+)["\']\)',path.read_text()))
                bundled=set(re.findall(r'package\.preload\["([^"]+)"\]',module_bundle))
                self.assertEqual(required-bundled,set())
                self.run_lua('package.path=""; package.cpath=""\n'+module_bundle+'\nassert(require("main"))\n',td)

                self.assertIn('DGHUD startup failed:',entry)
                self.assertIn('tempTimer(0,maintainRecoveryCompanion)',entry)
                reload_probe='''
package.path=""; package.cpath=""
getMudletHomeDir=function() return "/profile" end
local generation=1
package.loaded["special_transition"]={generation=0}
package.preload["special_transition"]=function() return {generation=generation} end
package.preload["defaults"]=function() return {} end
package.preload["settings"]=function() return {resolve=function(defaults,user) return defaults,user end} end
package.preload["mudlet_adapter"]=function() return {new=function() return {} end} end
package.preload["main"]=function()
  local special=require("special_transition")
  return {
    new=function() return {special=special,start=function() return true end,shutdown=function() return true end} end,
    installChatApi=function() end,
  }
end
package.preload["updater"]=function() return {new=function() return {} end} end
package.preload["chat_storage"]=function() return {mudletApi=function() return {} end} end
local function run_entry()
ENTRY
end
run_entry()
assert(DGHUD.controller.special.generation==1,"entry retained stale special_transition on initial load")
generation=2
package.preload["special_transition"]=function() return {generation=generation} end
run_entry()
assert(DGHUD.controller.special.generation==2,"entry retained stale special_transition on reload")
'''.replace('ENTRY',entry)
                self.run_lua(reload_probe,td)

    def test_build_rejects_version_different_from_defaults(self):
        with tempfile.TemporaryDirectory() as td:
            completed=subprocess.run(
                [sys.executable,str(ROOT/'scripts/build.py'),'--output',td,'--owner','ricwall','--repository','dragons-gate-hud','--version','9.9.9'],
                text=True,capture_output=True,
            )
            self.assertNotEqual(completed.returncode,0)
            self.assertIn('does not match defaults.version',completed.stderr)
if __name__=='__main__': unittest.main()

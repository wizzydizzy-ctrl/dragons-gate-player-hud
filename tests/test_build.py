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
                recovery_xml=z.read('DGHUDRecovery.xml').decode()
                self.assertIn('<packageName>DGHUDRecovery</packageName>',recovery_xml)
                self.assertIn('^dghud recover$',recovery_xml)
                self.assertIn('https://github.com/ricwall/dragons-gate-hud/releases/latest/download/DragonsGateHUD.mpackage',recovery_xml)
            self.assertEqual(manifest['package'],'DragonsGateHUD')
            self.assertEqual(manifest['sha256'],hashlib.sha256(package.read_bytes()).hexdigest())
            with zipfile.ZipFile(package) as z:
                names=z.namelist(); self.assertEqual(names,['DragonsGateHUD.xml'])
                xml=z.read(names[0]).decode(); self.assertIn('<name>DragonsGateHUD</name>',xml); self.assertIn('DGHUD.start',xml)
                self.assertIn('package.preload[&quot;layout&quot;]',xml)
                self.assertIn('package.preload[&quot;chat_controller&quot;]',xml)
                self.assertNotIn('&lt;/green&gt;',xml)
                self.assertIn('[DGHUD Update]&lt;reset&gt; Installed version',xml)
                root=ElementTree.fromstring(xml)
                scripts={node.findtext('name'):node.findtext('script') for node in root.findall('.//Script')}
                self.assertLessEqual(len(scripts),3)
                module_bundle=scripts['DGHUD Modules']
                required=set()
                for path in (ROOT/'src').glob('*.lua'):
                    required.update(re.findall(r'require\(["\']([^"\']+)["\']\)',path.read_text()))
                bundled=set(re.findall(r'package\.preload\["([^"]+)"\]',module_bundle))
                self.assertEqual(required-bundled,set())
                self.run_lua('package.path=""; package.cpath=""\n'+module_bundle+'\nassert(require("main"))\n',td)

                entry=scripts['DGHUD Start']
                reload_probe='''
package.path=""; package.cpath=""
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

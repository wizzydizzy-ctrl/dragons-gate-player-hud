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
            defaults=(ROOT/'src/defaults.lua').read_text()
            owner=re.search(r'github\s*=\s*\{\s*owner="([^"]+)"',defaults).group(1)
            repository=re.search(r'github\s*=\s*\{[^}]*repository="([^"]+)"',defaults).group(1)
            subprocess.run([sys.executable,str(ROOT/'scripts/build.py'),'--output',td,'--owner',owner,'--repository',repository],check=True)
            self.assertEqual({path.name for path in Path(td).iterdir()},{'DragonsGateHUD.mpackage','DGHUDRecovery.mpackage','DGHUDMigration.mpackage','manifest.json'})
            package=Path(td)/'DragonsGateHUD.mpackage'; manifest=json.loads((Path(td)/'manifest.json').read_text())
            recovery=Path(td)/'DGHUDRecovery.mpackage'; self.assertTrue(recovery.exists())
            migration=Path(td)/'DGHUDMigration.mpackage'; self.assertTrue(migration.exists())
            with zipfile.ZipFile(recovery) as z:
                self.assertEqual(z.read('config.lua'),b'mpackage = "DGHUDRecovery"\n')
                recovery_xml=z.read('DGHUDRecovery.xml').decode()
                self.assertIn('<packageName>DGHUDRecovery</packageName>',recovery_xml)
                self.assertIn('<version>1.5.0</version>',recovery_xml)
                self.assertIn('local runtime={version=&#x27;1.5.0&#x27;}',recovery_xml)
                self.assertIn('^dghud recover$',recovery_xml)
                self.assertIn('pcall(tempAlias',recovery_xml)
                self.assertIn('runtime.alias=alias',recovery_xml)
                self.assertNotIn('<AliasPackage>',recovery_xml)
                self.assertIn('hud._update_reinstall_pending=true',recovery_xml)
                self.assertIn(f'https://github.com/{owner}/{repository}/releases/latest/download/DragonsGateHUD.mpackage',recovery_xml)
                recovery_script=ElementTree.fromstring(recovery_xml).findtext('.//Script/script')
                recovery_probe=Path(td)/'recovery-probe.lua'; recovery_probe.write_text(recovery_script)
                self.run_lua('assert(loadfile('+json.dumps(str(recovery_probe))+'))',td)
                self.assertIn('hud._view_handoff={schema=schema,view=controller.view}',recovery_script)
                self.assertIn('controller.update_preserve_view=true',recovery_script)
                self.assertNotIn('hud._view_handoff=nil',recovery_script)
                self.assertIn('recovery.."/DragonsGateHUD.mpackage"',recovery_script)
                self.assertNotIn('tempTimer(0.15',recovery_script)
                self.assertIn('hud~=retired',recovery_script)
                self.assertIn('Reinstalled and verified DragonsGateHUD',recovery_script)
                self.assertIn('removeThenInstall(300)',recovery_script)
                self.assertIn('Personal data preflight failed; nothing was removed',recovery_script)
                self.assertIn('DGHUDMigration',recovery_script)
                self.assertGreaterEqual(recovery_script.count('preserveData()'),2)
                self.assertIn('Final personal data sync failed; nothing was removed',recovery_script)
                self.assertIn('type(lfs.symlinkattributes)~="function"',recovery_script)
                self.assertIn('could not prove the legacy HUD data directory is absent',recovery_script)
                self.assertLess(recovery_script.index('preserveData()'),recovery_script.index('uninstallPackage("DragonsGateHUD")'))
                self.assertNotIn('Reinstalled DragonsGateHUD.',recovery_script)
            with zipfile.ZipFile(migration) as z:
                self.assertEqual(z.namelist(),['DGHUDMigration.xml','config.lua'])
                self.assertEqual(z.read('config.lua'),b'mpackage = "DGHUDMigration"\n')
                migration_xml=z.read('DGHUDMigration.xml').decode()
                self.assertIn('<packageName>DGHUDMigration</packageName>',migration_xml)
                migration_root=ElementTree.fromstring(migration_xml)
                bridge_source=(ROOT/'src/migration_bridge.lua').read_text()
                bridge_version=re.search(r'Bridge=\{version="([^"]+)"',bridge_source).group(1)
                self.assertIn(f'<version>{bridge_version}</version>',migration_xml)
                self.assertEqual({node.text for node in migration_root.findall('.//packageName')},{'DGHUDMigration'})
                migration_script=migration_root.findtext('.//Script/script')
                self.assertEqual(migration_script,bridge_source)
                self.assertIn('^dghud safe update$',migration_script)
                self.assertIn('copyVerified',migration_script)
                self.assertIn('.dghud-migration',migration_script)
                self.assertIn('state=="committed"',migration_script)
                self.assertIn('_G.uninstallPackage=wrappedUninstall',migration_script)
                self.assertIn('symlinkattributes',migration_script)
                self.assertIn('DGHUDMigration=Bridge',migration_script)
                self.assertIn('tempTimer(0,Bridge.run)',migration_script)
            self.assertEqual(manifest['package'],'DragonsGateHUD')
            self.assertEqual(manifest['archive_url'],f'https://github.com/{owner}/{repository}/releases/download/v{manifest["version"]}/DragonsGateHUD.mpackage')
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
                self.assertIn('pcall(Adapter.prepareDataDirectory)',runtime)
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

            readme=(ROOT/'README.md').read_text()
            self.assertIn(f'https://github.com/{owner}/{repository}/releases/latest/download/DGHUDMigration.mpackage',readme)
            self.assertIn(f'https://github.com/{owner}/{repository}/releases/latest/download/DragonsGateHUD.mpackage',readme)
            self.assertIn(f'gh attestation verify DragonsGateHUD.mpackage --repo {owner}/{repository}',readme)
            self.assertIn(f'gh attestation verify DGHUDMigration.mpackage --repo {owner}/{repository}',readme)

    def test_build_rejects_version_different_from_defaults(self):
        with tempfile.TemporaryDirectory() as td:
            completed=subprocess.run(
                [sys.executable,str(ROOT/'scripts/build.py'),'--output',td,'--owner','ricwall','--repository','dragons-gate-hud','--version','9.9.9'],
                text=True,capture_output=True,
            )
            self.assertNotEqual(completed.returncode,0)
            self.assertIn('does not match defaults.version',completed.stderr)
if __name__=='__main__': unittest.main()

from pathlib import Path
import os, plistlib, subprocess, tempfile
script = Path(__file__).with_name('replace_macos_app_build.sh').read_text()
with tempfile.TemporaryDirectory(prefix='replace-skill-') as directory:
 root=Path(directory); repo=root/'repo'; repo.mkdir(); apps=root/'Applications'; apps.mkdir(); home=root/'home'; home.mkdir(); bins=root/'bin'; bins.mkdir()
 def tool(name, content):
  p=bins/name;p.write_text('#!/bin/bash\n'+content+'\n');p.chmod(0o755);return p
 tool('xcodebuild', 'exit 0')
 tool('osascript', 'if [[ "$*" == *"to quit"* ]]; then exit 0; elif [[ "$*" == *"path to app"* ]]; then echo "$TEST_INSTALLED/"; else echo false; fi')
 for name in ['mdimport','open','killall']: tool(name, 'exit 0')
 ls=tool('lsregister','exit 0')
 fixture=script.replace('"$HOME/Library/Developer/Xcode/DerivedData"', f'"{home}/Library/Developer/Xcode/DerivedData"').replace('INSTALLED_APP="/Applications/$INSTALL_NAME.app"',f'INSTALLED_APP="{apps}/$INSTALL_NAME.app"')
 import re
 fixture=re.sub(r'^LSREGISTER=.*$',f'LSREGISTER="{ls}"',fixture,flags=re.M)
 runner=root/'installer.sh';runner.write_text(fixture)
 env=dict(os.environ,PATH=str(bins)+':'+os.environ['PATH'],TEST_INSTALLED=str(apps/'Sample.app'))
 def bundle(path, identifier='test.sample', code='implementation'):
  (path/'Contents/MacOS').mkdir(parents=True,exist_ok=True)
  (path/'Contents/Info.plist').write_bytes(plistlib.dumps(dict(CFBundleIdentifier=identifier,CFBundleShortVersionString='1.2',CFBundleVersion='3',CFBundleExecutable='Sample')))
  (path/'Contents/MacOS/Sample').write_text('launcher')
  (path/'Contents/MacOS/Sample.debug.dylib').write_text(code)
 source=repo/'build/DerivedData/Build/Products/Release/Sample.app'
 stale=repo/'build/Old/Debug/Sample.app'
 other=repo/'build/Other/Sample.app'
 def run(*extra):
  return subprocess.run(['bash',str(runner),'--project','Sample.xcodeproj','--scheme','Sample','--app-name','Sample',*extra],cwd=repo,env=env,capture_output=True,text=True)
 assert run('--dry-run').returncode==0
 assert not (repo/'build').exists()
 bundle(source);bundle(stale);bundle(other,'test.unrelated')
 r=run('--bundle-id','wrong.identity');assert r.returncode!=0 and source.exists() and not (apps/'Sample.app').exists(),r.stdout+r.stderr
 r=run();assert r.returncode==0,r.stdout+r.stderr
 assert not source.exists() and not stale.exists() and other.exists()
 assert (apps/'Sample.app/Contents/MacOS/Sample.debug.dylib').read_text()=='implementation'
 bundle(source,code='new implementation')
 r=run('--keep-build');assert r.returncode==0 and source.exists(),r.stdout+r.stderr
 assert (apps/'Sample.app/Contents/MacOS/Sample.debug.dylib').read_text()=='new implementation'
 r=run('--derived-data','..');assert r.returncode!=0
 print('PASS: dry-run is nonmutating; identity mismatch preserves build; verified install removes fresh/stale copies; other identities survive; explicit retention works; unsafe build paths rejected.')

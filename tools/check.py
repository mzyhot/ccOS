#!/usr/bin/env python3
"""Build ccOS, compile all Lua, then run deterministic runtime regressions."""
from pathlib import Path
import subprocess, sys, tempfile, json
ROOT=Path(__file__).resolve().parents[1]
SCENARIOS=['picture','picture-small','picture-compact','picture-upgrade','desktop-menu','mirror','home','small','tools-desktop','tools-monitor','tool-logic','agent','agent-error','agent-malformed','agent-cancel','agent-deny','agent-cancel-http','agent-timeout','setup','setup-offline','setup-reinstall','setup-rollback','setup-no-space']
subprocess.run([sys.executable,str(ROOT/'tools/bundle.py')],check=True)
for source in sorted((ROOT/'src').rglob('*.lua')):
    subprocess.run(['lua','-e','assert(loadfile('+json.dumps(str(source))+'))'],check=True,capture_output=True)
subprocess.run(['lua','test_core.lua','../src'],cwd=ROOT/'test',check=True)
results=[]
with tempfile.TemporaryDirectory(prefix='ccos-check-')as out:
    for scenario in SCENARIOS:
        proc=subprocess.run(['lua','harness.lua','../src',scenario,str(Path(out)/(scenario+'.html'))],cwd=ROOT/'test',capture_output=True,text=True)
        results.append({'scenario':scenario,'passed':proc.returncode==0,'output':proc.stdout+proc.stderr})
        print(('PASS 'if proc.returncode==0 else 'FAIL ')+scenario)
        if proc.returncode:print(proc.stdout+proc.stderr)
if len(sys.argv)>1:Path(sys.argv[1]).write_text(json.dumps(results,indent=2))
failed=sum(not r['passed']for r in results)
print(f'{len(results)-failed}/{len(results)} runtime scenarios passed')
sys.exit(bool(failed))

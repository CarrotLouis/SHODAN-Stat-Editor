"""Package the Flutter UI and Rust host, excluding Qt and network proxy runtimes."""
import argparse,hashlib,json,pathlib,shutil,zipfile
from package_lab import MODULES
ROOT=pathlib.Path(__file__).resolve().parents[1]
def main():
 p=argparse.ArgumentParser();p.add_argument('--output',type=pathlib.Path,required=True);a=p.parse_args()
 if a.output.exists():p.error('Use a fresh output folder')
 ui=ROOT/'desktop/morrow/build/windows/x64/runner/Release';host=ROOT/'target/release/shodan-core.exe'
 if not (ui/'shodan_desktop.exe').exists() or not host.exists():p.error('Build Flutter release and cargo build --release first')
 shutil.copytree(ui,a.output)
 for f in a.output.rglob('*'):
  if f.is_file() and f.suffix.lower() in ('.pdb','.lib','.exp','.ilk'):f.unlink()
 (a.output/'shodan_desktop.exe').rename(a.output/'SHODAN 数值编辑器.exe')
 shutil.copy2(host,a.output/'shodan-core.exe')
 for name in ('lua51.dll','libsodium.dll'):shutil.copy2(ROOT/'offline/runtime'/name,a.output/name)
 shutil.copy2(ROOT/'offline/launcher/shodan_hash.dll',a.output/'shodan_hash.dll')
 (a.output/'app').mkdir()
 for module in MODULES:shutil.copy2(ROOT/('src/stat_editor.lua' if module=='stat_editor' else 'offline/'+module+'.lua'),a.output/'app'/f'{module}.lua')
 (a.output/'originals').mkdir()
 for f in (ROOT/'offline/originals').iterdir():
  if f.suffix=='.dl_plain' or f.name=='build.txt':shutil.copy2(f,a.output/'originals'/f.name)
 (a.output/'licenses').mkdir()
 for f in (ROOT/'offline/licenses').glob('*.txt'):
  if f.name.startswith(('LuaJIT','libsodium')):shutil.copy2(f,a.output/'licenses'/f.name)
 for name in ('MORROW-LICENSE','NOTICE.md'):shutil.copy2(ROOT/'desktop/morrow'/name,a.output/'licenses'/name)
 shutil.copy2(ROOT/'desktop/morrow/assets/fonts/MiSans-font-notice.txt',a.output/'licenses/MiSans-font-notice.txt')
 shutil.copy2(ROOT/'LICENSE',a.output/'LICENSE')
 shutil.copy2(ROOT/'README.md',a.output/'README.md')
 (a.output/'docs').mkdir()
 shutil.copy2(ROOT/'docs/corpse-cleanup.md',a.output/'docs/corpse-cleanup.md')
 manifest={'version':'4.6.0','status':'release','ui':'Morrow / Flutter','host':'Rust + compatibility Lua engine','core_version':'4.6.0','files':{str(f.relative_to(a.output)).replace('\\','/'):hashlib.sha256(f.read_bytes()).hexdigest() for f in a.output.rglob('*')if f.is_file()}}
 (a.output/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8')
 with zipfile.ZipFile(a.output.with_suffix('.zip'),'w',zipfile.ZIP_DEFLATED,compresslevel=9)as z:
  for f in a.output.rglob('*'):
   if f.is_file():z.write(f,a.output.name+'/'+f.relative_to(a.output).as_posix())
 print(json.dumps({'folder':str(a.output),'files':len(manifest['files']),'zip_bytes':a.output.with_suffix('.zip').stat().st_size}))
 if a.output.with_suffix('.zip').stat().st_size >= 20_000_000:
  raise SystemExit('Package exceeds the 20 MB limit')
if __name__=='__main__':main()

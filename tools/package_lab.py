"""Package the native desktop editor using an explicit runtime allowlist."""
from pathlib import Path
import argparse,hashlib,json,shutil,zipfile,ctypes,struct
ROOT=Path(__file__).resolve().parents[1]
VERSION='4.5.1-r2'
CORE_VERSION='4.5.1'
CORE_COMMIT='f14a20991dc5c92eefc2f36996e5191311c9ba22'
MODULES=('stat_editor','host','hostdata','install','engine_shim','gamedata','update','armory','armory_data','armor_ui','armor_presets','armor_baseline','text_input','zh_extra','zh_game','zh_params','zh_reference','zh_hashes','zh_ui','theme','layout','desktop_features','edit_history','reference_chain','gameplay_resources','ragdoll_recipe','corpse_cleanup','corpse_recipe','vehicles','mod_merge','extra_stratagem_guard','res_patch','state_machine')
def pack(folder,dest,allowed):
    with zipfile.ZipFile(dest,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
        for relative in sorted(allowed):archive.write(folder/relative,folder.name+'/'+relative)
def set_icon(executable,icon):
    data=icon.read_bytes();count=struct.unpack_from('<H',data,4)[0]
    kernel=ctypes.WinDLL('kernel32',use_last_error=True)
    kernel.BeginUpdateResourceW.argtypes=[ctypes.c_wchar_p,ctypes.c_bool];kernel.BeginUpdateResourceW.restype=ctypes.c_void_p
    kernel.UpdateResourceW.argtypes=[ctypes.c_void_p,ctypes.c_void_p,ctypes.c_void_p,ctypes.c_ushort,ctypes.c_void_p,ctypes.c_uint];kernel.UpdateResourceW.restype=ctypes.c_bool
    kernel.EndUpdateResourceW.argtypes=[ctypes.c_void_p,ctypes.c_bool];kernel.EndUpdateResourceW.restype=ctypes.c_bool
    handle=kernel.BeginUpdateResourceW(str(executable),False)
    if not handle:raise ctypes.WinError(ctypes.get_last_error())
    def put(kind,name,blob):
        buffer=ctypes.create_string_buffer(blob)
        if not kernel.UpdateResourceW(handle,kind,name,1033,buffer,len(blob)):raise ctypes.WinError(ctypes.get_last_error())
    try:
        group=bytearray(struct.pack('<HHH',0,1,count))
        for i in range(count):
            entry=data[6+i*16:22+i*16];size,offset=struct.unpack_from('<II',entry,8);rid=101+i
            put(3,rid,data[offset:offset+size]);group+=entry[:12]+struct.pack('<H',rid)
        put(14,1,bytes(group))
    except BaseException:
        kernel.EndUpdateResourceW(handle,True);raise
    if not kernel.EndUpdateResourceW(handle,False):raise ctypes.WinError(ctypes.get_last_error())

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--base',default=str(ROOT/'offline/runtime'));parser.add_argument('--python');parser.add_argument('--output-root',default=str(ROOT/'dist'))
    args=parser.parse_args();base=Path(args.base);out=Path(args.output_root);release=out/('SHODAN_'+VERSION)
    release.mkdir(parents=True,exist_ok=True);(release/'app').mkdir(exist_ok=True)
    allowed=set()
    def copy(source,relative):
        dest=release/relative
        dest.parent.mkdir(parents=True,exist_ok=True)
        if not dest.exists() or dest.read_bytes()!=source.read_bytes():shutil.copy2(source,dest)
        allowed.add(relative)
    launcher=ROOT/'offline/launcher/SHODAN Official Editor.exe'
    if not launcher.exists():launcher=ROOT/'offline/launcher/SHODAN Stat Editor Offline.exe'
    copy(launcher,'SHODAN 数值编辑器.exe')
    set_icon(release/'SHODAN 数值编辑器.exe',ROOT/'offline/launcher/sseo.ico')
    for name in ('libsodium.dll','lua51.dll'):copy(base/name,name)
    copy(ROOT/'offline/launcher/shodan_hash.dll','shodan_hash.dll')
    for name in MODULES:copy(ROOT/('src/stat_editor.lua' if name=='stat_editor' else 'offline/'+name+'.lua'),'app/'+name+'.lua')
    references=[ROOT/'offline/originals/build.txt']+sorted((ROOT/'offline/originals').glob('*.dl_plain'))
    for path in references:copy(path,'originals/'+path.name)
    for name in ('LICENSE','README.md'):copy(ROOT/name,name)
    for name in ('LuaJIT.txt','libsodium.txt'):copy(ROOT/'offline/licenses'/name,'licenses/'+name)
    manifest={'version':VERSION,'core_version':CORE_VERSION,'core_commit':CORE_COMMIT,'launcher':'official-3.2.0-custom-icon','write_flow':'official-3.2.0','source':'https://github.com/127MU/SHODAN-Stat-Editor','feature_source':'https://github.com/CarbonAnime/SHODAN-Stat-Editor/releases/tag/v3.2.31-armory','feature_commit':'01689e03e7631efe356aa47c8f3cf74400a5e7cf','game_writes_during_tests':False,'files':{}}
    for relative in sorted(allowed):manifest['files'][relative]=hashlib.sha256((release/relative).read_bytes()).hexdigest()
    (release/'manifest.json').write_text(json.dumps(manifest,ensure_ascii=False,indent=2),encoding='utf8');allowed.add('manifest.json')
    target=out/('SHODAN_'+VERSION+'_Windows.zip');pack(release,target,allowed)
    # Corresponding native source, without browser or unrelated workbench code.
    source=out/('SHODAN_'+VERSION+'_Source.zip')
    source_files=[ROOT/'src/stat_editor.lua',ROOT/'LICENSE',ROOT/'README.md',ROOT/'tools/package_lab.py']
    source_files+=list((ROOT/'offline').glob('*.lua'))
    source_files+=references
    source_files+=list((ROOT/'offline/licenses').glob('*.txt'))
    for pattern in ('*.c','*.h','*.def','*.cmd','*.rc','*.bat','*.ico'):
        source_files += [p for p in (ROOT/'offline/launcher').glob(pattern) if 'workbench' not in p.name.lower()]
    source_files += [p for p in (ROOT/'tests').glob('*.py') if p.name in ('test_armory_lua.py','test_native_input.py')]
    with zipfile.ZipFile(source,'w',zipfile.ZIP_DEFLATED,compresslevel=9) as archive:
        for p in sorted(set(source_files)):archive.write(p,'SHODAN_'+VERSION+'_Source/'+p.relative_to(ROOT).as_posix())
    print(json.dumps({'release':str(release),'files':len(allowed),'zip':str(target),'zip_bytes':target.stat().st_size,'source':str(source)},ensure_ascii=False))
if __name__=='__main__':main()

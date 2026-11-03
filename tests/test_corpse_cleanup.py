"""Versioned corpse recipes and hostdata round trips, using isolated fixtures only.

Windows: python tests/test_corpse_cleanup.py --vendor <lupa-and-PyNaCl-folder>
"""
import argparse
import hashlib
import json
import pathlib
import sys
import unittest

ROOT = pathlib.Path(__file__).resolve().parents[1]
parser = argparse.ArgumentParser()
parser.add_argument('--vendor', type=pathlib.Path)
parser.add_argument('--output', type=pathlib.Path, default=ROOT/'build/corpse-cleanup-tests')
args, remaining = parser.parse_known_args()
if args.vendor:
    sys.path.insert(0, str(args.vendor.resolve()))
from lupa.luajit21 import LuaRuntime
from nacl.public import PrivateKey, SealedBox

BASE = (ROOT/'offline/originals/generated_entities.dl_plain').read_bytes()
# Both directions use the isolated sodium bridge below, so fixtures can use a
# fresh in-memory key instead of embedding the game's format key in the test.
BOX = SealedBox(PrivateKey.generate())
FULL_SHA = '0a8c584eaad9c23c81e6375f60ad5a513829ff0962e5be3c95a6f5d6844daa58'
SMALL_SHA = 'a87f2efdb36eead685b644ed37d36f84d685353708b77cd0ee84cd461cbce734'


class CorpseCleanupTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.output = args.output.resolve()
        cls.output.mkdir(parents=True, exist_ok=True)
        cls.lua = LuaRuntime(encoding=None)
        globals = cls.lua.globals()
        globals.PY_UNSEAL = BOX.decrypt
        globals.PY_SEAL = BOX.encrypt
        globals.PY_SHA256 = lambda data: hashlib.sha256(data).digest()
        globals.BASE = BASE
        globals.BASE_CIPHER = BOX.encrypt(BASE)
        globals.FULL_SHA, globals.SMALL_SHA = FULL_SHA.encode(), SMALL_SHA.encode()
        cls.lua.execute(b"""
local ffi=require('ffi');local load=ffi.load
local sodium={sodium_init=function()return 0 end}
sodium.crypto_box_seal_open=function(dst,src,n,pk,sk)
 local ok,plain=pcall(PY_UNSEAL,ffi.string(src,n));if not ok then return -1 end
 ffi.copy(dst,plain,#plain);return 0
end
sodium.crypto_box_seal=function(dst,src,n,pk)
 local cipher=PY_SEAL(ffi.string(src,n));ffi.copy(dst,cipher,#cipher);return 0
end
sodium.crypto_hash_sha256=function(dst,src,n)ffi.copy(dst,PY_SHA256(ffi.string(src,n)),32);return 0 end
ffi.load=function(path,...)
 if type(path)=='string' and path:match('libsodium%.dll$')then return sodium end
 return load(path,...)
end
""")
        cls.lua.execute(b"package.path=.....';'..package.path", (ROOT/'offline/?.lua').as_posix().encode())
        target = cls.lua.execute(b"local G=require('gamedata');local ffi=require('ffi');return G.le64(G.murmur64(ffi.cast('const uint8_t*',BASE),#BASE))")
        (cls.output/'game.dll').write_bytes(target)
        globals.FOLDER = cls.output.as_posix().encode()
        cls.lua.execute(b"""
G=require('gamedata');D=require('hostdata');C=require('corpse_cleanup');ffi=require('ffi')
function unload()
 for _,f in pairs(D.files)do if f.original_p then G.free(f.original_p)end;G.free(f.p)end
 D.files={};D.modded={};D.original_layouts={}
end
function fixture(raw,keep)
 unload();assert(#D.load(FOLDER,{[C.FILE]=raw or BASE_CIPHER},{[C.FILE]=BASE_CIPHER})==0)
 if not keep then
  STORE={};I={home='isolated-profile',fail=false}
  I.read=function(path)return STORE[path]end
  I.write=function(path,data)if I.fail then return nil,'simulated failure'end;STORE[path]=data;return true end
  I.remove=function(path)STORE[path]=nil;return true end
 end
 controller=C.new(D,I,function()REV=(REV or 0)+1 end)
 assert(controller.supported,controller.problem)
 return controller
end
function changes()
 local changes,problems=D.diff();assert(#problems==0);controller:include_change(changes);return changes
end
function digest()
 local c=changes();assert(#c==1);local hash=G.sha256_hex(ffi.string(c[1].plain,c[1].n))
 for _,change in ipairs(c)do G.free(change.plain)end;return hash
end
function build()
 local c=changes();assert(#c==1);local sealed,why=D.build(c[1]);assert(sealed,why);return sealed
end
""")

    def setUp(self):
        self.lua.execute(b'fixture()')

    def test_both_original_mod_recipes_match_independent_plaintext_hashes(self):
        self.lua.execute(b"controller:set('fast',false);assert(digest()==FULL_SHA);controller:set('instant',true);assert(digest()==SMALL_SHA)")

    def test_combination_and_mode_switch_restore_only_owned_fields(self):
        self.lua.execute(b"""
controller:set('fast',true)
local h=controller.tables.health.slots[0]
local base=h[21532].at-21532;local hp=ffi.cast('uint32_t*',controller.file.p+base)
local old=tonumber(hp[0]);hp[0]=old+1
controller:set('instant',false);assert(tonumber(hp[0])==old+1)
controller:set('original',false);assert(tonumber(hp[0])==old+1)
for _,slot in ipairs(controller.slots)do assert(ffi.string(controller.file.p+slot.at,4)==slot.original)end
local c=changes();assert(#c==1);G.free(c[1].plain)
""")

    def test_combination_has_one_body_policy_and_two_second_fragments(self):
        self.lua.execute(b"""
controller:set('fast',true)
for _,r in ipairs(require('corpse_recipe').tables.health.fast)do
 local fields=controller.tables.health.slots[r[1]]
 assert(ffi.cast('float*',controller.file.p+fields[21540].at)[0]==r[3])
end
for _,fields in pairs(controller.tables.gore.slots)do
 for _,slot in pairs(fields)do assert(ffi.cast('float*',controller.file.p+slot.at)[0]==2)end
end
assert(#controller:preview()==2 and controller:status().changed)
""")

    def test_saved_configuration_and_sealed_file_survive_reopen(self):
        self.lua.execute(b"""
controller:set('fast',true);local raw=build()
fixture(nil,true);assert(controller.mode=='fast' and controller.fragments=='fast' and controller:dirty())
fixture(raw,true);assert(controller.mode=='fast' and controller.fragments=='fast' and not controller:dirty())
local c=changes();assert(#c==1);G.free(c[1].plain)
""")

    def test_reset_of_external_mod_is_included_even_when_diff_is_empty(self):
        self.lua.execute(b"""
controller:set('instant',true);local external=build()
fixture(external);assert(controller.mode=='instant' and controller.fragments=='fast')
controller:set('original',false)
local c,p=D.diff();assert(#p==0 and #c==0)
controller:include_change(c);assert(#c==1 and ffi.string(c[1].plain,c[1].n)==BASE)
local raw=assert(D.build(c[1]));local p,n=G.open_sealed(raw);assert(ffi.string(p,n)==BASE);G.free(p)
""")

    def test_version_and_table_layout_mismatches_do_not_mutate(self):
        self.lua.execute(b"""
local file=controller.file;local old=G.sha256_hex(ffi.string(file.p,file.n))
file.baseline=G.seal_string('unsupported version')
local bad=C.new(D,I);assert(not bad.supported)
assert(not pcall(function()bad:set('fast',true)end))
assert(G.sha256_hex(ffi.string(file.p,file.n))==old)
file.baseline=BASE_CIPHER
local at=controller.tables.health.slots[0][21532].at-21532-require('corpse_recipe').tables.health.buckets*16
file.p[at]=file.p[at]+1
bad=C.new(D,I);assert(not bad.supported)
""")

    def test_unsupported_saved_recipe_can_be_disabled_without_game_writes(self):
        self.lua.execute(b"""
controller:set('fast',true);controller.file.baseline=G.seal_string('new game version')
local B={pending_preview=function()return {}end}
local bad=C.attach(B,D,I,function()end)
assert(not B.corpse_status().supported and bad:validate())
B.corpse_reset();assert(not bad:validate() and not B.corpse_status().saved)
""")

    def test_save_failure_validation_and_custom_data_preservation(self):
        self.lua.execute(b"""
local before=G.sha256_hex(ffi.string(controller.file.p,controller.file.n))
I.fail=true;assert(not pcall(function()controller:set('fast',true)end));I.fail=false
assert(G.sha256_hex(ffi.string(controller.file.p,controller.file.n))==before)
assert(not pcall(function()controller:set('invented',true)end))
assert(not pcall(function()controller:set('fast',7)end))
local slot=controller.tables.health.slots[0][21532]
ffi.cast('uint32_t*',controller.file.p+slot.at)[0]=7
controller=C.new(D,I);assert(controller.mode=='custom')
controller:set('custom',true)
assert(ffi.cast('uint32_t*',controller.file.p+slot.at)[0]==7)
controller=C.new(D,I);assert(controller.mode=='custom' and controller.fragments=='fast')
""")

    def test_api_preview_history_and_undo_redo_use_same_controller(self):
        self.lua.execute(b"""
local B={pending_preview=function()return {{equipment='existing'}}end,
 set=function()end,choose=function()end,reset=function()end,code_set=function()end}
require('edit_history').attach(B,{})
controller=C.attach(B,D,I,function()REV=(REV or 0)+1 end)
B.corpse_set('fast',true);assert(#B.pending_preview()==3 and B.history().undo==1)
B.undo();assert(controller.mode=='original' and not controller:dirty())
B.redo();assert(controller.mode=='fast')
local field=controller.slots[1];controller.file.p[field.at]=controller.file.p[field.at]+1
assert(not pcall(B.undo));assert(B.history().undo==1 and B.history().redo==0)
""")

    @classmethod
    def tearDownClass(cls):
        cls.lua.execute(b'unload()')


if __name__ == '__main__':
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(CorpseCleanupTests)
    result = unittest.TextTestRunner(verbosity=2).run(suite)
    report = {'tests': result.testsRun, 'failures': len(result.failures), 'errors': len(result.errors), 'real_game_writes': 0}
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output/'report.json').write_text(json.dumps(report, indent=2), encoding='utf-8')
    print(json.dumps(report))
    sys.exit(not result.wasSuccessful())

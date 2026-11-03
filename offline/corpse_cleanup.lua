-- Desktop corpse settings share hostdata's working buffer and normal install.
-- Only the version-checked numeric fields in corpse_recipe are owned here.
local ffi=require('ffi')
local G=require('gamedata')
local recipe=require('corpse_recipe')
local M={FILE='generated_entities.dl_bin'}
local labels={original='原版',fast='快速清场（约 6 秒）',instant='小型单位快速消失',custom='已有自定义设置'}
local function u32(p,off)return tonumber(ffi.cast('const uint32_t*',p+off)[0])end
local function packed(value,integer)
 local p=ffi.new(integer and 'uint32_t[1]' or 'float[1]',value)
 return ffi.string(p,4)
end
local function decode(text)
 local mode,gore=text:match('^SHODAN%-CORPSE 1\nmode (%a+)\ngore ([01c])\n?$')
 assert(labels[mode],'尸体清理配置无效，请重新选择模式后保存')
 return mode,gore=='c' and 'custom' or gore=='1'
end
local function encode(mode,gore)return 'SHODAN-CORPSE 1\nmode '..mode..'\ngore '..(gore=='custom' and 'c' or gore and '1' or '0')..'\n'end
local Controller={};Controller.__index=Controller

function M.new(D,I,changed)
 local self=setmetatable({D=D,I=I,changed=changed or function()end,slots={},mode='custom',fragments='custom',
  path=I.home..'/corpse_cleanup.ini'},Controller)
 local stored=I.read(self.path)
 self.has_saved=stored~=nil
 local file=D.files[M.FILE];self.file=file
 local original
 local ok,why=pcall(function()
  assert(file,'未读取到实体数据文件，尸体清理不可用')
  local p,n=G.open_sealed(file.baseline or file.cipher);assert(p,n);original=p
  assert(G.sha256_hex(ffi.string(p,n))==recipe.sha256,'当前原版实体数据与尸体清理配方版本不匹配，未修改')
  local before,live={},{}
  for _,h in ipairs(G.headers(p,n))do before[h.type]=h end
  for _,h in ipairs(G.headers(file.p,file.n))do
   for _,spec in pairs(recipe.tables)do if spec.type==h.type then
    assert(not live[h.type],'尸体数据表重复，无法安全定位');live[h.type]=h
   end end
  end
  self.tables={}
  for name,spec in pairs(recipe.tables)do
   local a,b=assert(before[spec.type]),assert(live[spec.type],'缺少尸体相关数据表：'..name)
   assert(a.size==spec.size and b.size==spec.size and b.at+24+b.size<=file.n,'尸体数据表布局不匹配：'..name)
   assert(spec.buckets*16+spec.rows*spec.stride==spec.size,'尸体配方记录布局无效')
   local ap,bp=p+a.at+24,file.p+b.at+24
   assert(ffi.string(ap,spec.buckets*16)==ffi.string(bp,spec.buckets*16),'尸体数据表记录顺序已被其他 Mod 改变，未修改')
   local first=spec.buckets*16
   local offsets=name=='health' and {21532,21536,21540,21544,21548} or name=='gore' and {0,4,8} or {0}
   self.tables[name]={spec=spec,slots={}}
   for _,row in ipairs(spec.indices)do
    assert(row>=0 and row<spec.rows,'尸体配方索引越界')
    local fields={};self.tables[name].slots[row]=fields
    for _,off in ipairs(offsets)do
     local relative=first+row*spec.stride+off
     assert(relative+4<=spec.size,'尸体配方字段越界')
     local slot={at=b.at+24+relative,original=ffi.string(ap+relative,4),group=name}
     slot.loaded=ffi.string(file.p+slot.at,4)
     fields[off]=slot;self.slots[#self.slots+1]=slot
    end
   end
  end
 end)
 if original then G.free(original)end
 if not ok then self.problem=tostring(why);self.slots={};self.blocked=stored~=nil;return self end
 self.supported=true
 self.mode,self.fragments=self:detect()
 self.installed_mode,self.installed_fragments=self.mode,self.fragments
 if stored then
  local valid,mode,gore=pcall(decode,stored)
  if valid then if self:apply(mode,gore)then self.changed()end
  else self.config_problem=tostring(mode)end
 end
 return self
end

function Controller:plan(mode,gore)
 assert(self.supported,self.problem)
 assert(labels[mode],'未知尸体清理模式')
 assert(type(gore)=='boolean' or gore=='custom','碎块清理开关无效')
 local plan={}
 for _,slot in ipairs(self.slots)do plan[slot]=slot.original end
 if mode=='custom' then
  for _,slot in ipairs(self.slots)do if slot.group~='gore'then plan[slot]=ffi.string(self.file.p+slot.at,4)end end
 elseif mode=='fast' then
  for _,r in ipairs(recipe.tables.health.fast)do
   local fields=assert(self.tables.health.slots[r[1]])
   plan[fields[21532]]=packed(r[2],true)
   plan[fields[21540]]=packed(r[3])
   plan[fields[21548]]=packed(r[4])
  end
  for _,fields in pairs(self.tables.decayer.slots)do plan[fields[0]]=packed(300)end
 elseif mode=='instant' then
  for _,fields in pairs(self.tables.health.slots)do
   plan[fields[21532]]=packed(3,true);plan[fields[21536]]=packed(100)
   plan[fields[21540]]=packed(0);plan[fields[21544]]=packed(0)
  end
 end
 if gore=='custom' then
  for _,slot in ipairs(self.slots)do if slot.group=='gore'then plan[slot]=ffi.string(self.file.p+slot.at,4)end end
 elseif gore then for _,fields in pairs(self.tables.gore.slots)do
  for _,slot in pairs(fields)do plan[slot]=packed(2)end
 end end
 return plan
end

function Controller:detect()
 local mode='custom'
 for _,candidate in ipairs({'original','fast','instant'})do
  local matches=true
  for slot,bytes in pairs(self:plan(candidate,false))do
   if slot.group~='gore' and ffi.string(self.file.p+slot.at,4)~=bytes then matches=false;break end
  end
  if matches then mode=candidate;break end
 end
 local fragments='custom'
 for _,fast in ipairs({false,true})do
  local matches=true
  for slot,bytes in pairs(self:plan('original',fast))do
   if slot.group=='gore' and ffi.string(self.file.p+slot.at,4)~=bytes then matches=false;break end
  end
  if matches then fragments=fast and 'fast' or 'original';break end
 end
 return mode,fragments
end

function Controller:apply(mode,gore)
 local different=false
 for slot,bytes in pairs(self:plan(mode,gore))do
  if ffi.string(self.file.p+slot.at,4)~=bytes then ffi.copy(self.file.p+slot.at,bytes,4);different=true end
 end
 self.mode,self.fragments=mode,gore=='custom' and 'custom' or gore and 'fast' or 'original'
 return different
end
function Controller:capture()
 local out={mode=self.mode,fragments=self.fragments,bytes={},config=self.I.read(self.path)}
 for i,slot in ipairs(self.slots)do out.bytes[i]=ffi.string(self.file.p+slot.at,4)end
 return out
end
function Controller:restore_snapshot(target,expected)
 if self.I.read(self.path)~=expected.config then return nil,'尸体清理配置已变化，未覆盖新的配置'end
 for i,slot in ipairs(self.slots)do
  if ffi.string(self.file.p+slot.at,4)~=expected.bytes[i]then return nil,'尸体参数已变化，未覆盖新的编辑'end
 end
 local ok,why
 if target.config then ok,why=self.I.write(self.path,target.config)
 else ok,why=(self.I.remove or os.remove)(self.path)end
 if not ok then return nil,why end
 for i,slot in ipairs(self.slots)do ffi.copy(self.file.p+slot.at,target.bytes[i],4)end
 self.mode,self.fragments=target.mode,target.fragments;self.has_saved=target.config~=nil;self.config_problem=nil;self.changed();return true
end
function Controller:set(mode,gore)
 local plan=self:plan(mode,gore) -- Validate the entire operation before persistence or mutation.
 local before=self:capture()
 local ok,why=self.I.write(self.path,encode(mode,gore));assert(ok,'尸体配置保存失败：'..tostring(why))
 for slot,bytes in pairs(plan)do ffi.copy(self.file.p+slot.at,bytes,4)end
 self.mode,self.fragments=mode,gore=='custom' and 'custom' or gore and 'fast' or 'original';self.has_saved=true;self.config_problem=nil
 local after=self:capture();local different=before.config~=after.config
 for i,bytes in ipairs(after.bytes)do different=different or bytes~=before.bytes[i]end
 if different then self.changed()end
 return before,after,different
end
function Controller:dirty()
 for _,slot in ipairs(self.slots)do if ffi.string(self.file.p+slot.at,4)~=slot.loaded then return true end end
 return false
end
function Controller:validate()
 if self.blocked then return self.problem end
 return self.config_problem
end
function Controller:status()
 return {supported=self.supported==true,problem=self.problem or self.config_problem,mode=self.mode,fragments=self.fragments,
  installed_mode=self.installed_mode,installed_fragments=self.installed_fragments,changed=self:dirty(),saved=self.has_saved,
  health_records=473,small_records=507,decayer_records=59,gore_records=210}
end
function Controller:preview()
 if not self.supported then return {}end
 local entries={}
 if self.mode~='original' or self.mode~=self.installed_mode then entries[#entries+1]={equipment='尸体清理',parameter='尸体消退策略',
  before=labels[self.installed_mode] or '启动文件值',after=labels[self.mode],file=M.FILE}end
 if self.fragments~='original' or self.fragments~=self.installed_fragments then entries[#entries+1]={equipment='尸体清理',parameter='碎块寿命',
  before=self.installed_fragments=='fast' and '2 秒' or self.installed_fragments=='original' and '原版' or '已有自定义设置',
  after=self.fragments=='fast' and '2 秒' or self.fragments=='original' and '原版' or '已有自定义设置',file=M.FILE}end
 return entries
end
function Controller:include_change(changes)
 -- A reset of an externally installed mod can leave the whole working file at
 -- baseline. D.diff then has no entry, but the clean file still needs writing.
 if not self.supported or not self:dirty()then return end
 for _,change in ipairs(changes)do if change.name==M.FILE then return end end
 local p,n=G.open_sealed(self.file.baseline or self.file.cipher);assert(p,n);G.clear_correction(p,n)
 changes[#changes+1]={name=M.FILE,plain=p,n=n,bytes=0,floats={},hash=self.file.hash}
end
function M.attach(B,D,I,changed)
 local self=M.new(D,I,changed)
 B.corpse_status=function()return self:status()end
 B.corpse_set=function(mode,gore)
  local before,after,different=self:set(mode,gore)
  if different and B._record_edit then B._record_edit('尸体清理',before,after,function(target,expected)
   local ok,why=self:restore_snapshot(target,expected);assert(ok,why);return true
  end)end
  return self:status()
 end
 B.corpse_reset=function()
  if self.supported then return B.corpse_set('original',false)end
  if self.has_saved then assert((I.remove or os.remove)(self.path),'无法停用旧尸体清理配置')end
  self.has_saved=false;self.blocked=false;self.changed();return self:status()
 end
 local pending=B.pending_preview
 B.pending_preview=function()
  local entries=pending()
  for _,entry in ipairs(self:preview())do entries[#entries+1]=entry end
  return entries
 end
 return self
end
return M

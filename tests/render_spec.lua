local root=...
local path=root..'/MIDI Editor/lib/'
local N=dofile(path..'note_layout.lua')
local R=dofile(path..'render_cache.lua')
local M=dofile(path..'model.lua')
local count=0
local function eq(a,b,message) count=count+1; assert(a==b,(message or '')..': '..tostring(a)..' ~= '..tostring(b)) end
local clips={{view_start=0,view_end=8},{view_start=0,view_end=8}}
local a={s=-2,e=4,pitch=60,vel=90,take_index=1}
local b={s=1,e=3,pitch=60,vel=50,take_index=2}
local c={s=2,e=4,pitch=40,vel=90,take_index=1}
local g={s=8,e=10,pitch=60,vel=70,take_index=1,ghost=true}
local notes,ghosts,source={a,b,c},{g},{}
local cache=R.new(N)
local layout=cache:update(notes,ghosts,clips,source,1)
eq(layout[a].count,2,'collisions include overlapping offscreen onsets')
local v=cache:view(2,2,55,65)
eq(#v.notes,2); eq(#v.velocity,1,'offscreen pitch still has a velocity handle')
eq(v.velocity[1].n,c); eq(v.notes[2].n,a,'active track is painted last')
eq(cache:view(2,2,55,65),v,'steady viewport is reused')
a.selected=true; a.vel=20
eq(cache:update(notes,ghosts,clips,source,1),layout,'selection/velocity do not rebuild geometry')
eq(v.notes[2].n.vel,20,'cached entries see live velocity'); eq(v.notes[2].n.selected,true)
cache:update(notes,ghosts,clips,source,2)
eq(cache.builds,1,'active track does not rebuild overlap geometry')
eq(cache:view(2,2,55,65).notes[2].n,b,'active track updates hit order')
eq(#cache:view(4,4,55,65).notes,0,'touching viewport edges are excluded')
eq(#cache:view(8,1,55,65).ghosts,1,'repeated notes enter the viewport')
local mini=cache:miniature(16,160)
eq(cache:miniature(16,160),mini,'overview reused')
for _,bar in ipairs(mini) do eq(bar.a>=0 and bar.z<=160,true,'overview clips negative onsets') end
-- In-place drawing/deletion invalidates once; Undo replaces the source table.
notes[#notes+1]={s=2,e=3,pitch=60,vel=70,take_index=2}
cache:invalidate(); cache:update(notes,ghosts,clips,source,2)
eq(#cache:view(2,2,55,65).notes,3)
table.remove(notes,4); cache:invalidate(); cache:update(notes,ghosts,clips,source,2)
eq(#cache:view(2,2,55,65).notes,2)
clips[1].view_end=1; source={}; cache:update(notes,ghosts,clips,source,2)
eq(#cache:view(2,2,55,65).notes,1,'external trim invalidates cached clip edges')
local replacement=M.copy(notes); replacement[1].s=6; replacement[1].e=7; clips[1].view_end=8
cache:update(replacement,ghosts,clips,{},1)
eq(cache:view(6,1,55,65).notes[1].n,replacement[1],'undo/new note tables replace references')
-- Dense overview must remain bounded by distinguishable pixels, not events.
local dense={}
for i=0,1999 do dense[#dense+1]={s=i/250,e=(i+1)/250,pitch=60,vel=80,take_index=1} end
cache:update(dense,{},clips,{},1)
eq(#cache:miniature(8,800),1,'adjacent marks of the same track merge')
-- Differential culling: compare cached paint/hit candidates with visible MIDI
-- across arbitrary zooms, pitches and clip edges, including long notes.
math.randomseed(724)
local generated={}
for i=1,400 do local s=math.random()*12-2
  generated[i]={s=s,e=s+math.random()*5+.01,pitch=math.random(0,127),take_index=math.random(1,2),vel=90}
end
cache:update(generated,ghosts,clips,{},1)
for trial=1,60 do
  local start,span=math.random()*10,math.random()*8+.01
  local low=math.random(0,110); local high=low+17
  local view=cache:view(start,span,low,high); local seen={}; local expected=0
  for _,entry in ipairs(view.notes) do seen[entry.n]=true end
  for _,n in ipairs(generated) do
    local a,z=math.max(n.s,0),math.min(n.e,8)
    local visible=z>a and z>start and a<start+span and n.pitch>=low and n.pitch<=high
    eq(not not seen[n],visible,'culling must preserve all visible/hittable notes')
    if visible then expected=expected+1 end
  end
  eq(#view.notes,expected)
end
return count

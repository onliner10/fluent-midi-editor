local root=...
local M=dofile(root..'/MIDI Editor/lib/model.lua')
local I=dofile(root..'/MIDI Editor/lib/integration.lua')
local L=dofile(root..'/MIDI Editor/lib/length.lua')
local P=dofile(root..'/MIDI Editor/lib/phrase.lua')
local N=dofile(root..'/MIDI Editor/lib/note_layout.lua')
local count=0
local function eq(a,b,label) count=count+1; assert(a==b,(label or '')..': '..tostring(a)..' ~= '..tostring(b)) end
local function close(a,b,label) count=count+1; assert(math.abs(a-b)<1e-7,label or 'values differ') end
local function note(s,e,p,selected) return {s=s,e=e,pitch=p,selected=selected~=false,vel=100,channel=0,muted=false} end
local a,b,c=note(0,1,60),note(0,1,60),note(2,3,60)
a.take_index=1; b.take_index=2; c.take_index=2
local layout=N.build({a,b,c})
eq(layout[a].top,0); eq(layout[a].bottom,.5); eq(layout[b].top,.5); eq(layout[b].bottom,1)
eq(layout[c].count,1,'non-overlapping notes retain full pitch-row height')
local y,z=N.bounds(layout,b,100,32); eq(y,116); eq(z,132)
b.s=.5; b.e=1.5; layout=N.build({a,b,c}); eq(layout[a].count,2,'partial overlap is visible')
b.s=1; layout=N.build({a,b,c}); eq(layout[a].count,1,'touching edges do not collide')
b.s=0; b.pitch=61; layout=N.build({a,b,c}); eq(layout[a].count,1,'different pitches use different rows')
b.pitch=60; b.take_index=1; layout=N.build({a,b,c}); eq(layout[a].count,1,'one track retains its row')
b.take_index=2; c.s=.5; c.e=.75; c.take_index=3
layout=N.build({a,b},{c}); eq(layout[a].count,3,'read-only overlapping ghost remains visible')
close(layout[c].top,2/3); eq(layout[c].bottom,1)
layout=N.build({a,b},nil,function(n) return n.s,math.min(n.e,.25) end)
eq(layout[a].count,2,'layout uses visible item bounds')
close(L.parse(' 0,5 '),.5); close(L.parse('1.5'),1.5); close(L.parse('8'),8)
eq(L.format(.5),'0,5'); eq(L.format(4),'4')
for _,value in ipairs({'','0','-2','1,2,3','nan','inf','4097','1e4'}) do eq(L.parse(value),nil,'invalid length') end
eq(M.pitch_name(60),'C3','Ableton octave names')
eq(M.velocity_color(0x76C7BDFF,127),0x76C7BDFF)
eq(M.velocity_color(0x76C7BDFF,0),M.velocity_color(0x76C7BDFF,1))
for v=2,127 do
  local a,b=M.velocity_color(0x76C7BDFF,v-1),M.velocity_color(0x76C7BDFF,v)
  eq((a>>16)&255 <= (b>>16)&255,true,'velocity brightness is monotonic')
end
close(M.snap(0.38,0.25),0.5); close(M.floor(0.38,0.25),0.25)
close(.13+M.drag_delta(.13,.25,.25),.5,'snap restored after free move')
close(.13+M.drag_delta(.13,-.1,.25),0,'snap backwards after free move')
close(M.drag_delta(.13,.17,0),.17,'snap disabled')
close(.63+M.drag_delta(.63,.12,.25),.75,'right edge snap restored')
close(.13+M.drag_delta(.13,.12,.25),.25,'left edge snap restored')
close(.13+M.nudge_delta(.13,1,.25),.25,'off-grid right arrow')
close(.13+M.nudge_delta(.13,-1,.25),0,'off-grid left arrow')
close(.25+M.nudge_delta(.25,1,.25),.5,'on-grid right arrow')
close(.25+M.nudge_delta(.25,-1,.25),0,'on-grid left arrow')
local selected_time=M.selection_range(.07,3.96,.25,true)
eq(selected_time[1],0); eq(selected_time[2],4)
local on_release=M.selection_range(.07,3.96,.25,true)
eq(on_release[1],0); eq(on_release[2],4,'range persists on mouse release')
eq(M.selection_range(.07,.07,.25,false),nil,'click is not a time range')
local notes={note(.1,.6,60),note(.8,1.1,64)}
M.move(notes,.25,7,0); close(notes[1].s,.35); close(notes[2].s,1.05); eq(notes[2].pitch,71)
M.move(notes,-100,100,0); close(notes[1].s,0); eq(notes[2].pitch,127); eq(notes[1].pitch,123)
notes={note(0,.5,60),note(1,1.25,64)}
M.resize(notes,-1,'right',0,nil,.01); close(notes[1].e,.26); close(notes[2].e,1.01)
M.resize(notes,-1,'left',0); close(notes[1].s,0); close(notes[2].s,1)
notes={note(.25,.5,60)}
local range=M.duplicate(notes,.25,{0,1}); close(notes[2].s,1.25); close(range[1],1); close(range[2],2)
eq(notes[1].selected,false); eq(notes[2].selected,true)
range=M.duplicate(notes,.25,range); close(notes[3].s,2.25); close(range[2],3)
notes={note(.125,.375,60)}; range=M.duplicate(notes,.25); close(notes[2].s,.625)
notes={note(-.1,1.1,60)}; M.duplicate(notes,.25,{0,1}); close(notes[2].s,1); close(notes[2].e,2)
notes={note(0,.25,60)}; eq(M.duplicate(notes,.25,{2,3}),nil); eq(notes[1].selected,true)
notes={note(.13,.63,60),note(.63,1.13,64)}
M.move(notes,M.drag_delta(.13,.25,.25),12,0)
close(notes[1].s,.5); close(notes[2].s,1); eq(notes[1].pitch,72); eq(notes[2].pitch,76)
close(notes[1].e-notes[1].s,.5,'move preserves length')

local function evt(delta,flags,...) return string.pack('i4Bs4',delta,flags,string.char(...)) end
local cc=string.char(0xB3,1,80)
local shape=string.char(0xFF,15)..'CCBZ '..string.char(0,0,0,0,0)
local raw=evt(0,5,0x93,60,100)..string.pack('i4Bs4',60,0x50,cc)
  ..string.pack('i4Bs4',0,0,shape)..evt(60,3,0x83,60,47)
  ..string.pack('i4Bs4',10,0,string.char(0xF0,1,2,0xF7))..evt(350,0,0xB0,123,0)
local decoded=M.decode(raw,function(t) return t/960 end)
eq(#decoded.notes,1); close(decoded.notes[1].e,.125); eq(decoded.notes[1].channel,3)
eq(M.encode(decoded,M.copy(decoded.notes),function(q) return q*960 end),raw,'no-op byte exact')
notes=M.copy(decoded.notes); M.move(notes,.25,2,0)
local encoded=M.encode(decoded,notes,function(q) return q*960 end)
local result=M.decode(encoded,function(t) return t/960 end)
close(result.notes[1].s,.25); close(result.notes[1].e,.375); eq(result.notes[1].pitch,62)
eq(result.notes[1].off.msg:byte(3),47,'release velocity preserved')
eq(result.notes[1].on.flags,5,'unknown note flag bits preserved')
local retained={}
for _,e in ipairs(result.events) do if not e.note_id then retained[#retained+1]=e end end
eq(retained[1].msg,cc); eq(retained[1].pos,60); eq(retained[1].flags,0x50)
eq(retained[2].msg,shape); eq(retained[2].pos,60); eq(retained[3].msg,string.char(0xF0,1,2,0xF7))
-- A longer phrase unfolds audible repetitions, preserving MIDI expression.
local unfolded=M.decode(P.materialize(decoded,0,960))
eq(#unfolded.notes,2); eq(unfolded.end_ppq,960)
eq(unfolded.notes[2].s,480); eq(unfolded.notes[2].e,600)
eq(unfolded.notes[2].on.flags,5); eq(unfolded.notes[2].off.flags,3)
eq(unfolded.notes[2].off.msg:byte(3),47)
local messages={}
for _,e in ipairs(unfolded.events) do if not e.note_id and e.pos==540 then messages[#messages+1]=e end end
eq(messages[1].msg,cc); eq(messages[1].flags,0x50); eq(messages[2].msg,shape)
local partial=M.decode(P.materialize(decoded,60,540))
eq(#partial.notes,2); eq(partial.notes[1].s,0); eq(partial.notes[1].e,60)
eq(partial.notes[2].s,420); eq(partial.notes[2].e,480)
-- Re-extension first restores hidden source notes byte-for-byte; only newly
-- added time beyond the retained source is filled with the current phrase.
eq(P.extend(decoded,0,240,240),decoded.raw)
eq(P.extend(decoded,0,240,480),decoded.raw)
local extended=M.decode(P.extend(decoded,0,240,960))
eq(#extended.notes,3); eq(extended.notes[2].s,480); eq(extended.notes[3].s,720)
eq(extended.notes[1].off.msg,decoded.notes[1].off.msg)
notes=M.copy(decoded.notes); notes[1].id=nil; notes[1].s=.75; notes[1].e=1
result=M.decode(M.encode(decoded,notes,function(q) return q*960 end,960))
eq(#result.notes,1); eq(result.notes[1].s,720); eq(result.end_ppq,960)
eq(result.notes[1].off.msg:byte(3),47,'duplicate preserves release velocity')
result=M.decode(M.encode(decoded,{},nil)); eq(#result.notes,0); eq(#result.events,4)
-- Zero-velocity note-ons are valid note-offs, including their encoding.
raw=evt(0,0,0x91,62,80)..evt(120,0,0x91,62,0)..evt(360,0,0xB0,123,0)
decoded=M.decode(raw); notes=M.copy(decoded.notes); notes[1].vel=110
result=M.decode(M.encode(decoded,notes)); eq(result.notes[1].off.msg:byte(1),0x91)
-- Overlapping notes of the same pitch are matched FIFO; unmatched events survive.
raw=evt(0,0,0x90,60,100)..evt(10,0,0x90,60,90)..evt(10,0,0x80,60,1)..evt(10,0,0x80,60,2)
  ..evt(1,0,0x90,72,90)..evt(69,0,0xB0,123,0)
decoded=M.decode(raw); eq(#decoded.notes,2); eq(decoded.notes[1].e,20); eq(decoded.notes[2].e,30)
notes=M.copy(decoded.notes); notes[1].pitch=65
result=M.decode(M.encode(decoded,notes)); eq(#result.notes,2); eq(result.events[#result.events-1].msg:byte(2),72)

-- Mirrors REAPER: a numeric command ID is stored and read back as its named ID;
-- '_RS... c' is not understood and becomes "No action" ('0').
local mapping='6 m'; local state={}
local registered
local function set_modifier(_,_,v)
  if v:match('^%d+$') then mapping=v=='123' and '_RS_LIVE' or v
  elseif v:match(' m$') or v=='-1' then mapping=v
  else mapping='0' end
end
local r={AddRemoveReaScript=function(_,_,path) registered=registered or path; return 123 end,
  ReverseNamedCommandLookup=function() return 'RS_LIVE' end,
  GetMouseModifier=function() return mapping end,SetMouseModifier=set_modifier,
  GetExtState=function(_,k) return state[k] or '' end,SetExtState=function(_,k,v) state[k]=v end,
  DeleteExtState=function(_,k) state[k]=nil end}
eq(I.install(r,'R/'),123); eq(registered,'R/Fluent MIDI Editor - Open.lua'); eq(mapping,'_RS_LIVE'); eq(state.previous_double_click,'6 m')
I.install(r,'R/'); eq(state.previous_double_click,'6 m','reinstall preserves original')
local restored=I.restore(r); eq(restored,true); eq(mapping,'6 m')
I.install(r,'R/'); mapping='another action c'; restored=I.restore(r); eq(restored,false); eq(mapping,'another action c')
-- 0.9.0 left "No action" behind; restore must repair it.
state={previous_double_click='6 m',double_click_command='_RS_LIVE c'}; mapping='0'
restored=I.restore(r); eq(restored,true); eq(mapping,'6 m')
-- A rejected action is reported and the previous one is put back.
state={}; mapping='6 m'; r.SetMouseModifier=function(_,_,v) mapping=v:match('^%d+$') and '0' or v end
local id,err=I.install(r,'R/'); eq(id,nil); assert(err:match('did not accept')); eq(mapping,'6 m')
-- Links open through SWS when it is installed.
local opened; I.open_url({CF_ShellExecute=function(u) opened=u end},I.links.discord); eq(opened,'https://discord.gg/F6TJ6SDHcV')
return count

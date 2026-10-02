-- With Repeat phrase on, what plays past the phrase end is its repeats.
-- Lengthening the phrase pulls those repeats in (guide: "With repeat on,
-- lengthening the phrase pulls the next repeats into editing"), not notes an
-- earlier shortening hid in the source. Lengthening past the group adds more.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
T.reset()
local call=T.midi_item(0,8,{{60,0,1},{62,4,5}},'Call')
local response=T.midi_item(0,16,{{48,0,1}},'Response')
local S=T.session(call,response); local L=T.load('length')
T.ok(S:set_repeating(true,false))
local function heard()
  local got={}
  for _,n in ipairs(S.notes) do if n.take_index==1 then got[#got+1]=n.pitch..'@'..n.s end end
  for _,n in ipairs(S.ghosts) do if n.take_index==1 then got[#got+1]=n.pitch..'@'..n.s end end
  table.sort(got,function(a,b) return tonumber(a:match('@(.*)'))<tonumber(b:match('@(.*)')) end)
  return table.concat(got,' ')
end
T.ok(S:resize_phrase(L,1,false))
T.eq(heard(),'60@0.0 60@4.0 60@8.0 60@12.0','1-bar phrase repeated')
T.ok(S:resize_phrase(L,4,false))
T.eq(heard(),'60@0.0 60@4.0 60@8.0 60@12.0','after lengthening to 4 bars')
T.eq(#S.ghosts,0,'no repeats left'); T.eq(#S.notes,5,'all four passes and the response are editable')
T.ok(S:resize_phrase(L,6,false))
T.eq(heard(),'60@0.0 60@4.0 60@8.0 60@12.0 60@16.0 60@20.0','past the end of the group')
T.ok(S:resize_phrase(L,2,false)); T.ok(S:resize_phrase(L,4,false,true))
T.eq(heard(),'60@0.0 60@4.0 60@8.0 60@12.0','×2 of a repeating phrase')
print('lengthening a repeating phrase pulls in its repeats')

-- The layout audit (theme.lua, docs/design.md): in every state and at the
-- default and the smallest window size, no control overlaps another, leaves
-- its panel or breaks the control height.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
local SIZES={{1180,780},{780,580}}
local found={}
local function check(state)
  return function()
    local problems=T.audit_problems()
    if problems~='' then found[#found+1]=state..':\n  '..problems:gsub('\n','\n  ') end
    return true
  end
end
local function states(build,name)
  local steps={function() T.close_editor(); return true end,0.5,function() T.reset(); build(); return true end}
  for _,s in ipairs(T.open_steps()) do steps[#steps+1]=s end
  for _,size in ipairs(SIZES) do
    steps[#steps+1]=function() T.resize(size[1],size[2]); return true end
    steps[#steps+1]=1.0
    steps[#steps+1]=check(name..' at '..size[1]..'x'..size[2])
  end
  -- Leave the default size for the tests that follow.
  steps[#steps+1]=function() T.resize(SIZES[1][1],SIZES[1][2]); return true end
  steps[#steps+1]=0.5
  return steps
end
local function two_clips_with_lane()
  local call=T.midi_item(0,4,{{60,0,1},{64,1,2},{67,2,3},{72,3,3.5}},'Call')
  local response=T.midi_item(0,8,{{48,0,2},{55,2,4}},'Response')
  local S=T.session(call,response); S:set_repeating(true,false)
  S=T.session(r.GetTrackMediaItem(r.GetTrack(0,0),0),r.GetTrackMediaItem(r.GetTrack(0,1),0))
  local A=T.load('modulation')
  T.write_lane(S,A.new_lane(0,74,0,4,.3,'Cutoff'))
  T.select(r.GetTrackMediaItem(r.GetTrack(0,0),0),r.GetTrackMediaItem(r.GetTrack(0,1),0))
end
local function one_clip() T.select((T.midi_item(0,16,{{60,0,1},{72,4,6}},'Piano'))) end
-- MPE editing on: an MPE clip (bend range), then a plain one (Convert to MPE).
local function mpe(plain)
  return function()
    r.SetExtState('FluentMIDIEditor','expression','1',true)
    local item,take=T.midi_item(0,8,{},'MPE')
    local msgs=plain and {{0,'\144\60\100'},{960,'\128\60\0'}} or
      {{0,'\225\0\64'},{0,'\145\60\100'},{960,'\129\60\0'},{960,'\226\0\70'},{960,'\146\64\100'},{1920,'\130\64\0'}}
    local parts,last={},0
    for _,e in ipairs(msgs) do parts[#parts+1]=string.pack('i4Bs4',e[1]-last,0,e[2]); last=e[1] end
    parts[#parts+1]=string.pack('i4Bs4',7680-last,0,'\176\123\0')
    r.MIDI_SetAllEvts(take,table.concat(parts)); r.MIDI_Sort(take)
    T.select(item)
  end
end
return T.steps(T.concat(
  states(two_clips_with_lane,'two clips and a modulation lane'),
  states(one_clip,'one clip'),
  states(mpe(false),'MPE editing'),
  states(mpe(true),'MPE editing on a plain clip'),
  {function() r.SetExtState('FluentMIDIEditor','expression','0',true); return true end},
  states(function() end,'no clip selected'),
  {function()
    T.close_editor()
    T.eq(#found,0,'layout problems\n'..table.concat(found,'\n'))
    print('no overlaps in 5 states at 2 sizes')
    return true
  end}),120)

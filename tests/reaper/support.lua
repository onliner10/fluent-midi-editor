-- Helpers for tests/reaper/*_test.lua. Those run inside a live REAPER through
-- tools/reaper/reaper.sh, which provides ROOT (the repository) and print().
local r=reaper
local T={lib=ROOT..'/MIDI Editor/lib/',open=ROOT..'/MIDI Editor/Fluent MIDI Editor - Open.lua'}

function T.load(name) return dofile(T.lib..name..'.lua') end
function T.eq(a,b,label)
  if a~=b then error((label or 'values differ')..': '..tostring(a)..' ~= '..tostring(b),2) end
end
function T.ok(value,label) if not value then error(label or 'assertion failed',2) end return value end

-- Empty project and no running editor, so every test starts from the same state.
function T.reset()
  r.SetExtState('FluentMIDIEditor','instance','',false)
  for _,k in ipairs({'heartbeat','error','focus','target'}) do r.DeleteExtState('FluentMIDIEditor',k,false) end
  r.SelectAllMediaItems(0,false)
  for i=r.CountTracks(0)-1,0,-1 do r.DeleteTrack(r.GetTrack(0,i)) end
  r.SetEditCurPos(0,false,false)
  r.Undo_OnStateChange('Test: reset')
end

-- A MIDI item on a new track. notes: {{pitch,start_qn,end_qn},...} relative to the item.
function T.midi_item(start_qn,length_qn,notes,name)
  local index=r.CountTracks(0); r.InsertTrackAtIndex(index,true)
  local track=r.GetTrack(0,index)
  if name then r.GetSetMediaTrackInfo_String(track,'P_NAME',name,true) end
  local item=r.CreateNewMIDIItemInProj(track,r.TimeMap2_QNToTime(0,start_qn),
    r.TimeMap2_QNToTime(0,start_qn+length_qn),false)
  local take=r.GetActiveTake(item)
  for _,n in ipairs(notes or {}) do
    r.MIDI_InsertNote(take,false,false,r.MIDI_GetPPQPosFromProjQN(take,start_qn+n[2]),
      r.MIDI_GetPPQPosFromProjQN(take,start_qn+n[3]),0,n[1],100,true)
  end
  r.MIDI_Sort(take)
  -- An undo point per setup step, so a test's Undo stops at its own setup.
  r.Undo_OnStateChange('Test: add clip')
  return item,take,track
end

function T.select(...)
  r.SelectAllMediaItems(0,false)
  for _,item in ipairs({...}) do r.SetMediaItemSelected(item,true) end
  r.UpdateArrange()
end

-- Notes of a take as {pitch,start_qn,end_qn} sorted by start then pitch.
function T.notes(take)
  local out={}
  local _,count=r.MIDI_CountEvts(take)
  for i=0,count-1 do
    local _,_,_,s,e,_,pitch=r.MIDI_GetNote(take,i)
    out[#out+1]={pitch,r.MIDI_GetProjQNFromPPQPos(take,s),r.MIDI_GetProjQNFromPPQPos(take,e)}
  end
  table.sort(out,function(a,b) if a[2]~=b[2] then return a[2]<b[2] end return a[1]<b[1] end)
  return out
end

-- Run the Open action as REAPER would (its own script instance, deferred loop).
function T.open_editor()
  local id=r.AddRemoveReaScript(true,0,T.open,true)
  T.ok(id~=0,'could not register the Open action')
  r.Main_OnCommand(id,0)
end
function T.editor_running()
  local stamp=tonumber(r.GetExtState('FluentMIDIEditor','heartbeat'))
  return stamp and r.time_precise()-stamp<1
end
function T.close_editor() r.SetExtState('FluentMIDIEditor','instance','',false) end

-- Return from a test to keep it running across defer cycles: check() is called
-- each cycle until it returns true (pass) or the timeout (seconds) runs out.
function T.wait(check,timeout)
  local deadline=r.time_precise()+(timeout or 10)
  return function()
    if check() then return true end
    if r.time_precise()>deadline then error('condition not met within '..(timeout or 10)..'s',0) end
  end
end

-- Run steps one after another across defer cycles. A step is a function that
-- returns true when done, or a number of seconds to let the editor draw.
function T.steps(list,timeout)
  local i,resume,deadline=1,nil,r.time_precise()+(timeout or 45)
  return function()
    if r.time_precise()>deadline then error('steps timed out at step '..i,0) end
    local err=r.GetExtState('FluentMIDIEditor','error')
    if err~='' then error('editor failed: '..err,0) end
    if resume then if r.time_precise()<resume then return end; resume=nil; i=i+1 end
    local step=list[i]; if not step then return true end
    if type(step)=='number' then resume=r.time_precise()+step; return end
    if step() then i=i+1 end
  end
end

-- The editor as a fresh instance: the previous one exits on its next defer
-- cycle, so wait for that before running the Open action again.
function T.open_steps()
  return {0.5,function() T.open_editor(); return true end,
    function() return T.editor_running() end,1.0}
end

-- Mouse and keyboard on the virtual display, through xdotool.
local function sh(cmd)
  local ok=os.execute('DISPLAY=:99 '..cmd..' >/dev/null 2>&1')
  if not ok then error('command failed: '..cmd,2) end
end
function T.move(x,y) sh(string.format('xdotool mousemove %d %d',x,y)) end
function T.down(button) sh('xdotool mousedown '..(button or 1)) end
function T.up(button) sh('xdotool mouseup '..(button or 1)) end
function T.keys(...) sh('xdotool key --delay 100 '..table.concat({...},' ')) end
function T.keydown(k) sh('xdotool keydown '..k) end
function T.keyup(k) sh('xdotool keyup '..k) end
-- A press and release with frames in between, as a list of steps.
function T.click_steps(x,y,button)
  return {function() T.move(x,y); return true end,0.3,function() T.down(button); return true end,0.3,
    function() T.up(button); return true end,0.4}
end
function T.drag_steps(x1,y1,x2,y2,button)
  return {function() T.move(x1,y1); return true end,0.3,function() T.down(button); return true end,0.3,
    function() T.move((x1+x2)//2,(y1+y2)//2); return true end,0.3,
    function() T.move(x2,y2); return true end,0.3,function() T.up(button); return true end,0.5}
end
function T.concat(...)
  local out={}; for _,list in ipairs({...}) do
    if type(list)=='table' then for _,s in ipairs(list) do out[#out+1]=s end else out[#out+1]=list end
  end
  return out
end

-- Screen pixels, to find what the editor drew. Returns a reader or nil.
function T.screen()
  local path=os.tmpname()..'.ppm'
  sh('import -window root -depth 8 '..path)
  local f=assert(io.open(path,'rb')); local data=f:read('a'); f:close(); os.remove(path)
  local w,h,maxv,header=data:match('^P6%s+(%d+)%s+(%d+)%s+(%d+)%s()')
  w,h=tonumber(w),tonumber(h)
  return {w=w,h=h,rgb=function(x,y)
    local i=header+(y*w+x)*3; local a,b,c=data:byte(i,i+2); return (a<<16)|(b<<8)|c
  end}
end
-- Bounding box {x1,y1,x2,y2} of pixels with an RGBA colour (alpha ignored).
function T.find(rgba,screen)
  screen=screen or T.screen()
  local want=rgba>>8; local x1,y1,x2,y2
  for y=0,screen.h-1 do for x=0,screen.w-1 do
    if screen.rgb(x,y)==want then
      x1=math.min(x1 or x,x); y1=math.min(y1 or y,y); x2=math.max(x2 or x,x); y2=math.max(y2 or y,y)
    end
  end end
  return x1 and {x1,y1,x2,y2,cx=(x1+x2)//2,cy=(y1+y2)//2}
end
-- Fill colour of a note drawn by the editor: clip colour darkened by velocity.
T.clip_colors={0x76C7BDFF,0xDE9CC5FF,0xE5C377FF,0x89B3EFFF,0xAECF84FF,0xCCAFF2FF}
function T.note_color(velocity,clip)
  return T.load('model').velocity_color(T.clip_colors[clip or 1],velocity)
end

return T

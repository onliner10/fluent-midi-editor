-- Drawing paints one note per grid cell as drawn. Zoomed out, the drawn grid
-- doubles its step until lines are 9 px apart; a stroke across a 1024-bar
-- clip used to paint a 1/16 note into each of 16384 sub-pixel cells and hung
-- REAPER. Zoomed in, a stroke still paints notes of the grid length.
local T=dofile(ROOT..'/tests/reaper/support.lua')
local r=reaper
local item,t0
local function setup(bars)
  return function()
    T.reset()
    item=T.midi_item(0,8,{{60,0,1}},'Keys')
    if bars~=2 then T.ok(T.session(item):resize_phrase(T.load('length'),bars,false)) end
    T.select(item); return true
  end
end
local function stroke()
  local n=T.control('notes'); local y=(n[2]+n[4])//2
  t0=r.time_precise(); return T.drag_steps(n[1]+20,y,n[3]-20,y)
end
local function painted()
  local count,shortest=0,math.huge
  for _,n in ipairs(T.notes(r.GetActiveTake(item))) do if n[1]~=60 then count=count+1; shortest=math.min(shortest,n[3]-n[2]) end end
  return count,shortest
end
local function draw_mode() local c=T.control('Draw'); return T.click_steps(c.cx,c.cy) end
return T.steps(T.concat(setup(1024),T.open_steps(),draw_mode,stroke,
  function()
    T.ok(r.time_precise()-t0<5,string.format('the stroke took %.1fs',r.time_precise()-t0))
    local count,shortest=painted()
    T.ok(count>10 and count<200,'notes painted zoomed out: '..count)
    T.ok(shortest>=4,'zoomed out, painted notes are as long as a drawn cell: '..shortest)
    T.close_editor(); return true
  end,
  setup(2),T.open_steps(),draw_mode,stroke,
  function()
    local count,shortest=painted()
    T.ok(count>3,'notes painted zoomed in: '..count)
    T.eq(shortest,0.25,'zoomed in, painted notes are 1/16 long')
    T.close_editor()
    print('drawing paints one note per drawn cell')
    return true
  end),120)

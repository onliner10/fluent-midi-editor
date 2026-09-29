-- A dockable, clip-based piano roll. REAPER owns the MIDI and transport.
local E={}
function E.run(r,initial_item,dir)
  package.path=r.ImGui_GetBuiltinPath()..'/?.lua;'..package.path
  local ImGui=require('imgui')('0.10')
  local M=dofile(dir..'model.lua')
  local modulation=dofile(dir..'modulation.lua')
  local L=dofile(dir..'length.lua')
  local note_layout=dofile(dir..'note_layout.lua')
  local rendering=dofile(dir..'render_cache.lua').new(note_layout)
  local B=dofile(dir..'session.lua').new(r,M,dofile(dir..'backend.lua'),dofile(dir..'repetition.lua'),dofile(dir..'phrase.lua'))
  local audition=dofile(dir..'preview.lua').new(r)
  local integration=dofile(dir..'integration.lua')
  local ctx=ImGui.CreateContext('Fluent MIDI Editor')
  local mod_ui
  local C={bg=0x24272BFF,panel=0x2C3035FF,line=0x41464DFF,text=0xE4E8ECFF,muted=0xA5ADB7FF,
    accent=0xFFAD59FF,note=0x76C7BDFF,black=0x272B30FF,white=0x2E3339FF}
  local black_keys={[1]=true,[3]=true,[6]=true,[8]=true,[10]=true}
  local S={notes={},start=0,span=16,row=53,rowh=19,grid=0.25,triplet=false,snap=true,
    draw=false,fold=false,velocity=100,channel=0,
    cursor=0,follow=false,preview=audition.available,trackFollow=true,range=nil,drag=nil,clipboard=nil,
    status='Ready',lastPoll=0,fit=true,rows={},help=false,open=true,lane=105,focus=true,
    matchLoop=r.GetExtState('FluentMIDIEditor','lengthLoop')~='0',lengthEditing=false}
  local saved={'grid','velocity','channel','rowh','lane'}
  for _,k in ipairs(saved) do S[k]=tonumber(r.GetExtState('FluentMIDIEditor',k)) or S[k] end
  S.grid=M.clamp(S.grid,1/128,4); S.velocity=M.clamp(S.velocity,1,127)
  S.channel=M.clamp(S.channel,0,15); S.rowh=M.clamp(S.rowh,10,42); S.lane=M.clamp(S.lane,65,220)
  local token=tostring(r.time_precise())
  local palette={0x76C7BDFF,0xDE9CC5FF,0xE5C377FF,0x89B3EFFF,0xAECF84FF,0xCCAFF2FF}
  local function clip_color(index) return palette[((index or B.active)-1)%#palette+1] end
  local velocity_colors={}
  for i,color in ipairs(palette) do
    velocity_colors[i]={}; for v=1,127 do velocity_colors[i][v]=M.velocity_color(color,v) end
  end
  local function clip_info(b)
    -- Session reads also refresh meter, offsets and native/managed repeats.
    if S.infoSource~=B.notes then S.infoSource=B.notes; S.clipInfo={} end
    local info=S.clipInfo[b]
    if not info then
      local ending=b.item_view_end
      for _,cycle in ipairs(b.repeats) do ending=math.max(ending,cycle.e) end
      info={phrase=L.phrase_bars(r,b),item=L.format(L.bars(r,b)),
        visible=L.format(L.span_bars(r,B.project,B.origin+b.view_start,B.origin+b.view_end)),
        ending=ending,extent=L.format(L.span_bars(r,B.project,b.item_start,B.origin+ending))}
      info.label=L.format(info.phrase); S.clipInfo[b]=info
    end
    return info
  end
  r.SetExtState('FluentMIDIEditor','instance',token,false)
  local function stop_preview() audition:stop() end
  local function preview(pitch)
    if S.preview and B:valid() then audition:play(B.project,B.track,pitch,S.velocity,S.channel) end
  end
  local function rows()
    local used={}; for _,n in ipairs(S.notes) do used[n.pitch]=true end
    for _,n in ipairs(B.ghosts) do used[n.pitch]=true end
    S.rows={}; S.rowIndex={}
    for p=127,0,-1 do
      if not S.fold or not next(used) or used[p] then S.rows[#S.rows+1]=p; S.rowIndex[p]=#S.rows end
    end
  end
  local function attach(items)
    if mod_ui then mod_ui:reset() end
    stop_preview(); S.drag=nil; S.range=nil; S.lengthEdit=nil; S.lengthEditing=false; S.lengthError=nil
    S.notes=M.copy(B:attach(items or {}) or {}); S.start=0; S.cursor=0; S.fit=true
    rows()
    if B.take then S.span=math.max(4,B.view_length or B.length); S.status='Clips: '..#B.clips..' · New notes: '..B.track_name end
  end
  local initial=B:selected_items()
  if #initial==0 and initial_item then initial={initial_item} end
  attach(initial)
  local function reload(keep_capture)
    if mod_ui then mod_ui:reset(keep_capture) end
    if B:valid() then S.notes=M.copy(B:read() or {})
    else attach(B:selected_items()) end
    S.drag=nil; S.range=nil; rows()
  end
  local function commit(notes,label,phrase_end,event_edits)
    local ok,message=B:commit(notes,label,phrase_end,event_edits)
    S.status=ok and label or message
    S.notes=M.copy(B.notes or {}); rows()
    return ok
  end
  local function edit(label,fn,phrase_end)
    if not B:valid() then return end
    local notes=M.copy(S.notes); fn(notes); return commit(notes,label,phrase_end and phrase_end())
  end
  local function grid() return S.grid*(S.triplet and 2/3 or 1) end
  local function mods()
    return ImGui.IsKeyDown(ctx,ImGui.Mod_Ctrl),ImGui.IsKeyDown(ctx,ImGui.Mod_Shift),ImGui.IsKeyDown(ctx,ImGui.Mod_Alt)
  end
  local function snapping(alt) return S.snap~=alt end
  local function selected_count()
    local count=0; for _,n in ipairs(S.notes) do if n.selected then count=count+1 end end
    return count
  end
  local function deselect() for _,n in ipairs(S.notes) do n.selected=false end end
  local function delete_selected()
    edit('Delete notes',function(notes) for i=#notes,1,-1 do if notes[i].selected then table.remove(notes,i) end end end)
    S.range=nil
  end
  local function duplicate()
    if selected_count()==0 and not S.range then S.status='Select notes or a time range, then press Ctrl+D.'; return end
    local a,z=M.bounds(S.notes,true)
    if S.range then a,z=S.range[1],S.range[2]
    elseif a and S.snap then a=M.floor(a,grid()); z=math.ceil(z/grid()-1e-8)*grid() end
    if not a or z<=a then return end
    local notes=M.copy(S.notes); local range=M.duplicate(notes,0,{a,z}) or {z,z+z-a}
    local event_edits={}; local affected={}
    for _,n in ipairs(S.notes) do if n.selected then affected[n.take_index]=true end end
    for i,b in ipairs(B.clips) do if affected[i] or S.range then
      local start,finish=math.max(a,b.view_start),math.min(z,b.view_end)
      if finish>start then
        local fragment=modulation.copy_range(b.source,b.to_ppq(start-b.offset_in_view),b.to_ppq(finish-b.offset_in_view))
        if #fragment.events>0 then
          local destination=b.to_ppq(start+z-a-b.offset_in_view)
          local ending=range[2]-b.offset_in_view
          event_edits[i]={raw=modulation.insert_range(b.source,fragment,destination,math.max(b.source.end_ppq,b.to_ppq(ending))),ending=ending}
        end
      end
    end end
    if commit(notes,'Duplicate phrase with modulation',range[2],event_edits) then
      S.range=range
      if range then S.cursor=range[1]; if range[1]>S.start+S.span then S.start=range[1] end end
    end
  end
  local function copy(notes_only)
    local a,z=M.bounds(S.notes,true); if S.range then a,z=S.range[1],S.range[2] end; if not a then return end
    S.clipboard={notes=M.copy(M.selected(S.notes)),origin=a,length=z-a}
    local b=B.clips[B.active]
    if b and not notes_only then
      local start,finish=b.to_ppq(a-b.offset_in_view),b.to_ppq(z-b.offset_in_view)
      local fragment=modulation.copy_range(b.source,start,finish)
      -- Clipboard positions use project beats, so pasting onto a take with a
      -- different PPQ resolution, start offset or playrate stays musical.
      fragment=modulation.retime(fragment,function(pos) return b.from_ppq(pos+start)+b.offset_in_view-a end)
      fragment.length=z-a; S.clipboard.modulation=fragment
    end
    S.status='Copied '..#S.clipboard.notes..' notes'..(notes_only and '' or ' and active clip CC')
  end
  local function paste()
    if not S.clipboard then return end
    local notes=M.copy(S.notes)
      for _,n in ipairs(notes) do n.selected=false end
      for _,original in ipairs(S.clipboard.notes) do
        local n=M.copy(original); n.id=nil; n.take_index=B.active; n.s=n.s-S.clipboard.origin+S.cursor
        n.e=n.e-S.clipboard.origin+S.cursor; n.selected=true; notes[#notes+1]=n
      end
    local edits={}; local b=B.clips[B.active]; local fragment=S.clipboard.modulation
    if b and fragment and #fragment.events>0 then
      local dest=b.to_ppq(S.cursor-b.offset_in_view)
      local events=modulation.retime(fragment,function(pos) return b.to_ppq(pos+S.cursor-b.offset_in_view)-dest end)
      events.length=b.to_ppq(S.cursor+fragment.length-b.offset_in_view)-dest
      local ending=S.cursor+S.clipboard.length-b.offset_in_view
      edits[B.active]={raw=modulation.insert_range(b.source,events,dest,math.max(b.source.end_ppq,b.to_ppq(ending))),ending=ending}
    end
    commit(notes,'Paste notes and modulation',S.cursor+S.clipboard.length,edits)
  end
  local function fit(selection,width,height)
    local a,b,lo,hi=M.bounds(S.notes,selection)
    if selection and not a then return end
    if not selection then
      a=0; b=B.view_length or B.length or 16
      local _,_,ghostLo,ghostHi=M.bounds(B.ghosts)
      if ghostLo then lo=math.min(lo or ghostLo,ghostLo); hi=math.max(hi or ghostHi,ghostHi) end
    end
    S.start=math.max(0,(a or 0)-0.25); S.span=math.max(1,(b or 16)-S.start+0.5)
    if lo then
      local upper=S.rowIndex[hi] or 55; local lower=S.rowIndex[lo] or upper
      local count=lower-upper+5
      S.rowh=M.clamp((height or 420)/math.max(12,count),20,32)
      S.row=math.max(0,(upper+lower)/2-1-(height or 420)/S.rowh/2)
    else S.row=math.max(0,(S.rowIndex[72] or 1)-1) end
    S.fit=false
  end
  local function transport()
    if not B.project or r.EnumProjects(-1,'')~=B.project then return end
    if r.GetPlayStateEx(B.project)&1~=0 then r.OnStopButtonEx(B.project) else r.OnPlayButtonEx(B.project) end
  end
  local function loop_selection()
    if not B:valid() then return end
    local a,b=M.bounds(S.notes,true)
    if S.range then a,b=S.range[1],S.range[2] end
    a,b=a or 0,b or B.length
    r.GetSet_LoopTimeRange2(B.project,true,true,r.TimeMap2_QNToTime(B.project,a+B.origin),
      r.TimeMap2_QNToTime(B.project,b+B.origin),false)
    r.GetSetRepeatEx(B.project,1); S.status='Playback loop set'
  end
  local function key(k,repeat_key) return ImGui.IsKeyPressed(ctx,ImGui['Key_'..k],repeat_key or false) end
  local function shortcuts()
    if mod_ui and mod_ui:shortcuts() then return end
    if not ImGui.IsWindowFocused(ctx,ImGui.FocusedFlags_RootAndChildWindows) or
      S.lengthInputUsed or ImGui.IsAnyItemActive(ctx) and not S.drag then return end
    local ctrl,shift,alt=mods()
    if key('Escape') then
      if S.drag then S.notes=S.drag.before or S.notes; S.drag=nil else deselect(); S.range=nil end
      return
    end
    if S.drag then return end
    if key('Space') then transport() end
    if ctrl then
      if key('A') then S.range=nil; for _,n in ipairs(S.notes) do n.selected=not shift or not n.selected end end
      if key('D') then duplicate()
      elseif key('C') then copy()
      elseif key('X') then copy(true); delete_selected()
      elseif key('V') then paste()
      elseif key('Z') then if shift then r.Undo_DoRedo2(B.project) else r.Undo_DoUndo2(B.project) end; reload()
      elseif key('Y') then r.Undo_DoRedo2(B.project); reload()
      elseif key('L') then loop_selection()
      elseif key('1') then S.grid=math.max(1/128,S.grid/2)
      elseif key('2') then S.grid=math.min(4,S.grid*2)
      elseif key('3') then S.triplet=not S.triplet
      elseif key('4') then S.snap=not S.snap end
      return
    end
    if key('B') then S.draw=not S.draw
    elseif key('F') then S.fold=not S.fold; rows(); S.fit=true
    elseif key('X') then fit(false)
    elseif key('Z') then fit(true)
    elseif key('D') and shift then duplicate()
    elseif key('Delete') or key('Backspace') then delete_selected()
    elseif key('0') then edit('Mute / unmute notes',function(notes) for _,n in ipairs(notes) do if n.selected then n.muted=not n.muted end end end)
    elseif key('Home') then S.start=0; S.cursor=0
    elseif key('End') then S.cursor=B.view_length or B.length or 0; S.start=math.max(0,S.cursor-S.span)
    elseif key('Equal',true) then S.span=math.max(0.25,S.span/1.25)
    elseif key('Minus',true) then S.span=math.min(4096,S.span*1.25)
    elseif key('PageUp',true) then S.row=math.max(0,S.row-(shift and 1 or 12))
    elseif key('PageDown',true) then S.row=math.min(#S.rows-1,S.row+(shift and 1 or 12))
    else
      local dx=(key('RightArrow',true) and 1 or 0)-(key('LeftArrow',true) and 1 or 0)
      local dp=(key('UpArrow',true) and 1 or 0)-(key('DownArrow',true) and 1 or 0)
      if dp~=0 or dx~=0 then
        local step=snapping(alt) and grid() or 1/64
        if selected_count()>0 then
          edit(shift and dx~=0 and 'Change length' or 'Move notes',function(notes)
            local chosen=M.selected(notes); local a=M.bounds(notes,true)
            local anchor=shift and chosen[1].e or a
            local delta=dx*step
            if dx~=0 and snapping(alt) then delta=M.nudge_delta(anchor,dx,grid()) end
            if shift and dx~=0 then M.resize(notes,delta,'right',0)
            else M.move(notes,delta,dp*(shift and 12 or 1),0) end
          end)
        else S.cursor=M.clamp(S.cursor+dx*step,0,B.length or math.huge) end
      end
    end
  end
  local function tip(text)
    if ImGui.IsItemHovered(ctx,ImGui.HoveredFlags_DelayNormal) then ImGui.SetTooltip(ctx,text) end
  end
  local function button(label,active,width)
    if active then ImGui.PushStyleColor(ctx,ImGui.Col_Button,0xA36B37FF) end
    local clicked=ImGui.Button(ctx,label,width or 0,26)
    if active then ImGui.PopStyleColor(ctx) end
    return clicked
  end
  local function text_muted(text) ImGui.TextColored(ctx,C.muted,text) end
  local function header()
    local playing=r.GetPlayState()&1~=0
    if button(playing and 'Stop' or 'Play',playing,52) then transport() end
    tip('Space: play project')
    ImGui.SameLine(ctx)
    if button('Loop',r.GetSetRepeat(-1)>0,48) then
      if r.GetSetRepeat(-1)>0 then r.GetSetRepeat(0) else loop_selection() end
    end
    ImGui.SameLine(ctx)
    if button('Follow',S.follow,60) then S.follow=not S.follow end
    tip('Follow the play cursor')
    ImGui.SameLine(ctx); ImGui.TextColored(ctx,C.text,'  FLUENT MIDI EDITOR')
    ImGui.SameLine(ctx); text_muted(' / Clips: '..#B.clips)
    ImGui.SameLine(ctx)
    if button('Options',false,55) then ImGui.OpenPopup(ctx,'options') end
    if ImGui.BeginPopup(ctx,'options') then
      if ImGui.MenuItem(ctx,'Set as default editor (MIDI double-click)') then
        local ok,err=integration.install(r,dir:sub(1,-5)) -- dir ends in 'lib/'
        S.status=ok and 'Double-clicking a MIDI clip opens Fluent MIDI Editor' or err
      end
      if ImGui.MenuItem(ctx,'Restore previous double-click') then local _,message=integration.restore(r); S.status=message end
      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx,'Dock in REAPER') then S.dockRequest=-1 end
      if ImGui.MenuItem(ctx,'Floating window') then S.dockRequest=0 end
      local changed; changed,S.trackFollow=ImGui.MenuItem(ctx,'Follow selected clips',nil,S.trackFollow)
      if ImGui.MenuItem(ctx,'Open clip in native editor') and B:valid() then
        r.Main_OnCommand(40153,0)
      end
      if ImGui.MenuItem(ctx,'Shortcuts and help') then S.help=not S.help end
      ImGui.EndPopup(ctx)
    end
    ImGui.Separator(ctx)
    if button('Draw [B]',S.draw,77) then S.draw=not S.draw end
    ImGui.SameLine(ctx)
    if button('Fold [F]',S.fold,68) then S.fold=not S.fold; rows(); S.fit=true end
    ImGui.SameLine(ctx)
    if button('Snap [Ctrl+4]',S.snap,102) then S.snap=not S.snap end; tip('Ctrl+4: snap / Alt: temporarily invert snap')
    ImGui.SameLine(ctx); ImGui.SetNextItemWidth(ctx,80)
    local label='1/'..math.floor(4/S.grid+0.5)..(S.triplet and ' T' or '')
    if ImGui.BeginCombo(ctx,'##grid',label) then
      for _,v in ipairs({4,2,1,0.5,0.25,0.125,0.0625,0.03125}) do
        if ImGui.Selectable(ctx,'1/'..math.floor(4/v),S.grid==v) then S.grid=v end
      end
      ImGui.Separator(ctx)
      if ImGui.Selectable(ctx,'Triplets',S.triplet) then S.triplet=not S.triplet end
      ImGui.EndCombo(ctx)
    end
    ImGui.SameLine(ctx)
    if button('Fit [X]',false,57) then fit(false) end
    ImGui.SameLine(ctx); text_muted('Add to: ')
    ImGui.SameLine(ctx); ImGui.TextColored(ctx,clip_color(B.active),B.track_name or '-')
  end
  local function length_controls()
    S.lengthInputUsed=false
    local b=B.clips[B.active]; if not b then S.lengthEditing=false; return end
    local value=clip_info(b).phrase
    if not S.lengthEdit or S.lengthEdit.item~=b.item then
      S.lengthEdit={item=b.item,text=L.format(value)}; S.lengthEditing=false; S.lengthError=nil
    elseif not S.lengthEditing then S.lengthEdit.text=L.format(value) end
    local function apply(bars)
      local showWholeGroup=S.start<=.25 and S.start+S.span>=(B.view_length or B.length)
      local ok,message=B:resize_phrase(L,bars,S.matchLoop)
      if ok then
        S.notes=M.copy(B.notes or {}); rows(); S.range=nil
        if showWholeGroup then S.start=0; S.span=math.max(1,(B.view_length or B.length)+.5) end
        S.lengthEdit.text=clip_info(b).label; S.lengthError=nil
        S.status=b.track_name..': '..S.lengthEdit.text..' bar(s)'..(S.matchLoop and ' - loop matched' or '')
      else S.lengthError=message; S.status=message end
    end
    text_muted('PHRASE LENGTH')
    ImGui.TextColored(ctx,clip_color(B.active),b.track_name)
    ImGui.SetNextItemWidth(ctx,72)
    local wasEditing=S.lengthEditing
    local submitted,text=ImGui.InputText(ctx,'##clip_length',S.lengthEdit.text,
      ImGui.InputTextFlags_EnterReturnsTrue|ImGui.InputTextFlags_AutoSelectAll)
    S.lengthEdit.text=text
    S.lengthEditing=ImGui.IsItemActive(ctx)
    S.lengthInputUsed=S.lengthEditing or wasEditing
    tip((b.looped or b.repeating) and 'Length of the editable phrase. Lengthening pulls the next repeat into the phrase; its notes become editable separately. Enter applies.' or
      'Bars, e.g. 4 or 0.5. Enter applies, Escape cancels. Notes past the end are kept.')
    if S.lengthEditing and not wasEditing then S.lengthError=nil end
    if S.lengthInputUsed and ImGui.IsKeyPressed(ctx,ImGui.Key_Escape) then
      S.lengthEdit.text=L.format(value); S.lengthError=nil; S.lengthEditing=false
    elseif submitted then
      local parsed,message=L.parse(text)
      if parsed then apply(parsed) else S.lengthError=message end
    elseif wasEditing and not S.lengthEditing then S.lengthEdit.text=L.format(value) end
    ImGui.SameLine(ctx); text_muted('bars')
    ImGui.SameLine(ctx)
    if button('÷2##length_half',false,30) then apply(clip_info(b).phrase/2) end
    tip('Halve the clip; keep notes past the end')
    ImGui.SameLine(ctx)
    if button('×2##length_double',false,30) then apply(clip_info(b).phrase*2) end
    tip((b.looped or b.repeating) and 'Double the phrase: make the next repeat editable.' or 'Double the clip length. To duplicate notes: Ctrl+D.')
    local info=clip_info(b); local ending=info.ending
    if ending-b.item_view_start>b.length+1e-7 then
      text_muted('With repeats: '..info.extent..' bars')
    end
    if b.repeat_context_changed then
      ImGui.TextWrapped(ctx,'Repeats come from another set of clips. Press Enter in Length to fit them here.')
    end
    local changed
    if b.looped then
      text_muted('Clip loop source: on')
      tip('Repeating is already stored in REAPER. Edit the first pass; the dashed copies update with it.')
    else
      local toggle,enabled=ImGui.Checkbox(ctx,'Repeat phrase',b.repeating)
      if toggle then
        local ok,message=B:set_repeating(enabled,S.matchLoop)
        S.notes=M.copy(B.notes or {}); rows(); S.range=nil
        S.status=ok and (enabled and 'Repeats play in REAPER; edit the first pass.' or 'Phrase repeat off.') or message
      end
      tip('Repeat this phrase until the end of the longest clip in this group. Later passes are read-only.')
    end
    changed,S.matchLoop=ImGui.Checkbox(ctx,'Loop: all clips',S.matchLoop)
    if changed then r.SetExtState('FluentMIDIEditor','lengthLoop',S.matchLoop and '1' or '0',true) end
    tip('When the length changes, fit the loop range to all clips and repeats. The Loop button turns on looped playback.')
    if S.lengthError then
      ImGui.PushStyleColor(ctx,ImGui.Col_Text,C.accent)
      ImGui.TextWrapped(ctx,S.lengthError); ImGui.PopStyleColor(ctx)
    end
  end
  local function sidebar(height)
    ImGui.PushStyleVar(ctx,ImGui.StyleVar_ItemSpacing,8,4)
    ImGui.PushStyleVar(ctx,ImGui.StyleVar_FramePadding,6,3)
    if ImGui.BeginChild(ctx,'Inspector',230,height,ImGui.ChildFlags_Borders) then
      ImGui.TextColored(ctx,C.muted,'TRACKS / CLIPS')
      ImGui.Spacing(ctx)
      for i,b in ipairs(B.clips) do
        ImGui.PushStyleColor(ctx,ImGui.Col_Text,clip_color(i))
        ImGui.PushStyleColor(ctx,ImGui.Col_Header,(clip_color(i)&0xFFFFFF00)|0x28)
        ImGui.PushStyleColor(ctx,ImGui.Col_HeaderHovered,(clip_color(i)&0xFFFFFF00)|0x40)
        if ImGui.Selectable(ctx,(i==B.active and '> ' or '  ')..b.track_name..' · '..clip_info(b).label..' bars##clip'..i,i==B.active,0,0,24) then
          B:set_active(i); S.channel=b.notes[1] and b.notes[1].channel or 0
          S.status='New notes: '..b.track_name
        end
        ImGui.PopStyleColor(ctx,3)
        tip('Click: add and paste new notes here. Notes on all tracks stay editable without switching.')
        if b.name and b.name~='' and b.name~=b.track_name then text_muted(b.name) end
        if b.native_repeats then text_muted('Clip '..clip_info(b).item..' bars · '..b.native_cycles..' passes') end
        ImGui.Spacing(ctx)
      end
      if #B.clips==0 then ImGui.TextWrapped(ctx,'Select MIDI clips in REAPER.') end
      ImGui.Spacing(ctx); ImGui.Separator(ctx)
      length_controls()
      ImGui.Spacing(ctx); ImGui.Separator(ctx)
      text_muted(selected_count()..' / '..#S.notes..' notes selected')
      ImGui.Spacing(ctx)
      ImGui.SetNextItemWidth(ctx,-1)
      local changed,v=ImGui.SliderInt(ctx,'##velocity',S.velocity,1,127,'Velocity  %d')
      if changed then S.velocity=v end
      if ImGui.IsItemDeactivatedAfterEdit(ctx) and selected_count()>0 then
        edit('Change velocity',function(notes) for _,n in ipairs(notes) do if n.selected then n.vel=S.velocity end end end)
      end
      tip('Default velocity; selected notes take the value when you release the slider')
      if audition.available then _,S.preview=ImGui.Checkbox(ctx,'Preview notes',S.preview) end
      ImGui.Spacing(ctx); ImGui.Separator(ctx)
      text_muted('SHORTCUTS')
      ImGui.Spacing(ctx)
      text_muted('B   draw\nF   fold\nZ   zoom to selection\nX   all clips\n0   mute notes\n\nCtrl+4   snap on/off\nCtrl+D   duplicate time\nShift+↑/↓   octave')
      ImGui.TextWrapped(ctx,'Right-click: pick overlapping notes')
      ImGui.Spacing(ctx)
      ImGui.TextWrapped(ctx,'Ctrl + wheel: zoom time\nAlt + wheel: row height\nShift + wheel: scroll time')
      ImGui.EndChild(ctx)
    end
    ImGui.PopStyleVar(ctx,2)
  end
  local function create_clip()
    local proj=r.EnumProjects(-1,''); local track=r.GetSelectedTrack(proj,0)
    if not track then S.status='Select an instrument track in REAPER.'; return end
    local a,b=r.GetSet_LoopTimeRange2(proj,false,false,0,0,false)
    if b<=a then a=r.GetCursorPositionEx(proj); b=r.TimeMap2_QNToTime(proj,r.TimeMap2_timeToQN(proj,a)+16) end
    r.Undo_BeginBlock2(proj)
    local item=r.CreateNewMIDIItemInProj(track,a,b,false)
    if item then r.SelectAllMediaItems(proj,false); r.SetMediaItemSelected(item,true) end
    r.Undo_EndBlock2(proj,'Fluent MIDI Editor: new clip',-1); r.UpdateArrange()
    attach(item and {item} or {})
  end
  local function canvas(w,h)
    local x,y=ImGui.GetCursorScreenPos(ctx)
    w=math.max(180,w); h=math.max(180,h)
    local header_h=28+22*#B.clips
    local A={x=x,y=y,w=w,h=h,gx=x+64,gy=y+header_h,ry=y+header_h-24,gw=w-64,vh=math.min(S.lane,h*0.3)}
    S.timeline_x=A.gx; S.timeline_w=A.gw
    A.gh=h-header_h-A.vh-40; A.vy=A.gy+A.gh+20; A.bottom=A.vy+A.vh
    if S.fit then fit(false,A.gw,A.gh) end
    S.row=M.clamp(S.row,0,math.max(0,#S.rows-math.floor(A.gh/S.rowh)))
    S.start=math.max(0,S.start)
    local playq=S.cursor
    if B.project and r.GetPlayStateEx(B.project)&1~=0 then
      playq=r.TimeMap2_timeToQN(B.project,r.GetPlayPositionEx(B.project))-B.origin
      if S.follow and (playq<S.start or playq>S.start+S.span) then S.start=math.max(0,playq-S.span*0.1) end
    end
    local dl=ImGui.GetWindowDrawList(ctx)
    local function rect(x1,y1,x2,y2,color) ImGui.DrawList_AddRectFilled(dl,x1,y1,x2,y2,color) end
    local function line(x1,y1,x2,y2,color,width) ImGui.DrawList_AddLine(dl,x1,y1,x2,y2,color,width or 1) end
    local function dashed(x1,y1,x2,y2,color)
      -- Clip on the CPU before emitting dashes. A zoomed-in long note can
      -- otherwise generate thousands of invisible draw calls per frame.
      if y1==y2 then x1=math.max(A.gx,x1); x2=math.min(x+w,x2)
      elseif x1==x2 then
        if x1<A.gx or x1>x+w then return end
        local a,z=math.min(y1,y2),math.max(y1,y2)
        y1=math.max(A.gy,a); y2=math.min(A.bottom,z)
      end
      if x2<x1 or y2<y1 then return end
      local length=math.max(math.abs(x2-x1),math.abs(y2-y1)); if length==0 then return end
      for d=0,length,7 do
        local e=math.min(length,d+4)
        line(x1+(x2-x1)*d/length,y1+(y2-y1)*d/length,x1+(x2-x1)*e/length,y1+(y2-y1)*e/length,color)
      end
    end
    local function text(tx,ty,color,value) ImGui.DrawList_AddText(dl,tx,ty,color,value) end
    local function tx(q) return A.gx+(q-S.start)/S.span*A.gw end
    local function tq(px) return S.start+(px-A.gx)/A.gw*S.span end
    local function py(p) local idx=S.rowIndex[p]; return idx and A.gy+(idx-1-S.row)*S.rowh end
    local function pitch(my) return S.rows[M.clamp(math.floor((my-A.gy)/S.rowh+S.row)+1,1,#S.rows)] end
    local function inside(mx,my,x1,y1,x2,y2) return mx>=x1 and mx<x2 and my>=y1 and my<y2 end
    local function edges(n)
      if n.ghost then return n.s,n.e end
      local b=B.clips[n.take_index]
      return math.max(n.s,b.view_start),math.min(n.e,b.view_end)
    end
    local function editable_time(q)
      local b=B.clips[B.active]
      return not (b.repeating or b.looped) or q>=b.view_start and q<b.view_end-1e-8
    end
    ImGui.InvisibleButton(ctx,'Piano roll',w,h,ImGui.ButtonFlags_MouseButtonLeft|ImGui.ButtonFlags_MouseButtonRight|ImGui.ButtonFlags_MouseButtonMiddle)
    local hovered=ImGui.IsItemHovered(ctx)
    local hint_hovered=hovered and not S.drag and ImGui.IsItemHovered(ctx,ImGui.HoveredFlags_DelayNormal|ImGui.HoveredFlags_Stationary)
    local mx,my=ImGui.GetMousePos(ctx)
    local ctrl,shift,alt=mods()
    local in_grid=inside(mx,my,A.gx,A.gy,x+w,A.gy+A.gh)
    local in_vel=inside(mx,my,A.gx,A.vy,x+w,A.bottom)
    local layout=rendering:update(S.notes,B.ghosts,B.clips,B.notes,B.active)
    local first_row=math.floor(S.row)+1
    local last_row=math.min(#S.rows,math.ceil(S.row+A.gh/S.rowh)+1)
    local visible=rendering:view(S.start,S.span,S.rows[last_row] or 0,S.rows[first_row] or 127)
    local function vertical(n) return note_layout.bounds(layout,n,py(n.pitch),S.rowh) end
    -- Only collisions split a pitch row. Paint and hit testing share geometry.
    local hit
    if in_grid then for j=#visible.notes,1,-1 do
      local entry=visible.notes[j]; local ny,ey=vertical(entry.n)
      if ny and inside(mx,my,tx(entry.a),ny,tx(entry.z),ey) then hit=entry.i; break end
    end end
    local ghost_hit
    if in_grid and not hit then for _,entry in ipairs(visible.ghosts) do local n=entry.n
      local ny,ey=vertical(n)
      if ny and in_grid and inside(mx,my,tx(n.s),ny,tx(n.e),ey) then ghost_hit=n; break end
    end end
    local candidates={}
    if in_grid and (hint_hovered or ImGui.IsMouseClicked(ctx,1)) then
      local p,q=pitch(my),tq(mx)
      for _,entry in ipairs(visible.notes) do
        if entry.n.pitch==p and q>=entry.a and q<entry.z then candidates[#candidates+1]=entry.i end
      end
      if ImGui.IsMouseClicked(ctx,1) then table.sort(candidates,function(a,b)
        local ta,tb=S.notes[a].take_index,S.notes[b].take_index
        return ta==tb and a<b or ta<tb
      end) end
    end
    rect(x,y,x+w,y+h,C.bg)
    rect(x,y,A.gx,A.gy,C.panel)
    rect(A.gx,y,x+w,A.gy,0x36393EFF)
    text(x+9,A.ry+5,C.muted,'NOTE')
    ImGui.DrawList_PushClipRect(dl,x,A.gy,x+w,A.gy+A.gh,true)
    if S.pitchTrack~=B.track or S.pitchChannel~=S.channel or S.pitchPoll~=S.lastPoll then
      S.pitchNames={}; S.pitchTrack=B.track; S.pitchChannel=S.channel; S.pitchPoll=S.lastPoll
    end
    for j=first_row,last_row do
      local p=S.rows[j]; local yy=py(p); local black=black_keys[p%12]
      local background=black and C.black or C.white
      rect(A.gx,yy,x+w,yy+S.rowh,background)
      rect(x,yy,A.gx-1,yy+S.rowh,black and 0x25292EFF or 0x454C55FF)
      line(x,yy+S.rowh-1,x+w,yy+S.rowh-1,0x1E202330)
      if S.rowh>=13 then
        local name=S.pitchNames[p]
        if not name then
          name=M.pitch_name(p)
          if B.track and r.ValidatePtr2(B.project,B.track,'MediaTrack*') then
            local drum=r.GetTrackMIDINoteNameEx(B.project,B.track,p,S.channel)
            if drum and drum~='' then name=drum end
          end
          S.pitchNames[p]=name
        end
        ImGui.DrawList_PushClipRect(dl,x+5,yy,A.gx-3,yy+S.rowh,true)
        text(x+8,yy+math.max(0,(S.rowh-14)/2),C.text,name)
        ImGui.DrawList_PopClipRect(dl)
      end
    end
    ImGui.DrawList_PopClipRect(dl)
    local step=grid(); while A.gw/S.span*step<9 do step=step*2 end
    if S.meterSource~=B.notes then
      S.meterSource=B.notes; S.beatsPerBar=4
      local num,den=r.TimeMap_GetTimeSigAtTime(B.project,B.position or 0)
      if num and den and den>0 then S.beatsPerBar=num*4/den end
    end
    local beats_per_bar=S.beatsPerBar
    ImGui.DrawList_PushClipRect(dl,A.gx,y,x+w,A.bottom,true)
    local first=M.floor(S.start,step)
    for q=first,S.start+S.span+step,step do
      local xx=tx(q); local bar=math.abs(q/beats_per_bar-math.floor(q/beats_per_bar+0.5))<1e-5
      local beat=math.abs(q-math.floor(q+0.5))<1e-5
      line(xx,A.gy,xx,A.gy+A.gh,bar and 0x89939E78 or beat and 0x78838F40 or 0x78838F20)
      line(xx,A.vy,xx,A.bottom,bar and 0x89939E60 or 0x78838F20)
    end
    local ruler_step=beats_per_bar
    while ruler_step*A.gw/S.span<65 do ruler_step=ruler_step*2 end
    for q=M.floor(S.start,ruler_step),S.start+S.span,ruler_step do
      text(tx(q)+5,A.ry+5,C.text,tostring(math.floor(q/beats_per_bar+1.00001)))
    end
    if beats_per_bar*A.gw/S.span>220 then
      for q=math.ceil(S.start),S.start+S.span do
        if q%beats_per_bar~=0 then text(tx(q)+4,A.ry+5,C.muted,string.format('%d.%d',math.floor(q/beats_per_bar)+1,math.floor(q%beats_per_bar)+1)) end
      end
    end
    local length=B.view_length or B.length or 16
    for i,b in ipairs(B.clips) do
      local sy=y+2+(i-1)*22
      local function strip(a,z,label,ghost)
        local nx,ex=math.max(A.gx,tx(a)),math.min(x+w,tx(z))
        if ex<=nx then return end
        rect(nx,sy,ex-1,sy+19,(clip_color(i)&0xFFFFFF00)|(ghost and 0x22 or 0x55))
        if ghost then dashed(nx,sy,ex-1,sy,clip_color(i)); dashed(nx,sy+19,ex-1,sy+19,clip_color(i))
        else line(nx,sy,ex-1,sy,clip_color(i),2) end
        ImGui.DrawList_PushClipRect(dl,nx+4,sy,ex-3,sy+19,true)
        text(nx+5,sy+2,C.text,label)
        ImGui.DrawList_PopClipRect(dl)
        if hint_hovered and inside(mx,my,nx,sy,ex,sy+19) then
          ImGui.SetTooltip(ctx,ghost and (b.track_name..': '..label..'. Edit the first pass.') or
            (b.track_name..': clip '..clip_info(b).item..' bars, phrase '..clip_info(b).label..' bars.'))
        end
      end
      strip(b.view_start,b.view_end,b.track_name..' · '..clip_info(b).visible..' bars · editable',false)
      if B.show_repeats then for _,cycle in ipairs(b.repeats) do strip(cycle.s,cycle.e,'Repeat '..cycle.cycle..' · read-only',true) end end
    end
    if S.range then
      rect(tx(S.range[1]),A.gy,tx(S.range[2]),A.gy+A.gh,0xA5CBE217)
      rect(tx(S.range[1]),A.ry,tx(S.range[2]),A.gy,0xFFAD5935)
      line(tx(S.range[1]),A.ry,tx(S.range[1]),A.gy+A.gh,0xFFAD5970)
      line(tx(S.range[2]),A.ry,tx(S.range[2]),A.gy+A.gh,0xFFAD5970)
    end
    ImGui.DrawList_PopClipRect(dl)
    -- Note geometry and velocity have independent clips; no drawing over controls.
    ImGui.DrawList_PushClipRect(dl,A.gx,A.gy,x+w,A.gy+A.gh,true)
    if tx(length)<x+w then rect(math.max(A.gx,tx(length)),A.gy,x+w,A.gy+A.gh,0x10121570) end
    local function draw_note(n)
      local yy,ey=vertical(n)
      local nh=yy and ey-yy or 0
      local a,b=edges(n)
      if yy and b>S.start and a<S.start+S.span and b>a and yy<A.gy+A.gh and yy+S.rowh>A.gy then
        local nx,ex=tx(a)+1,math.max(tx(a)+2,tx(b)-1)
        local color=n.muted and 0x697279FF or velocity_colors[(n.take_index-1)%#palette+1][n.vel]
        rect(nx,yy+1,ex,yy+nh-1,color)
        if n.ghost then
          dashed(nx,yy+1,ex,yy+1,C.text); dashed(nx,yy+nh-1,ex,yy+nh-1,C.text)
          dashed(nx,yy+1,nx,yy+nh-1,C.text); dashed(ex,yy+1,ex,yy+nh-1,C.text)
        else ImGui.DrawList_AddRect(dl,nx,yy+1,ex,yy+nh-1,(clip_color(n.take_index)&0xFFFFFF00)|0x70) end
        if n.selected then
          ImGui.DrawList_AddRect(dl,nx,yy+1,ex,yy+nh-1,0xFFFFFFFF,0,0,1.5)
        elseif hit and S.notes[hit]==n then
          ImGui.DrawList_AddRect(dl,nx,yy+1,ex,yy+nh-1,clip_color(n.take_index),0,0,1.5)
        end
        if n.muted then line(nx,yy+nh/2,ex,yy+nh/2,0x272D30FF) end
        if ex-nx>34 and nh>=12 then
          local label_x=math.max(nx,A.gx)
          ImGui.DrawList_PushClipRect(dl,label_x+2,yy+1,ex,yy+nh-1,true)
          local label=layout[n].count>1 and B.clips[n.take_index].track_name or M.pitch_name(n.pitch)
          text(label_x+4,yy+(nh-14)/2,n.vel<85 and C.text or 0x18232BFF,label)
          ImGui.DrawList_PopClipRect(dl)
        end
      end
    end
    for _,entry in ipairs(visible.ghosts) do draw_note(entry.n) end
    for _,entry in ipairs(visible.notes) do draw_note(entry.n) end
    if S.drag and S.drag.kind=='select' then
      local d=S.drag
      ImGui.DrawList_AddRect(dl,math.min(d.mx,mx),math.min(d.my,my),math.max(d.mx,mx),math.max(d.my,my),C.accent,0,0,1)
    end
    ImGui.DrawList_PopClipRect(dl)
    rect(x,A.vy-20,x+w,A.vy,0x3C3F43FF); text(x+8,A.vy-18,C.text,'Velocity')
    text(A.gx+13,A.vy-18,C.muted,'1 - 127'); text(x+12,A.vy+4,C.muted,'127'); text(x+30,A.bottom-16,C.muted,'1')
    ImGui.DrawList_PushClipRect(dl,A.gx,A.vy,x+w,A.bottom,true)
    line(A.gx,A.vy+A.vh/2,x+w,A.vy+A.vh/2,0xFFFFFF13)
    local ghost_velocity_hit
    for _,entry in ipairs(visible.ghost_velocity) do local n=entry.n
      local xx=tx(n.s)+(n.take_index-(#B.clips+1)/2)*4; local yy=A.bottom-4-(n.vel-1)/126*(A.vh-10)
      dashed(xx,A.bottom-3,xx,yy,clip_color(n.take_index))
      ImGui.DrawList_AddCircle(dl,xx,yy,3,clip_color(n.take_index))
      if in_vel and math.abs(mx-xx)<8 and math.abs(my-yy)<8 then ghost_velocity_hit=n end
    end
    for _,entry in ipairs(visible.velocity) do local n=entry.n
      local xx=tx(n.s)+(n.take_index-(#B.clips+1)/2)*4; local yy=A.bottom-4-(n.vel-1)/126*(A.vh-10)
      local color=clip_color(n.take_index)
      line(xx,A.bottom-3,xx,yy,n.muted and C.muted or color,n.selected and 2 or 1)
      ImGui.DrawList_AddCircleFilled(dl,xx,yy,n.selected and 4 or 3,color)
    end
    ImGui.DrawList_PopClipRect(dl)
    if playq>=S.start and playq<=S.start+S.span then line(tx(playq),A.ry,tx(playq),A.bottom,C.accent,1.5) end
    local overview_y=y+h-17
    rect(A.gx,overview_y,x+w,y+h,0x1D2023FF)
    local total=math.max(length,S.start+S.span)
    for _,bar in ipairs(rendering:miniature(total,A.gw)) do
      local ny=overview_y+2+bar.row
      local color=clip_color(bar.track)
      rect(A.gx+bar.a,ny,A.gx+bar.z,ny+2,bar.ghost and (color&0xFFFFFF00)|0x70 or color)
    end
    ImGui.DrawList_AddRect(dl,A.gx+S.start/total*A.gw,overview_y,A.gx+(S.start+S.span)/total*A.gw,y+h,C.muted)

    if not B.take then return end
    if hovered and not S.drag then
      if hit and hint_hovered then
        local n=S.notes[hit]
        ImGui.SetTooltip(ctx,B.clips[n.take_index].track_name..' · '..M.pitch_name(n.pitch)..' · Velocity '..n.vel..
          (#candidates>1 and '\nOverlapping notes: click a colored part, or right-click to pick by name.' or ''))
      end
      if hint_hovered and (ghost_hit or ghost_velocity_hit) then ImGui.SetTooltip(ctx,'Repeat — read-only. Edit the note or velocity in the first pass.') end
      local wheel,horizontal=ImGui.GetMouseWheel(ctx)
      if wheel~=0 then
        S.follow=false
        if ctrl then
          local anchor=tq(mx); local fraction=(mx-A.gx)/A.gw
          S.span=M.clamp(S.span*1.2^(-wheel),0.25,4096); S.start=math.max(0,anchor-fraction*S.span)
        elseif alt then
          local anchor=S.row+(my-A.gy)/S.rowh
          S.rowh=M.clamp(S.rowh+wheel*2,10,42); S.row=anchor-(my-A.gy)/S.rowh
        elseif shift then S.start=math.max(0,S.start-wheel*S.span/12)
        else S.row=S.row-wheel*3 end
      end
      if horizontal~=0 then S.start=math.max(0,S.start-horizontal*S.span/12) end
      if in_grid and hit then
        local a,z=edges(S.notes[hit])
        if math.abs(mx-tx(z))<7 or math.abs(mx-tx(a))<5 then ImGui.SetMouseCursor(ctx,ImGui.MouseCursor_ResizeEW) end
      elseif S.draw and in_grid then ImGui.SetMouseCursor(ctx,ImGui.MouseCursor_Hand) end
      if ImGui.IsMouseClicked(ctx,1) then
        if in_grid then
          local before=M.copy(S.notes); if not shift then deselect() end
          S.drag={kind='select',mx=mx,my=my,q=tq(mx),p=pitch(my),before=before,add=shift,right=true,candidates=candidates}
        else ImGui.OpenPopup(ctx,'note_menu') end
      end
      if ImGui.IsMouseClicked(ctx,2) then S.drag={kind='pan',mx=mx,my=my,start=S.start,row=S.row} end
      if ImGui.IsMouseClicked(ctx,0) then
        S.follow=false
        local q=math.max(0,tq(mx)); local p=pitch(my)
        if my>=overview_y then S.drag={kind='overview'}
        elseif inside(mx,my,x,A.gy,A.gx,A.gy+A.gh) then
          if not shift then deselect() end
          for _,n in ipairs(S.notes) do if n.pitch==p then n.selected=true end end
          preview(p)
          S.status=M.pitch_name(p)..' - selected notes at this pitch'
        elseif inside(mx,my,A.gx,A.ry,x+w,A.gy) then
          S.cursor=S.snap and M.snap(q,grid()) or q
          r.SetEditCurPos2(B.project,r.TimeMap2_QNToTime(B.project,B.origin+S.cursor),true,false)
          S.drag={kind=shift and 'time' or 'ruler',mx=mx,my=my,start=S.start,span=S.span,q=q,before=M.copy(S.notes)}
          if ImGui.IsMouseDoubleClicked(ctx,0) then fit(selected_count()>0,A.gw,A.gh); S.drag=nil end
        elseif inside(mx,my,x,A.vy-20,x+w,A.vy) then
          S.drag={kind='lane',my=my,lane=S.lane}
        elseif in_vel then
          local closest,dist
          for _,entry in ipairs(visible.velocity) do local i,n=entry.i,entry.n
            local yy=A.bottom-4-(n.vel-1)/126*(A.vh-10)
            local xx=tx(n.s)+(n.take_index-(#B.clips+1)/2)*4
            local d=math.abs(xx-mx)+math.abs(yy-my)*0.4
            if math.abs(xx-mx)<9 and (not dist or d<dist) then closest,dist=i,d end
          end
          if closest then
            if not S.notes[closest].selected then if not shift then deselect() end; S.notes[closest].selected=true end
            S.velocity=S.notes[closest].vel
            S.drag={kind='velocity',before=M.copy(S.notes),my=my,mx=mx,index=closest,changed=false,inlane=true}
          elseif ghost_velocity_hit then S.status='Repeat velocity is read-only.'
          elseif S.draw then S.drag={kind='velocity_draw',before=M.copy(S.notes),changed=false,lastq=q} end
        elseif in_grid then
          local dbl=ImGui.IsMouseDoubleClicked(ctx,0)
          if S.draw and hit and S.notes[hit].take_index~=B.active then hit=nil end
          if (ghost_hit and not hit) or ((S.draw or dbl) and not hit and not editable_time(q)) then
            S.status='Repeats are read-only. Edit the first pass of the phrase.'
          elseif S.draw or dbl then
            rendering:invalidate()
            local before=M.copy(S.notes)
            if hit then table.remove(S.notes,hit)
            else
              deselect(); local start=snapping(alt) and M.floor(q,grid()) or q
              S.notes[#S.notes+1]={s=start,e=start+grid(),pitch=p,vel=S.velocity,channel=S.channel,selected=true,muted=false,take_index=B.active}; preview(p)
            end
            S.drag={kind=S.draw and 'draw' or 'add',before=before,changed=true,lastcell=math.floor(q/grid()),pitch=p,erase=hit~=nil,visited={}}
            S.drag.visited[math.floor(q/grid())..':'..p]=true
          elseif hit then
            local n=S.notes[hit]
            B:set_active(n.take_index)
            S.velocity=n.vel; S.channel=n.channel
            if shift then n.selected=not n.selected
            elseif not n.selected then deselect(); n.selected=true end
            S.range=nil
            if n.selected then
              preview(n.pitch)
              -- Grab the drawn edge. A note running past the pass end is drawn
              -- clipped there; its hidden overhang is trimmed so the edge
              -- follows the mouse from where the user grabbed it.
              local a,z=edges(n)
              local kind=math.abs(mx-tx(z))<7 and 'right' or math.abs(mx-tx(a))<5 and 'left' or alt and 'velocity' or 'move'
              local before=M.copy(S.notes)
              if ctrl and kind=='move' then
                rendering:invalidate()
                for _,c in ipairs(M.copy(M.selected(S.notes))) do c.id=nil; S.notes[#S.notes+1]=c end
                for i=1,#before do S.notes[i].selected=false end
              end
              S.drag={kind=kind,mx=mx,my=my,q=q,p=p,before=before,base=M.copy(S.notes),index=hit,anchor=n.s,anchorEnd=n.e,changed=ctrl and kind=='move',
                shown=kind=='left' and a or kind=='right' and z or nil}
            end
          else
            local before=M.copy(S.notes)
            if not shift then deselect() end
            S.cursor=S.snap and M.floor(q,grid()) or q
            S.drag={kind='select',mx=mx,my=my,q=q,p=p,before=before,add=shift}
          end
        end
      end
    end
    if S.drag then
      local d=S.drag
      if d.kind=='pan' then S.start=math.max(0,d.start-(mx-d.mx)/A.gw*S.span); S.row=d.row-(my-d.my)/S.rowh
      elseif d.kind=='overview' then S.start=M.clamp((mx-A.gx)/A.gw*total-S.span/2,0,math.max(0,total-S.span))
      elseif d.kind=='lane' then S.lane=M.clamp(d.lane+d.my-my,65,220)
      elseif d.kind=='ruler' then
        if ImGui.IsMouseDragging(ctx,0,4) then
          S.span=M.clamp(d.span*1.01^(my-d.my),0.25,4096)
          S.start=math.max(0,d.q-(d.mx-A.gx)/A.gw*S.span-(mx-d.mx)/A.gw*S.span)
        end
      elseif d.kind=='time' then
        local a,b=math.max(0,math.min(d.q,tq(mx))),math.max(d.q,tq(mx))
        S.range={S.snap and M.floor(a,grid()) or a,S.snap and math.ceil(b/grid())*grid() or b}
        for _,n in ipairs(S.notes) do n.selected=n.s<S.range[2] and n.e>S.range[1] end
      elseif d.kind=='select' then
        local q1,q2=math.min(d.q,tq(mx)),math.max(d.q,tq(mx))
        local y1,y2=math.min(d.my,my),math.max(d.my,my)
        for i,n in ipairs(S.notes) do
          local ny,ey=vertical(n); local a,z=edges(n)
          n.selected=(d.add and d.before[i].selected) or (ny~=nil and a<q2 and z>q1 and ny<y2 and ey>y1)
        end
        d.moved=d.moved or math.abs(mx-d.mx)>=4 or math.abs(my-d.my)>=4
        S.range=M.selection_range(d.q,tq(mx),S.snap and grid() or 0,d.moved)
      elseif d.kind=='draw' and in_grid then
        local q=math.max(0,tq(mx)); local p=pitch(my); local cell=math.floor(q/grid())
        local low,high=math.min(cell,d.lastcell),math.max(cell,d.lastcell)
        for c=low,high do
          local id=c..':'..p
          if not d.visited[id] and editable_time(c*grid()) then
            rendering:invalidate()
            d.visited[id]=true
            if d.erase then
              for i=#S.notes,1,-1 do local n=S.notes[i]; if n.take_index==B.active and n.pitch==p and n.s<(c+1)*grid() and n.e>c*grid() then table.remove(S.notes,i) end end
            else
              local occupied=false
              for _,n in ipairs(S.notes) do if n.take_index==B.active and n.pitch==p and n.s<(c+1)*grid() and n.e>c*grid() then occupied=true; break end end
              if not occupied then S.notes[#S.notes+1]={s=c*grid(),e=(c+1)*grid(),pitch=p,vel=S.velocity,channel=S.channel,selected=true,muted=false,take_index=B.active} end
            end
          end
        end
        d.lastcell=cell
      elseif d.kind=='velocity_draw' and in_vel then
        local q=tq(mx); local a,b=math.min(d.lastq,q)-S.span/A.gw*5,math.max(d.lastq,q)+S.span/A.gw*5
        for _,n in ipairs(S.notes) do if n.s>=a and n.s<=b then n.vel=M.clamp(math.floor((A.bottom-my)/A.vh*127+0.5),1,127); d.changed=true end end
        d.lastq=q
      elseif (d.kind=='move' or d.kind=='left' or d.kind=='right' or d.kind=='velocity') and ImGui.IsMouseDragging(ctx,0,3)
        and (mx~=d.lastX or my~=d.lastY or alt~=d.lastAlt) then
        d.lastX,d.lastY,d.lastAlt=mx,my,alt
        local delta=(mx-d.mx)/A.gw*S.span
        local dp,dv=0,0
        if d.kind=='move' then
          delta=math.abs(mx-d.mx)<3 and 0 or M.drag_delta(d.anchor,delta,snapping(alt) and grid() or 0)
          dp=pitch(my)-d.p
        elseif d.kind=='velocity' then
          local gain=d.inlane and 126/(A.vh-10) or .7
          delta=0; dv=math.floor((d.my-my)*gain+0.5)
        else
          local anchor=d.kind=='left' and d.anchor or d.anchorEnd
          delta=M.drag_delta(d.shown,delta,snapping(alt) and grid() or 0)+d.shown-anchor
        end
        -- Moving inside one snap cell does not change MIDI geometry. Velocity
        -- only changes appearance, so retain note identities and cached bands.
        if delta~=d.appliedDelta or dp~=d.appliedPitch or dv~=d.appliedVelocity then
          d.appliedDelta,d.appliedPitch,d.appliedVelocity=delta,dp,dv
          local base=d.base or d.before
          if d.kind=='velocity' then
            for i,n in ipairs(S.notes) do if n.selected then n.vel=M.clamp(base[i].vel+dv,1,127) end end
            S.velocity=S.notes[d.index] and S.notes[d.index].vel or S.velocity
          else
            S.notes=M.copy(base)
            if d.kind=='move' then
              M.move(S.notes,delta,dp,0)
              if d.lastPitch~=pitch(my) then preview(pitch(my)); d.lastPitch=pitch(my) end
            else M.resize(S.notes,delta,d.kind,0) end
          end
          d.changed=true
        end
      end
      local release=ImGui.IsMouseReleased(ctx,d.kind=='pan' and 2 or d.right and 1 or 0)
      -- A focus loss cancels an uncommitted gesture instead of writing stale data.
      if not ImGui.IsWindowFocused(ctx,ImGui.FocusedFlags_RootAndChildWindows) then
        S.notes=d.before or S.notes; S.drag=nil
      elseif release then
        S.drag=nil
        if d.right and math.abs(mx-d.mx)<4 and math.abs(my-d.my)<4 then
          S.notes=d.before
          if d.candidates and #d.candidates>1 then
            S.pickCandidates=d.candidates; S.pickAdd=d.add; ImGui.OpenPopup(ctx,'overlap_picker')
          else ImGui.OpenPopup(ctx,'note_menu') end
        end
        if d.changed then commit(S.notes,({draw='Draw notes',add='Add / delete note',move='Move notes',left='Change note start',right='Change note length',velocity='Change velocity',velocity_draw='Draw velocity'})[d.kind] or 'Edit notes') end
      end
    end
    if ImGui.BeginPopup(ctx,'overlap_picker') then
      ImGui.Text(ctx,'Pick a note'); ImGui.Separator(ctx)
      for _,i in ipairs(S.pickCandidates or {}) do local n=S.notes[i]
        if n then
          ImGui.PushStyleColor(ctx,ImGui.Col_Text,clip_color(n.take_index))
          local chosen=ImGui.Selectable(ctx,B.clips[n.take_index].track_name..' · '..M.pitch_name(n.pitch)..' · vel '..n.vel..'##pick'..i,n.selected)
          ImGui.PopStyleColor(ctx)
          if chosen then
            if not S.pickAdd then deselect() end
            n.selected=true; B:set_active(n.take_index); S.velocity=n.vel; S.channel=n.channel; S.range=nil
            S.status='Selected: '..B.track_name..' · '..M.pitch_name(n.pitch)
          end
        end
      end
      ImGui.EndPopup(ctx)
    end
    if ImGui.BeginPopup(ctx,'note_menu') then
      if ImGui.MenuItem(ctx,'Duplicate','Ctrl+D') then duplicate() end
      if ImGui.MenuItem(ctx,'Copy','Ctrl+C') then copy() end
      if ImGui.MenuItem(ctx,'Paste','Ctrl+V') then paste() end
      if ImGui.MenuItem(ctx,'Delete','Delete') then delete_selected() end
      ImGui.Separator(ctx)
      if ImGui.MenuItem(ctx,'Loop selection','Ctrl+L') then loop_selection() end
      if ImGui.MenuItem(ctx,'Show all notes','X') then fit(false) end
      ImGui.EndPopup(ctx)
    end
  end
  local function help()
    if not S.help then return end
    ImGui.SetNextWindowSize(ctx,570,430,ImGui.Cond_FirstUseEver)
    local visible; visible,S.help=ImGui.Begin(ctx,'Fluent MIDI Editor - shortcuts',S.help)
    if visible then
      ImGui.TextWrapped(ctx,'Double-click an empty cell to add a note; double-click a note to delete it. B toggles drawing. Drag a note or its left or right edge, or drag a rectangle to select.')
      ImGui.Separator(ctx)
      ImGui.Text(ctx,'Ctrl+A / Shift+click   Select\nCtrl+C / X / V         Copy / cut / paste\nCtrl+D                 Duplicate time including silence\nShift+drag on ruler    Select a time range\nCtrl+Z / Shift+Ctrl+Z  Undo / redo in REAPER\nCtrl+1 / 2 / 3 / 4     Grid: finer / coarser / triplets / snap\nArrows                 Move notes\nShift+Up / Down        Transpose by an octave\nShift+Left / Right     Change length\nAlt+drag               Velocity (middle of a note)\nCtrl+drag              Copy notes\nF / Z / X / 0          Fold / zoom / all clips / mute\nSpace / Ctrl+L         Transport / loop selection\nMiddle button          Scroll the piano roll')
      ImGui.Separator(ctx)
      ImGui.TextWrapped(ctx,'Select clips on several tracks in REAPER to edit them together; clicking the track list picks where new notes go. Darker notes = lower velocity. Escape cancels a gesture. One gesture = one Undo across all tracks. The note clipboard works inside this window; pasting goes to the active clip.')
      ImGui.End(ctx)
    end
  end
  local function tick()
    if r.GetExtState('FluentMIDIEditor','instance')~=token then return end
    -- Native Undo/project edits may replace item and track pointers between
    -- frames. Rendering cannot wait for the slower 200 ms MIDI-content poll.
    if B.take and not B:valid() then attach(B:selected_items()) end
    local now=r.time_precise()
    audition:tick()
    if not S.lastHeartbeat or now-S.lastHeartbeat>.25 then
      S.lastHeartbeat=now; r.SetExtState('FluentMIDIEditor','heartbeat',tostring(now),false)
    end
    if r.GetExtState('FluentMIDIEditor','focus')=='1' then
      r.DeleteExtState('FluentMIDIEditor','focus',false); S.focus=true
      local chosen=B:selected_items()
      if #chosen>0 and not B:matches(chosen) then attach(chosen) end
      r.DeleteExtState('FluentMIDIEditor','target',false)
    end
    if now-S.lastPoll>0.2 then
      S.lastPoll=now
      if not S.drag and not S.lengthEditing and not (mod_ui and mod_ui:busy()) then
        local chosen=B:selected_items()
        if S.trackFollow and #chosen>0 and not B:matches(chosen) then
          attach(chosen)
        elseif B.take and B:changed() then reload(true) end
      end
    end
    ImGui.SetNextWindowSize(ctx,1180,780,ImGui.Cond_FirstUseEver)
    ImGui.SetNextWindowSizeConstraints(ctx,780,580,10000,10000)
    if S.dockRequest then ImGui.SetNextWindowDockID(ctx,S.dockRequest); S.dockRequest=nil end
    if S.focus then ImGui.SetNextWindowFocus(ctx); S.focus=false end
    ImGui.PushStyleColor(ctx,ImGui.Col_WindowBg,C.bg)
    ImGui.PushStyleColor(ctx,ImGui.Col_ChildBg,C.panel)
    ImGui.PushStyleColor(ctx,ImGui.Col_Button,0x484D53FF)
    ImGui.PushStyleColor(ctx,ImGui.Col_ButtonHovered,0x626971FF)
    ImGui.PushStyleColor(ctx,ImGui.Col_ButtonActive,0x8C6542FF)
    ImGui.PushStyleColor(ctx,ImGui.Col_FrameBg,0x24272BFF)
    ImGui.PushStyleColor(ctx,ImGui.Col_CheckMark,C.accent)
    ImGui.PushStyleColor(ctx,ImGui.Col_SliderGrab,C.note)
    ImGui.PushStyleColor(ctx,ImGui.Col_Text,C.text)
    ImGui.PushStyleColor(ctx,ImGui.Col_Separator,C.line)
    ImGui.PushStyleVar(ctx,ImGui.StyleVar_WindowRounding,3)
    ImGui.PushStyleVar(ctx,ImGui.StyleVar_FrameRounding,2)
    ImGui.PushStyleVar(ctx,ImGui.StyleVar_FramePadding,8,5)
    ImGui.PushStyleVar(ctx,ImGui.StyleVar_ItemSpacing,8,6)
    local visible; visible,S.open=ImGui.Begin(ctx,'Fluent MIDI Editor',S.open,ImGui.WindowFlags_NoScrollbar|ImGui.WindowFlags_NoScrollWithMouse)
    local drawn,draw_error=xpcall(function()
      if visible then
      header()
      local aw,ah=ImGui.GetContentRegionAvail(ctx)
      local contenth=math.max(190,ah-25)
      sidebar(contenth); ImGui.SameLine(ctx)
      if B.take then
        local w=ImGui.GetContentRegionAvail(ctx)
        ImGui.BeginGroup(ctx)
        local mh=mod_ui:layout_height(contenth)
        canvas(w,contenth-mh-6)
        mod_ui:draw(w,mh)
        ImGui.EndGroup(ctx); shortcuts()
      else
        if ImGui.BeginChild(ctx,'Empty',0,contenth) then
          ImGui.Spacing(ctx); ImGui.Spacing(ctx)
          ImGui.Text(ctx,'Your piano roll, inside REAPER')
          ImGui.TextWrapped(ctx,'Select one or more MIDI clips in the arrange view. Their notes appear here together.')
          ImGui.Spacing(ctx)
          if button('Create a MIDI clip on the selected track') then create_clip() end
          ImGui.Spacing(ctx)
          text_muted('B - draw   /   Ctrl+D - duplicate   /   Space - play')
          ImGui.EndChild(ctx)
        end
      end
      ImGui.TextColored(ctx,C.muted,S.status)
      end
    end,debug.traceback)
    -- Preserve the original failure if ReaImGui also rejects cleanup after a
    -- failed nested child/group. The original traceback is the useful one.
    local ended,end_error=true
    if visible then ended,end_error=pcall(ImGui.End,ctx) end
    if drawn then help() end
    pcall(ImGui.PopStyleVar,ctx,4); pcall(ImGui.PopStyleColor,ctx,10)
    if not drawn then error(draw_error,0) end
    if not ended then error(end_error,0) end
    if S.open then r.defer(function()
      local ok,err=xpcall(tick,debug.traceback)
      if not ok then r.SetExtState('FluentMIDIEditor','error',err,false); stop_preview(); r.MB(err,'Fluent MIDI Editor',0) end
    end) end
  end
  r.atexit(function()
    stop_preview()
    if r.GetExtState('FluentMIDIEditor','instance')==token then
      r.DeleteExtState('FluentMIDIEditor','heartbeat',false); r.DeleteExtState('FluentMIDIEditor','instance',false)
      for _,k in ipairs(saved) do r.SetExtState('FluentMIDIEditor',k,tostring(S[k]),true) end
    end
  end)
  mod_ui=dofile(dir..'modulation_ui.lua').new(r,ImGui,ctx,M,modulation,B,S,dir,function()
    S.notes=M.copy(B.notes or {}); rows()
  end)
  tick()
end
return E

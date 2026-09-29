-- The modulation lane shares the piano roll's QN viewport. Gestures only edit a
-- local draft; release writes CC and knot metadata together in one native Undo.
local U={}
function U.new(r,ImGui,ctx,M,A,B,S,dir,on_write)
  local F=dofile(dir..'modulation_fx.lua').new(r,A,M)
  local MIN_HEIGHT=160
  local self={enabled=r.GetExtState('FluentMIDIEditor','modOpen')~='0',lanes={},selected=1,snap=false,
    height=math.max(MIN_HEIGHT,tonumber(r.GetExtState('FluentMIDIEditor','modHeight')) or 275),max_height=MIN_HEIGHT,cc=1,channel=1}
  local C={bg=0x24272BFF,panel=0x2C3035FF,line=0x41464DFF,text=0xE4E8ECFF,muted=0xA5ADB7FF,accent=0xFFAD59FF}
  local function lane() return self.draft or self.lanes[self.selected] end
  function self:busy() return self.drag~=nil or self.pending~=nil or self.numeric~=nil end
  function self:reset(keep_capture)
    self.drag=nil; self.pending=nil; self.numeric=nil; self.draft=nil; self.raw=nil
    if not keep_capture then self.armed=false end
  end
  function self:refresh()
    local b=B.clips[B.active]; if not b then self:reset(); return end
    if self.item~=b.item then self:reset(); self.item=b.item; self.channel=S.channel+1 end
    if self.raw~=b.source.raw and not self:busy() then
      local key=lane() and lane().key
      self.raw=b.source.raw; self.lanes=A.read(b.source,b.from_ppq); self.selected=1
      for i,l in ipairs(self.lanes) do
        if l.key==key then self.selected=i end
        if l.managed then
          l.stale=not A.matches_playback(l,b.source,b.from_ppq,b.to_ppq)
        end
      end
    end
  end
  function self:write(value,label,effect)
    local b=B.clips[B.active]; if not b then return false end
    local ok,raw=pcall(A.write,b.source,{value},b.to_ppq,b.source.end_ppq)
    local message
    if ok then ok,message=B:commit(S.notes,label,nil,{[B.active]={raw=raw}},effect) else message=raw end
    self.draft=nil; self.drag=nil; self.pending=nil; self.numeric=nil; self.raw=nil
    S.status=ok and label or tostring(message); on_write(); self:refresh()
    for i,l in ipairs(self.lanes) do if l.key==value.key then
      self.selected=i
      for _,p in ipairs(l.points) do for _,old in ipairs(value.points or {}) do
        if old.selected and math.abs(p.t-old.t)<1e-5 and math.abs(p.v-old.v)<1e-8 then p.selected=true end
      end end
    end end
    return ok
  end
  function self:finish_pending()
    if self.pending then local value=self.pending.value; self.pending=nil; self:write(value,'Change modulation point type') end
  end
  local function editable(l) return l and not l.stale and not (not l.managed and l.complex_native) end
  local function deselect(l) for _,p in ipairs(l.points) do p.selected=false end end
  local function prepare() self:finish_pending(); self.draft=M.copy(lane()); return self.draft end
  local function selected(l) local out={}; for i,p in ipairs(l.points) do if p.selected then out[#out+1]=i end end; return out end
  function self:delete_points()
    local l=lane(); if not editable(l) then return end
    local draft=M.copy(l); for i=#draft.points,1,-1 do if draft.points[i].selected then table.remove(draft.points,i) end end
    if #draft.points~=#l.points then self:write(draft,'Delete modulation points') end
  end
  function self:poll()
    self:refresh(); local b=B.clips[B.active]; if not b then return end
    if self.pending and r.time_precise()-self.pending.time>.35 then self:finish_pending() end
    if self.armed and not self:busy() then
      local c=F:touched(b); local signature=F:signature(c)
      if c and signature~=self.armed then
        self.armed=false
        local value,message,effect=F:prepare(c,b,self.lanes,self.channel-1)
        if not value then S.status=message
        else
          local exists=false
          for i,l in ipairs(self.lanes) do if l==value then self.selected=i; exists=true end end
          if effect or not exists then self:write(value,'Map VST parameter to clip modulation',effect) end
        end
      end
    end
  end
  function self:set_open(open)
    if open==self.enabled then return end
    if not open then self:finish_pending(); self.drag=nil; self.numeric=nil; self.draft=nil; self.resize=nil end
    self.enabled=open; r.SetExtState('FluentMIDIEditor','modOpen',open and '1' or '0',true)
  end
  -- Collapsed and empty panels shrink to their header, so a clip without
  -- modulation does not take space from the piano roll.
  function self:layout_height(available)
    self:refresh()
    local _,pad=ImGui.GetStyleVar(ctx,ImGui.StyleVar_WindowPadding)
    local head=ImGui.GetFrameHeight(ctx)+2*pad+2
    self.max_height=math.max(MIN_HEIGHT,math.floor(available*.7))
    if not self.enabled then return head end
    if #self.lanes==0 then return head+ImGui.GetTextLineHeightWithSpacing(ctx)+4 end
    return M.clamp(self.height,MIN_HEIGHT,self.max_height)
  end
  function self:shortcuts()
    if not self.focus then return false end
    local function key(name) return ImGui.IsKeyPressed(ctx,ImGui['Key_'..name],false) end
    local ctrl=ImGui.IsKeyDown(ctx,ImGui.Mod_Ctrl)
    if key('Escape') and (self.armed or self.enabled and lane()) then self.drag=nil; self.pending=nil; self.numeric=nil; self.draft=nil; self.armed=false; return true end
    if not self.enabled or not lane() then return false end
    if self:busy() then return true end
    if ImGui.IsAnyItemActive(ctx) then return true end
    if key('Delete') or key('Backspace') then self:delete_points(); return true end
    if ctrl and key('A') and lane() then for _,p in ipairs(lane().points) do p.selected=true end; return true end
    return false
  end
  local function tip(text) if ImGui.IsItemHovered(ctx,ImGui.HoveredFlags_DelayNormal) then ImGui.SetTooltip(ctx,text) end end
  local function button(text,active)
    if active then ImGui.PushStyleColor(ctx,ImGui.Col_Button,0xA36B37FF) end
    local clicked=ImGui.Button(ctx,text)
    if active then ImGui.PopStyleColor(ctx) end
    return clicked
  end
  local function text_w(text) local w=ImGui.CalcTextSize(ctx,text); return w end
  local function plural(n)
    return n==1 and 'lane' or 'lanes'
  end
  local function summary(space)
    if #self.lanes==0 then return '· none in this clip' end
    local text='· '..#self.lanes..' '..plural(#self.lanes)..': '
    for i,l in ipairs(self.lanes) do
      local more=text..(i>1 and ', ' or '')..l.label
      if text_w(more..', ...')>space then return text..(i>1 and ', ...' or '...') end
      text=more
    end
    return text
  end
  -- The gap above the panel is its resize handle: drag to resize, double click to collapse.
  local function splitter(width)
    local x,y=ImGui.GetCursorScreenPos(ctx); local _,gap=ImGui.GetStyleVar(ctx,ImGui.StyleVar_ItemSpacing)
    ImGui.SetCursorScreenPos(ctx,x,y-gap)
    ImGui.InvisibleButton(ctx,'##mod_splitter',width,gap)
    local mx,my=ImGui.GetMousePos(ctx); local active=ImGui.IsItemActive(ctx)
    local hovered=ImGui.IsItemHovered(ctx) and mx>=x and mx<=x+width and my>=y-gap and my<=y
    if hovered or active then ImGui.SetMouseCursor(ctx,ImGui.MouseCursor_ResizeNS) end
    if hovered and ImGui.IsMouseDoubleClicked(ctx,0) then self.resize=nil; self:set_open(false)
    elseif ImGui.IsItemActivated(ctx) then self.resize={my=my,height=M.clamp(self.height,MIN_HEIGHT,self.max_height)}
    elseif active and self.resize then self.height=M.clamp(self.resize.height-(my-self.resize.my),MIN_HEIGHT,self.max_height)
    elseif not active and self.resize then self.resize=nil; r.SetExtState('FluentMIDIEditor','modHeight',tostring(math.floor(self.height)),true) end
    local mid,cx=y-gap/2,x+width/2
    ImGui.DrawList_AddLine(ImGui.GetWindowDrawList(ctx),cx-18,mid,cx+18,mid,(hovered or active) and C.accent or C.line,2)
    tip('Drag to resize. Double-click to collapse.')
    ImGui.SetCursorScreenPos(ctx,x,y)
  end
  function self:draw(width,height)
    self:poll(); local b=B.clips[B.active]; if not b then return end
    local expanded=self.enabled and #self.lanes>0
    if expanded then splitter(width) end
    if not ImGui.BeginChild(ctx,'Modulation lane',width,height,ImGui.ChildFlags_Borders) then ImGui.EndChild(ctx); return end
    self.focus=ImGui.IsWindowFocused(ctx,ImGui.FocusedFlags_ChildWindows)
    local x0=ImGui.GetCursorPosX(ctx); local available=ImGui.GetContentRegionAvail(ctx)
    local fx=ImGui.GetStyleVar(ctx,ImGui.StyleVar_FramePadding); local sx=ImGui.GetStyleVar(ctx,ImGui.StyleVar_ItemSpacing)
    local vst_w=math.max(text_w('+ VST parameter'),text_w('Move a knob...'))
    local actions_w=text_w('+ CC')+vst_w+4*fx+sx
    local l=lane()
    if ImGui.ArrowButton(ctx,'##mod_toggle',self.enabled and ImGui.Dir_Down or ImGui.Dir_Right) then self:set_open(not self.enabled) end
    tip(self.enabled and 'Collapse modulation' or 'Expand modulation')
    ImGui.SameLine(ctx); ImGui.AlignTextToFramePadding(ctx); ImGui.Text(ctx,'Modulation')
    if ImGui.IsItemHovered(ctx) then ImGui.SetMouseCursor(ctx,ImGui.MouseCursor_Hand) end
    if ImGui.IsItemClicked(ctx) then self:set_open(not self.enabled) end
    ImGui.SameLine(ctx)
    local space=x0+available-actions_w-sx-ImGui.GetCursorPosX(ctx)
    if expanded then
      ImGui.SetNextItemWidth(ctx,math.max(100,space))
      if ImGui.BeginCombo(ctx,'##mod_target',l and l.label or '') then
        for i,v in ipairs(self.lanes) do
          if ImGui.Selectable(ctx,v.label..' · CC '..v.cc..' / ch. '..(v.channel+1)..'##mod'..i,i==self.selected) then self:finish_pending(); self.selected=i; self.draft=nil end
        end
        ImGui.EndCombo(ctx)
      end
    elseif not self.enabled then
      ImGui.TextColored(ctx,C.muted,summary(space))
    end
    ImGui.SameLine(ctx,x0+available-actions_w)
    if button('+ CC') then self:finish_pending(); self:set_open(true); ImGui.OpenPopup(ctx,'Add CC') end
    ImGui.SameLine(ctx)
    if button(self.armed and 'Move a knob...' or '+ VST parameter',self.armed) then
      self:finish_pending(); self:set_open(true)
      if self.armed then self.armed=false else self.armed=F:signature(F:touched(b)) end
      S.status=self.armed and 'Move a VST parameter on track '..b.track_name..'. Escape cancels.' or 'Capture cancelled'
    end
    tip('Capture a parameter on the active track. Its curve is stored as CC in the clip.')
    if ImGui.BeginPopup(ctx,'Add CC') then
      ImGui.SetNextItemWidth(ctx,140); local changed; changed,self.cc=ImGui.InputInt(ctx,'CC (0-119)',self.cc)
      self.cc=M.clamp(self.cc,0,119)
      ImGui.SetNextItemWidth(ctx,140); changed,self.channel=ImGui.InputInt(ctx,'Channel (1-16)',self.channel)
      self.channel=M.clamp(self.channel,1,16)
      if button('Add / show') then
        local found; for i,v in ipairs(self.lanes) do if v.channel==self.channel-1 and v.cc==self.cc then self.selected=i; found=true end end
        if not found then self:write(A.new_lane(self.channel-1,self.cc,b.edit_source_start,b.edit_source_end,.5),'Add CC lane to clip') end
        ImGui.CloseCurrentPopup(ctx)
      end
      ImGui.EndPopup(ctx)
    end
    l=lane()
    if not self.enabled then ImGui.EndChild(ctx); return end
    if not l then
      ImGui.TextColored(ctx,C.muted,'Add a CC or capture a VST parameter. Modulation is copied and repeated with the clip.')
      ImGui.EndChild(ctx); return
    end
    if l.stale or not l.managed and l.complex_native then
      ImGui.TextColored(ctx,C.accent,l.stale and 'CC changed outside Fluent MIDI Editor.' or 'CC uses native curve shapes.')
      ImGui.SameLine(ctx)
      if button('Import current CC as points') then
        local draft=M.copy(l); draft.points=M.copy(l.native); draft.managed=true; draft.stale=nil; draft.complex_native=nil
        self:write(draft,'Import current CC into modulation')
      end
      tip('Keeps the CC values. Native curves are replaced by segments between points.')
    else
      if button('Curve',l.mode~='steps') then l.mode='curve' end
      ImGui.SameLine(ctx); if button('Steps',l.mode=='steps') then l.mode='steps' end
      ImGui.SameLine(ctx); if button('Snap',self.snap) then self.snap=not self.snap end
      tip('Shift temporarily enables snap. Same grid as the notes.')
      ImGui.SameLine(ctx); if button('Undo') then self:finish_pending(); r.Undo_DoUndo2(B.project); B:read(); self:reset(); on_write() end
      ImGui.SameLine(ctx); if button('Redo') then r.Undo_DoRedo2(B.project); B:read(); self:reset(); on_write() end
      ImGui.SameLine(ctx); ImGui.TextColored(ctx,C.muted,'CC '..l.cc..' / ch. '..(l.channel+1)..' · '..b.track_name)
      if not F:linked(l,b) then ImGui.TextColored(ctx,C.accent,'Not mapped to this VST on the track. The CC stays in the clip.') end
    end
    local x,y=ImGui.GetCursorScreenPos(ctx); local w,remain=ImGui.GetContentRegionAvail(ctx)
    local h=math.max(65,remain-31); local gx=S.timeline_x or x+44; local gw=S.timeline_w or math.max(40,w-54); local gy=y+9; local gh=h-25
    local dl=ImGui.GetWindowDrawList(ctx)
    local tx=function(q) return gx+(q-S.start)/S.span*gw end
    local tq=function(px) return S.start+(px-gx)/gw*S.span end
    local ty=function(v) return gy+(1-v)*gh end
    local value=function(py) return M.clamp(1-(py-gy)/gh,0,1) end
    ImGui.InvisibleButton(ctx,'Modulation graph',w,h,ImGui.ButtonFlags_MouseButtonLeft|ImGui.ButtonFlags_MouseButtonRight)
    local hovered=ImGui.IsItemHovered(ctx); local mx,my=ImGui.GetMousePos(ctx)
    local ctrl=ImGui.IsKeyDown(ctx,ImGui.Mod_Ctrl); local shift=ImGui.IsKeyDown(ctx,ImGui.Mod_Shift); local alt=ImGui.IsKeyDown(ctx,ImGui.Mod_Alt)
    local step=S.grid*(S.triplet and 2/3 or 1)
    local snap=function(t) return (self.snap or shift) and M.snap(t+b.offset_in_view,step)-b.offset_in_view or t end
    local q=tq(mx)-b.offset_in_view; local v=value(my)
    local in_phrase=q>=b.edit_source_start-1e-9 and q<=b.edit_source_end+1e-9
    local in_graph=hovered and mx>=gx and mx<=gx+gw and my>=gy and my<=gy+gh
    l=lane() or l
    local hit,segment
    if in_graph then
      local nearest=11
      for i,p in ipairs(l.points) do if p.t>=b.edit_source_start-1e-8 and p.t<=b.edit_source_end+1e-8 then
        local distance=((tx(p.t+b.offset_in_view)-mx)^2+(ty(p.v)-my)^2)^.5
        if distance<nearest then hit=i; nearest=distance end
      end end
      if not hit then for i=1,#l.points-1 do local a,z=l.points[i],l.points[i+1]
        if q>a.t and q<z.t and math.abs(ty(A.segment(l,i,(q-a.t)/(z.t-a.t)))-my)<8 then segment=i; break end
      end end
    end
    ImGui.DrawList_AddRectFilled(dl,x,y,x+w,y+h,C.bg)
    ImGui.DrawList_PushClipRect(dl,gx,gy-5,gx+gw+6,gy+gh+6,true)
    for _,level in ipairs({0,.25,.5,.75,1}) do ImGui.DrawList_AddLine(dl,gx,ty(level),gx+gw,ty(level),C.line) end
    local gridstep=step; while gridstep*gw/S.span<12 do gridstep=gridstep*2 end
    for t=M.floor(S.start,gridstep),S.start+S.span,gridstep do ImGui.DrawList_AddLine(dl,tx(t),gy,tx(t),gy+gh,0x78838F38) end
    local function curve(shiftq,a,z,color,ghost)
      local left=math.max(a,S.start); local right=math.min(z,S.start+S.span); if right<=left then return end
      local n=math.max(1,math.ceil((right-left)/S.span*gw/3)); local px,py
      for i=0,n do local t=left+(right-left)*i/n; local xx,yy=tx(t),ty(A.value(l,t-shiftq))
        if px and (not ghost or i%4<2) then ImGui.DrawList_AddLine(dl,px,py,xx,yy,color,ghost and 1 or 2) end; px,py=xx,yy
      end
    end
    curve(b.offset_in_view,b.view_start,b.view_end,C.accent)
    if B.show_repeats then for _,cycle in ipairs(b.repeats) do curve(cycle.s-b.edit_source_start,cycle.s,cycle.e,0xFFAD5970,true) end end
    for i,p in ipairs(l.points) do if p.t>=b.edit_source_start-1e-8 and p.t<=b.edit_source_end+1e-8 then
      local xx,yy=tx(p.t+b.offset_in_view),ty(p.v)
      if p.selected then ImGui.DrawList_AddCircle(dl,xx,yy,8,C.text,0,1) end
      if p.kind==2 then ImGui.DrawList_AddCircle(dl,xx,yy,4,C.accent,0,2)
      else ImGui.DrawList_AddCircleFilled(dl,xx,yy,p.kind==1 and 3 or 4,C.accent) end
    end end
    if self.drag and self.drag.kind=='select' then local d=self.drag
      ImGui.DrawList_AddRect(dl,math.min(d.mx,mx),math.min(d.my,my),math.max(d.mx,mx),math.max(d.my,my),C.text)
    end
    if r.GetPlayStateEx(B.project)&1~=0 then local play=r.TimeMap2_timeToQN(B.project,r.GetPlayPositionEx(B.project))-B.origin
      ImGui.DrawList_AddLine(dl,tx(play),gy,tx(play),gy+gh,C.text,1)
    end
    ImGui.DrawList_PopClipRect(dl)
    ImGui.DrawList_AddText(dl,x+3,gy-4,C.muted,'127'); ImGui.DrawList_AddText(dl,x+20,gy+gh-10,C.muted,'0')
    if in_graph and not self.drag then
      ImGui.SetMouseCursor(ctx,hit and ImGui.MouseCursor_ResizeAll or segment and ImGui.MouseCursor_ResizeNS or ImGui.MouseCursor_Arrow)
      tip(not in_phrase and 'Repeat: edit the first pass.' or 'Click: add point | Double-click point: delete | Drag line: bend\nCtrl+click: Soft | Shift: snap | Right-click point: type\nClick point: line/curve | Shift+click point: soften')
    end
    if in_graph and editable(l) and in_phrase and not self.drag then
      if ImGui.IsMouseClicked(ctx,1) and hit then
        self:finish_pending(); self.context=hit; ImGui.OpenPopup(ctx,'Point type')
      end
      if ImGui.IsMouseClicked(ctx,0) then
        if ImGui.IsMouseDoubleClicked(ctx,0) and hit then
          self.pending=nil; self.draft=nil; local draft=M.copy(self.lanes[self.selected]); table.remove(draft.points,hit)
          self:write(draft,'Delete modulation point')
        else
          local draft=prepare(); local before=M.copy(draft)
          if hit and not draft.points[hit].selected then deselect(draft); draft.points[hit].selected=true end
          self.drag={kind=draft.mode=='steps' and 'steps' or hit and 'point' or segment and 'bend' or 'select',
            mx=mx,my=my,q=q,v=v,hit=hit,segment=segment,before=before,moved=false,shift=shift,ctrl=ctrl}
          if self.drag.kind=='steps' then local a=M.floor(q+b.offset_in_view,step)-b.offset_in_view
            A.paint(draft,math.max(b.edit_source_start,a),math.min(b.edit_source_end,a+step),v); self.drag.last=a
          end
        end
      end
    end
    if self.drag then local d=self.drag; local draft=self.draft
      if ImGui.IsKeyPressed(ctx,ImGui.Key_Escape) then self.drag=nil; self.draft=nil
      else
        if (mx-d.mx)^2+(my-d.my)^2>9 then d.moved=true end
        if d.moved then
          if d.kind=='point' then
            local anchor=d.before.points[d.hit]; local delta=snap(anchor.t+q-d.q)-anchor.t; local dv=v-d.v
            if alt then if ctrl then dv=0 else delta=0 end end
            local chosen={}; for i,p in ipairs(draft.points) do if p.selected then chosen[#chosen+1]=i end end
            for _,i in ipairs(chosen) do local p=d.before.points[i]; delta=M.clamp(delta,b.edit_source_start-p.t,b.edit_source_end-p.t); dv=M.clamp(dv,-p.v,1-p.v) end
            for _,i in ipairs(chosen) do local p=d.before.points[i]
              local prev,nextp=d.before.points[i-1],d.before.points[i+1]
              if prev and not draft.points[i-1].selected then delta=math.max(delta,prev.t-p.t+1e-6) end
              if nextp and not draft.points[i+1].selected then delta=math.min(delta,nextp.t-p.t-1e-6) end
            end
            for _,i in ipairs(chosen) do local p=d.before.points[i]; draft.points[i].t=p.t+delta; draft.points[i].v=p.v+dv
              draft.points[i].c1=nil; draft.points[i].c2=nil
              if draft.points[i-1] then draft.points[i-1].c1=nil; draft.points[i-1].c2=nil end
            end
          elseif d.kind=='bend' then
            local p,z=d.before.points[d.segment],d.before.points[d.segment+1]; local t=M.clamp((d.q-p.t)/(z.t-p.t),.12,.88)
            draft.points[d.segment].bend=M.clamp((p.bend or 0)+(v-d.v)/(3*t*(1-t)),-1,1); draft.points[d.segment].kind=p.kind==3 and 0 or p.kind
            draft.points[d.segment].c1=nil; draft.points[d.segment].c2=nil
          elseif d.kind=='steps' then
            local a=M.clamp(M.floor(q+b.offset_in_view,step)-b.offset_in_view,b.edit_source_start,b.edit_source_end-step)
            for t=math.min(a,d.last),math.max(a,d.last)+step*.01,step do A.paint(draft,t,math.min(b.edit_source_end,t+step),v) end; d.last=a
          elseif d.kind=='select' then
            for _,p in ipairs(draft.points) do p.selected=p.t>=math.min(d.q,q) and p.t<=math.max(d.q,q) and p.v>=math.min(d.v,v) and p.v<=math.max(d.v,v) end
          end
        end
        if ImGui.IsMouseReleased(ctx,0) then
          self.drag=nil
          if d.kind=='select' and d.moved then self.lanes[self.selected]=draft; self.draft=nil
          elseif not d.moved and d.kind=='point' then
            local p=draft.points[d.hit]; p.kind=d.shift and math.min(2,(p.kind==3 and 0 or p.kind)+1) or (p.kind==0 and 2 or 0); p.bend=0
            p.c1=nil; p.c2=nil
            self.pending={value=draft,time=r.time_precise()}
          else
            if not d.moved and d.kind~='steps' then deselect(draft); draft.points[#draft.points+1]={t=M.clamp(snap(d.q),b.edit_source_start,b.edit_source_end),v=d.v,kind=d.ctrl and 2 or 0,bend=0,selected=true} end
            A.sort(draft.points); self:write(draft,d.kind=='steps' and 'Draw modulation steps' or 'Edit modulation curve')
          end
        end
      end
    end
    if ImGui.BeginPopup(ctx,'Point type') then
      for i,name in ipairs({'Hard - sharp','Medium - gentle','Soft - smooth','Step - constant value'}) do
        if ImGui.MenuItem(ctx,name) then local draft=M.copy(lane()); local p=draft.points[self.context]; if p then p.kind=i-1; p.bend=0; p.c1=nil; p.c2=nil; self:write(draft,'Change modulation point type') end end
      end
      if ImGui.MenuItem(ctx,'Delete point') then local draft=M.copy(lane()); table.remove(draft.points,self.context); self:write(draft,'Delete modulation point') end
      ImGui.EndPopup(ctx)
    end
    l=lane()
    if l then
      local chosen=selected(l); local p=#chosen==1 and l.points[chosen[1]]
      if p and editable(l) then
        ImGui.SetNextItemWidth(ctx,135)
        local changed,new=ImGui.SliderDouble(ctx,'##point_value',p.v,0,1,'Value %.3f')
        if changed then if not self.numeric then self.numeric=M.copy(l); self.numeric_index=chosen[1] end; self.numeric.points[self.numeric_index].v=new; self.draft=self.numeric end
        if ImGui.IsItemDeactivatedAfterEdit(ctx) and self.numeric then self:write(self.numeric,'Change modulation value') end
        ImGui.SameLine(ctx)
        if button('Delete point') then self:delete_points() end
        ImGui.SameLine(ctx)
      end
      ImGui.TextColored(ctx,C.muted,#l.points..' pts · in MIDI clip')
    end
    ImGui.EndChild(ctx)
  end
  return self
end
return U

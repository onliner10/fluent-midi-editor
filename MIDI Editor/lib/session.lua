-- Several REAPER takes on one shared project-beat timeline.
-- All affected clips are checked before writing and share a single Undo step.
local G={}
function G.new(r,M,backend,repetitions,phrase)
  local self={clips={},active=1,notes={},ghosts={},length=16,origin=0}
  local repeats=repetitions and repetitions.new(r)
  function self:selected_items()
    local items,seen={},{}
    for i=0,r.CountSelectedMediaItems(0)-1 do
      local item=r.GetSelectedMediaItem(0,i)
      if repeats then item=repeats:owner(item,r.EnumProjects(-1,'')) or item end
      local take=r.GetActiveTake(item)
      if take and r.TakeIsMIDI(take) and not seen[item] then items[#items+1]=item; seen[item]=true end
    end
    return items
  end
  function self:matches(items)
    if #items~=#self.clips then return false end
    for i,item in ipairs(items) do if self.clips[i].item~=item then return false end end
    return true
  end
  function self:set_active(index)
    self.active=M.clamp(index,1,math.max(1,#self.clips))
    local b=self.clips[self.active]
    self.take=b and b.take; self.item=b and b.item; self.track=b and b.track
    self.name=b and b.name; self.track_name=b and b.track_name
  end
  function self:valid()
    if #self.clips==0 then return false end
    for _,b in ipairs(self.clips) do if not b:valid() then return false end end
    return true
  end
  function self:attach(items)
    self.clips={}; self.notes={}; self.ghosts={}; self.project=nil; self.take=nil; self.item=nil; self.active=1
    for _,item in ipairs(items or {}) do
      local b=backend.new(r,M)
      if b:attach(item) then self.clips[#self.clips+1]=b end
    end
    return self:read()
  end
  function self:read()
    if #self.clips==0 then return self.notes end
    self.origin=math.huge; self.position=math.huge; local ending=-math.huge
    for _,b in ipairs(self.clips) do
      if not b:read() then self.take=nil; return nil end
      self.origin=math.min(self.origin,b.item_start)
      self.position=math.min(self.position,b.position)
      ending=math.max(ending,b.item_end)
    end
    self.project=self.clips[1].project; self.length=ending-self.origin; self.notes={}; self.ghosts={}
    local group_items={}; for _,b in ipairs(self.clips) do group_items[#group_items+1]=b.item end
    for i,b in ipairs(self.clips) do
      local cycles=b:cycles()
      local first=cycles[1]
      b.offset_in_view=b.origin+first.shift-self.origin
      b.view_start=first.s-self.origin; b.view_end=first.e-self.origin
      b.item_view_start=b.item_start-self.origin; b.item_view_end=b.item_end-self.origin
      b.edit_source_start=b.view_start-b.offset_in_view
      b.edit_source_end=b.view_end-b.offset_in_view
      b.native_repeats=b.looped and #cycles>1
      b.native_cycles=#cycles
      b.repeating=repeats and repeats:enabled(b.item) or false; b.repeats={}
      b.repeat_context_changed=repeats and repeats:context_changed(b.item,group_items) or false
      for _,original in ipairs(b.notes) do if original.s<b.edit_source_end-1e-8 and original.e>b.edit_source_start+1e-8 then
        local n=M.copy(original); n.s=n.s+b.offset_in_view; n.e=n.e+b.offset_in_view
        n.take_index=i; self.notes[#self.notes+1]=n
      end end
      -- REAPER's Loop source repeats already play. Display those occurrences
      -- without creating items, changing MIDI, or requiring our repeat option.
      for j=2,#cycles do
        local cycle=cycles[j]
        local start,finish=cycle.s-self.origin,cycle.e-self.origin
        b.repeats[#b.repeats+1]={s=start,e=finish,cycle=j,native=true}
        for _,original in ipairs(b.notes) do
          local a=r.MIDI_GetProjQNFromPPQPos(b.take,original.on.pos+cycle.offset)-self.origin
          local z=r.MIDI_GetProjQNFromPPQPos(b.take,original.off.pos+cycle.offset)-self.origin
          if a<finish-1e-8 and z>start+1e-8 then
            local n=M.copy(original); n.s=math.max(start,a); n.e=math.min(finish,z)
            n.selected=false; n.take_index=i; n.ghost=true; n.cycle=j
            self.ghosts[#self.ghosts+1]=n
          end
        end
      end
      if repeats then
        for j,item in ipairs(repeats:copies(self.project,b.item)) do
          local take=r.GetActiveTake(item)
          local start=r.TimeMap2_timeToQN(self.project,r.GetMediaItemInfo_Value(item,'D_POSITION'))-self.origin
          local finish=r.TimeMap2_timeToQN(self.project,r.GetMediaItemInfo_Value(item,'D_POSITION')+r.GetMediaItemInfo_Value(item,'D_LENGTH'))-self.origin
          b.repeats[#b.repeats+1]={s=start,e=finish,cycle=j+1}
          self.length=math.max(self.length,finish)
          if take and r.TakeIsMIDI(take) then
            local ok,raw=r.MIDI_GetAllEvts(take,'')
            if ok then
              local source=M.decode(raw,function(ppq) return r.MIDI_GetProjQNFromPPQPos(take,ppq)-self.origin end)
              for _,n in ipairs(source.notes) do if n.s<finish and n.e>start then
                n.s=math.max(start,n.s); n.e=math.min(finish,n.e)
                n.selected=false; n.take_index=i; n.ghost=true; n.cycle=j+1
                self.ghosts[#self.ghosts+1]=n
              end end
            end
          end
        end
      end
    end
    -- Repeats only add information when phrases of different lengths drift
    -- against each other; equal phrases show the first pass alone. b.repeats
    -- stays filled because clip info reports the extent with repetitions.
    local phrase_end,phrase_length,equal=0,nil,true
    for _,b in ipairs(self.clips) do
      local len=b.view_end-b.view_start
      if phrase_length and math.abs(len-phrase_length)>1e-6 then equal=false end
      phrase_length=phrase_length or len; phrase_end=math.max(phrase_end,b.view_end)
    end
    self.show_repeats=not equal
    self.view_length=equal and phrase_end or self.length
    if equal then self.ghosts={} end
    self:set_active(self.active)
    self.revision=r.GetProjectStateChangeCount and r.GetProjectStateChangeCount(self.project)
    return self.notes
  end
  function self:changed()
    for _,b in ipairs(self.clips) do if b:changed() then return true end end
    if repeats and self.revision~=r.GetProjectStateChangeCount(self.project) then return true end
    return false
  end
  function self:phrase_transaction(label,fn,match_loop)
    if not repeats or not self:valid() then return false,'Select the MIDI clips again.' end
    if r.GetPlayStateEx(self.project)&4~=0 then return false,'Stop recording before editing.' end
    local items={}; for _,b in ipairs(self.clips) do
      if b:changed() then self:read(); return false,'The clip changed in REAPER. Repeat the gesture.' end
      items[#items+1]=b.item
    end
    local saved_ok,saved=pcall(function() return repeats:snapshot(self.project,items) end)
    if not saved_ok then return false,tostring(saved) end
    local a,z=r.GetSet_LoopTimeRange2(self.project,false,true,0,0,false)
    local ta,tz=r.GetSet_LoopTimeRange2(self.project,false,false,0,0,false)
    r.Undo_BeginBlock2(self.project); r.PreventUIRefresh(1)
    local ok,err=xpcall(function()
      fn(items); repeats:sync(self.project,items)
      for _,b in ipairs(self.clips) do b.take=r.GetActiveTake(b.item) end
      self:read()
      if match_loop then r.GetSet_LoopTimeRange2(self.project,true,true,self.position,r.TimeMap2_QNToTime(self.project,self.origin+self.length),false) end
    end,debug.traceback)
    local restored=true
    if not ok then
      restored=repeats:restore(self.project,saved)
      r.GetSet_LoopTimeRange2(self.project,true,true,a,z,false)
      r.GetSet_LoopTimeRange2(self.project,true,false,ta,tz,false)
    end
    r.PreventUIRefresh(-1); r.Undo_EndBlock2(self.project,'Fluent MIDI Editor: '..label,-1); r.UpdateArrange()
    for _,b in ipairs(self.clips) do b.take=r.GetActiveTake(b.item) end
    self:read()
    if not ok then return false,(restored and 'Clips restored. ' or 'Use Undo. ')..tostring(err) end
    return true
  end
  function self:resize_phrase(length_module,bars,match_loop)
    if type(bars)~='number' or bars~=bars or bars<=0 or bars>4096 then return false,'Enter a length above 0 and up to 4096 bars.' end
    return self:phrase_transaction('Change phrase length and repeats',function(items)
      local b=self.clips[self.active]
      if phrase and (b.looped or b.repeating) then
        local current=length_module.phrase_bars(r,b)
        -- Applying the displayed source length can still trim a longer native
        -- looped item. Explicit length edits follow the current phrase group.
        if math.abs(current-bars)<1e-8 and (not b.looped or math.abs(length_module.bars(r,b)-bars)<1e-8) then return end
        local native=b.looped
        phrase.resize(r,b,bars,length_module)
        if native then
          repeats:set_enabled(self.project,b.item,items,true)
        end
      else
        local ok,message=length_module.resize(r,b,bars,false,true); assert(ok,message)
      end
    end,match_loop)
  end
  function self:set_repeating(enabled,match_loop)
    return self:phrase_transaction(enabled and 'Turn on phrase repeat' or 'Turn off phrase repeat',function(items)
      local b=self.clips[self.active]
      if enabled and b.looped and not b.can_extend then error('This clip already loops its MIDI source. Use Glue in REAPER first.') end
      repeats:set_enabled(self.project,b.item,items,enabled)
    end,match_loop)
  end
  function self:commit(notes,label,phrase_end,event_edits,effect)
    if not self:valid() then return false,'The project or one of the clips changed. Select the clips again.' end
    local split,originals={},{}
    for i,b in ipairs(self.clips) do
      split[i]={}; originals[i]={}
      for _,n in ipairs(b.source.notes) do if n.id then originals[i][n.id]=n end end
    end
    for _,n in ipairs(notes) do
      if n.ghost then return false,'Repeats are read-only. Edit the first pass.' end
      local index=n.take_index or self.active; local b=self.clips[index]
      if not b then return false,'Select a target clip.' end
      local c=M.copy(n); c.s=c.s-b.offset_in_view; c.e=c.e-b.offset_in_view
      -- Existing notes outside a trimmed item's view remain untouched.
      local original=c.id and originals[index][c.id]
      if c.s<-1e-7 and (not original or math.abs(c.s-original.s)>1e-7) then
        return false,'A note starts before the beginning of clip '..b.track_name..'.'
      end
      split[index][#split[index]+1]=c
    end
    local snapshots,affected,pools,endings={},{},{},{}
    for i,b in ipairs(self.clips) do
      if b:changed() then self:read(); return false,'The clip changed in REAPER. Repeat the gesture.' end
      -- These source notes were outside the editor's visible item bounds, so
      -- absence from the edited list must not be interpreted as deletion.
      for _,n in ipairs(b.source.notes) do
        if n.s>=b.edit_source_end-1e-8 or n.e<=b.edit_source_start+1e-8 then split[i][#split[i]+1]=M.copy(n) end
      end
      local ending=b:edit_ending(split[i])
      if event_edits and event_edits[i] and event_edits[i].ending then ending=math.max(ending,event_edits[i].ending) end
      for _,n in ipairs(split[i]) do
        if phrase_end and not n.id then ending=math.max(ending,phrase_end-b.offset_in_view) end
      end
      endings[i]=ending
      local source=event_edits and event_edits[i] and M.decode(event_edits[i].raw,b.from_ppq) or b.source
      local encoded=M.encode(source,split[i],b.to_ppq,math.max(b.source.end_ppq,b.to_ppq(ending)))
      if encoded~=b.source.raw or ending>b.length+1e-7 then
        if r.GetMediaItemInfo_Value(b.item,'C_LOCK')&1~=0 then return false,'Locked clip: '..b.track_name end
        if not b.can_extend and ending>b.length+1e-7 then return false,'Clip loops its source several times; lengthen the source first. '..b.track_name end
        local ok,chunk=r.GetItemStateChunk(b.item,'',false); if not ok then return false,'Could not back up the clip.' end
        local pool=chunk:match('POOLEDEVTS%s+(%b{})')
        if pool and pools[pool] then return false,'These clips share one MIDI source. Edit only one of them.' end
        if pool then pools[pool]=true end
        snapshots[i]=chunk; affected[#affected+1]=i
      end
    end
    if #affected==0 then return true end
    if r.GetPlayStateEx(self.project)&4~=0 then return false,'Stop recording before editing.' end
    if effect and effect.validate then local ok,message=effect.validate(); if not ok then return false,message end end
    local repeat_saved
    local items={}; for _,b in ipairs(self.clips) do items[#items+1]=b.item end
    if repeats then
      local ok,value=pcall(function() return repeats:snapshot(self.project,items) end)
      if not ok then return false,tostring(value) end
      repeat_saved=value
    end
    r.Undo_BeginBlock2(self.project); r.PreventUIRefresh(1)
    local ok,err=xpcall(function()
      if effect then effect.apply() end
      for _,i in ipairs(affected) do
        local done,message=self.clips[i]:commit(split[i],label,true,endings[i],event_edits and event_edits[i] and event_edits[i].raw)
        assert(done,message)
      end
      if repeats then repeats:sync(self.project,items) end
    end,debug.traceback)
    local restored=true
    if not ok then
      if effect and effect.rollback then local restored_effect=pcall(effect.rollback); if not restored_effect then restored=false end end
      if repeats then restored=repeats:restore(self.project,repeat_saved) and restored end
      for _,i in ipairs(affected) do
        if not r.SetItemStateChunk(self.clips[i].item,snapshots[i],false) then restored=false end
      end
    end
    r.PreventUIRefresh(-1); r.Undo_EndBlock2(self.project,'Fluent MIDI Editor: '..label,-1); r.UpdateArrange()
    -- SetItemStateChunk/Undo can replace take pointers; reacquire each one.
    for _,b in ipairs(self.clips) do b.take=r.GetActiveTake(b.item) end
    self:read()
    if not ok then return false,(restored and 'Clips restored. ' or 'Use Undo. ')..tostring(err) end
    return true
  end
  return self
end
return G

-- Transaction boundary: gestures stay local until release, then one REAPER undo.
local B={}
function B.new(r,M)
  local self={r=r,model=M}
  function self:valid()
    return self.take and r.EnumProjects(-1,'')==self.project
      and r.ValidatePtr2(self.project,self.take,'MediaItem_Take*')
      and r.ValidatePtr2(self.project,self.item,'MediaItem*')
      and r.GetActiveTake(self.item)==self.take
      and (not self.track or r.ValidatePtr2(self.project,self.track,'MediaTrack*'))
  end
  function self:attach(item)
    self.item,self.take,self.source,self.track=nil,nil,nil,nil
    if not item then return end
    local take=r.GetActiveTake(item)
    if not take or not r.TakeIsMIDI(take) then return end
    self.item,self.take,self.project=item,take,r.GetItemProjectContext(item)
    return self:read()
  end
  function self:read()
    if not self:valid() then self.take=nil; return end
    self.position=r.GetMediaItemInfo_Value(self.item,'D_POSITION')
    self.item_length=r.GetMediaItemInfo_Value(self.item,'D_LENGTH')
    self.looped=r.GetMediaItemInfo_Value(self.item,'B_LOOPSRC')>0
    self.offset=r.GetMediaItemTakeInfo_Value(self.take,'D_STARTOFFS')
    self.rate=r.GetMediaItemTakeInfo_Value(self.take,'D_PLAYRATE')
    local ok,raw=r.MIDI_GetAllEvts(self.take,''); if not ok then return end
    self.item_start=r.TimeMap2_timeToQN(self.project,self.position)
    self.item_end=r.TimeMap2_timeToQN(self.project,self.position+self.item_length)
    self.origin=self.item_start
    self.from_ppq=function(ppq) return r.MIDI_GetProjQNFromPPQPos(self.take,ppq)-self.origin end
    self.to_ppq=function(qn) return r.MIDI_GetPPQPosFromProjQN(self.take,qn+self.origin) end
    -- Set when the editor writes an MPE clip; see attach_expression.
    self.known_mpe=select(2,r.GetSetMediaItemTakeInfo_String(self.take,'P_EXT:FluentMIDIMPE','',false))=='1'
    self.source=M.decode(raw,self.from_ppq,self.known_mpe)
    local events=self.source.events; local last=events[#events]
    self.empty=#events==0 or #events==1 and (#last.msg==0 or last.msg:byte(1)&0xF0==0xB0 and last.msg:byte(2)==123)
    local origin
    origin,self.single,self.length=self:extent(self.source.end_ppq)
    -- Note times are relative to the origin: decode again on a repeating source.
    if origin~=self.origin then self.origin=origin; self.source=M.decode(raw,self.from_ppq,self.known_mpe) end
    self.can_extend=not self.looped or self.single
    self.notes=self.source.notes
    self.name=r.GetTakeName(self.take)
    self.track=r.GetMediaItem_Track(self.item)
    _,self.track_name=r.GetTrackName(self.track)
    _,self.hash=r.MIDI_GetHash(self.take,false,'')
    return self.notes
  end
  -- REAPER turns Loop source on for new MIDI items. An item that plays at most
  -- one pass of its source is a plain clip, also when its start was trimmed:
  -- its length is what is visible, and it grows. Only a source that repeats is
  -- a phrase of repeats, timed from the start of its source.
  -- An empty source repeats nothing: a new 1-bar clip stretched to 2 bars in
  -- the arrange view is a 2-bar clip, and the first write lengthens its source.
  -- Returns the origin of note times, whether the clip is plain, and its length.
  function self:extent(end_ppq)
    local item_start=r.TimeMap2_timeToQN(self.project,self.position)
    local item_end=r.TimeMap2_timeToQN(self.project,self.position+self.item_length)
    if not self.looped then return item_start,false,math.max(1/16,item_end-item_start) end
    local origin=r.MIDI_GetProjQNFromPPQPos(self.take,0)
    local source_end=r.MIDI_GetProjQNFromPPQPos(self.take,end_ppq)
    if item_start>=origin-1e-7 and (self.empty or item_end<=source_end+1e-7) then
      return item_start,true,math.max(1/16,item_end-item_start)
    end
    return origin,false,math.max(1/16,source_end-origin)
  end
  -- Actual item boundaries and source cycles are different quantities. Use PPQ
  -- to locate cycles even when the take has an offset, playrate or tempo change.
  function self:cycles()
    if not self.looped or self.source.end_ppq<=0 or self.single then
      return {{s=self.item_start,e=self.item_end,offset=0,shift=0}}
    end
    local period=self.source.end_ppq
    local a=r.MIDI_GetPPQPosFromProjQN(self.take,self.item_start)
    local z=r.MIDI_GetPPQPosFromProjQN(self.take,self.item_end)
    local first=math.floor(a/period+1e-8)
    local last=math.ceil(z/period-1e-8)-1
    local cycles={}
    for i=first,last do
      local start=r.MIDI_GetProjQNFromPPQPos(self.take,i*period)
      local ending=r.MIDI_GetProjQNFromPPQPos(self.take,(i+1)*period)
      cycles[#cycles+1]={s=math.max(start,self.item_start),e=math.min(ending,self.item_end),
        offset=i*period,shift=start-self.origin}
    end
    return cycles
  end
  function self:changed()
    if not self:valid() then return true end
    local _,hash=r.MIDI_GetHash(self.take,false,'')
    local origin,_,length=self:extent(self.source.end_ppq)
    return hash~=self.hash
      or math.abs(origin-self.origin)>1e-7 or math.abs(length-self.length)>1e-7
      or r.GetMediaItemInfo_Value(self.item,'D_POSITION')~=self.position
      or r.GetMediaItemInfo_Value(self.item,'D_LENGTH')~=self.item_length
      or r.GetMediaItemInfo_Value(self.item,'B_LOOPSRC')~=(self.looped and 1 or 0)
      or r.GetMediaItemTakeInfo_Value(self.take,'D_STARTOFFS')~=self.offset
      or r.GetMediaItemTakeInfo_Value(self.take,'D_PLAYRATE')~=self.rate
  end
  function self:edit_ending(notes,minimum)
    local ending=math.max(self.length,minimum or self.length)
    local original={}; for _,n in ipairs(self.source.notes) do original[n.id]=n end
    for _,n in ipairs(notes) do
      local old=original[n.id]
      -- Notes beyond a trimmed edge survive. Velocity, selection and pitch
      -- edits must not reveal that hidden tail by growing the item again.
      if not old or n.e>old.e+1e-7 then ending=math.max(ending,n.e) end
    end
    return ending
  end
  function self:commit(notes,label,group_transaction,minimum_ending,event_source)
    if not self:valid() then return false,'The clip was closed or the project changed.' end
    if r.GetPlayStateEx(self.project)&4~=0 then return false,'Stop recording before editing.' end
    if r.GetMediaItemInfo_Value(self.item,'C_LOCK')&1~=0 then return false,'The clip is locked.' end
    local got,raw=r.MIDI_GetAllEvts(self.take,'')
    if not got or raw~=self.source.raw or self:changed() then
      self:read(); return false,'The clip changed in REAPER. Notes were refreshed; repeat the gesture.'
    end
    local ending=self:edit_ending(notes,minimum_ending)
    for _,n in ipairs(notes) do
      if n.pitch<0 or n.pitch>127 or n.vel<1 or n.vel>127 or n.e<=n.s
        or self.to_ppq(n.e)-self.to_ppq(n.s)<0.99 then return false,'A note is shorter than one MIDI tick.' end
    end
    if not self.can_extend and ending>self.length+1e-7 then
      return false,'The copy extends past the source loop. Lengthen the source in the native editor or turn off Loop source.'
    end
    local end_ppq=math.max(self.source.end_ppq,self.to_ppq(ending))
    local source=event_source and M.decode(event_source,self.from_ppq,self.known_mpe) or self.source
    local encoded=M.encode(source,notes,self.to_ppq,end_ppq)
    if encoded==raw and ending<=self.length+1e-7 then self.notes=notes; return true end
    local chunk_ok,chunk=r.GetItemStateChunk(self.item,'',false)
    if not chunk_ok then return false,'Could not back up the clip state.' end
    if not group_transaction then r.Undo_BeginBlock2(self.project); r.PreventUIRefresh(1) end
    local success,err=xpcall(function()
      if ending>self.length+1e-7 and not self.looped then
        assert(r.MIDI_SetItemExtents(self.item,r.TimeMap2_timeToQN(self.project,self.position),
          self.origin+ending),'Could not extend the clip')
      end
      assert(r.MIDI_SetAllEvts(self.take,encoded),'Could not write MIDI')
      -- Notes with a starting state are MPE notes, also right after a conversion.
      local mpe=source.mpe
      for _,n in ipairs(notes) do if n.initial then mpe=true end end
      if mpe and not self.known_mpe then r.GetSetMediaItemTakeInfo_String(self.take,'P_EXT:FluentMIDIMPE','1',true) end
      -- MIDI_SetItemExtents turns Loop source off. A looped clip keeps it: the
      -- source already ends at end_ppq, so only the item grows.
      if ending>self.length+1e-7 and self.looped then
        assert(r.SetMediaItemInfo_Value(self.item,'D_LENGTH',
          r.TimeMap2_QNToTime(self.project,self.origin+ending)-self.position),'Could not extend the clip')
      end
      r.MIDI_Sort(self.take)
      r.UpdateItemInProject(self.item)
    end,debug.traceback)
    local restored=true
    if not success then restored=r.SetItemStateChunk(self.item,chunk,false) end
    if not group_transaction then
      r.PreventUIRefresh(-1); r.Undo_EndBlock2(self.project,'Fluent MIDI Editor: '..label,-1); r.UpdateArrange()
    end
    self:read()
    if not success then return false,(restored and 'Clip restored. ' or 'Restore failed; use Undo. ')..tostring(err) end
    return true
  end
  return self
end
return B

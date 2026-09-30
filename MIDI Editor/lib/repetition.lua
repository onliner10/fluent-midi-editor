-- Read-only repetitions are real REAPER items sharing the owner's MIDI pool.
-- Ownership lives in item extstate, so playback, save/reload and native Undo
-- work without this editor running. Only explicitly enabled phrases get copies.
local R={}
function R.new(r)
  local self={}
  -- Keys keep the 'LiveMIDI' prefix of earlier builds so their repeats stay recognised.
  local MEMBERS='P_EXT:LiveMIDIRepeatMembers'
  local OWNER='P_EXT:LiveMIDIRepeatOwner'
  -- Older builds pinned native loops to their pre-edit item length. Clear that
  -- metadata on writes; repetition length now comes only from current members.
  local LEGACY_SPAN='P_EXT:LiveMIDIRepeatSpanQN'
  local function get(item,key) local _,s=r.GetSetMediaItemInfo_String(item,key,'',false); return s or '' end
  local function set(item,key,value)
    r.GetSetMediaItemInfo_String(item,key,value,true)
    -- REAPER returns false when deleting a P_EXT value; verify the stored value.
    assert(get(item,key)==value,'Could not save the repeat settings')
  end
  local function guid(item) return get(item,'GUID') end
  local function member_ids(group)
    local ids={}; for _,item in ipairs(group) do ids[#ids+1]=guid(item) end
    table.sort(ids); return table.concat(ids,',')
  end
  local function canonical(value)
    local ids={}; for id in value:gmatch('%b{}') do ids[#ids+1]=id end
    table.sort(ids); return table.concat(ids,',')
  end
  local function items(project)
    local out={}; for i=0,r.CountMediaItems(project)-1 do out[#out+1]=r.GetMediaItem(project,i) end; return out
  end
  local function index(project)
    local out={}; for _,item in ipairs(items(project)) do out[guid(item)]=item end; return out
  end
  function self:enabled(item) return get(item,MEMBERS)~='' end
  -- A repeat belongs to its owner only on the owner's track. Duplicating a
  -- repeat in REAPER copies its extstate; moved elsewhere it is a plain clip.
  function self:owner(item,project,byid)
    local id=get(item,OWNER); local owner=id~='' and (byid or index(project))[id]
    if owner and r.GetMediaItem_Track(owner)==r.GetMediaItem_Track(item) then return owner end
  end
  function self:is_copy(item,project,byid) return self:owner(item,project,byid)~=nil end
  function self:context_changed(item,group)
    return self:enabled(item) and canonical(get(item,MEMBERS))~=member_ids(group)
  end
  function self:copies(project,owner)
    local out,id,track={},guid(owner),r.GetMediaItem_Track(owner)
    for _,item in ipairs(items(project)) do
      if get(item,OWNER)==id and r.GetMediaItem_Track(item)==track then out[#out+1]=item end
    end
    table.sort(out,function(a,b) return r.GetMediaItemInfo_Value(a,'D_POSITION')<r.GetMediaItemInfo_Value(b,'D_POSITION') end)
    return out
  end
  function self:snapshot(project,extra)
    local saved,seen={},{}
    saved.allids={}; for _,item in ipairs(items(project)) do saved.allids[guid(item)]=true end
    local function add(item)
      local id=guid(item); if seen[id] then return end
      local ok,chunk=r.GetItemStateChunk(item,'',false); assert(ok,'Could not back up the clip')
      saved[#saved+1]={id=id,item=item,track=r.GetMediaItem_Track(item),chunk=chunk}; seen[id]=true
    end
    local byid=index(project)
    for _,item in ipairs(items(project)) do if self:enabled(item) or self:is_copy(item,project,byid) then add(item) end end
    for _,item in ipairs(extra or {}) do add(item) end
    return saved
  end
  function self:restore(project,saved)
    local keep={}; for _,entry in ipairs(saved) do keep[entry.id]=true end
    local ok,byid=true,index(project)
    for _,item in ipairs(items(project)) do if not saved.allids[guid(item)] or self:is_copy(item,project,byid) and not keep[guid(item)] then
      if not r.DeleteTrackMediaItem(r.GetMediaItem_Track(item),item) then ok=false end
    end end
    local current=index(project)
    for _,entry in ipairs(saved) do
      local item=current[entry.id]
      if not item and r.ValidatePtr2(project,entry.track,'MediaTrack*') then item=r.AddMediaItemToTrack(entry.track) end
      if not item or not r.SetItemStateChunk(item,entry.chunk,false) then ok=false end
    end
    return ok
  end
  function self:set_enabled(project,owner,members,enabled)
    if r.GetMediaItemInfo_Value(owner,'C_LOCK')&1~=0 then error('The phrase is locked.') end
    if enabled then
      set(owner,MEMBERS,member_ids(members))
    else
      for _,item in ipairs(self:copies(project,owner)) do
        if r.GetMediaItemInfo_Value(item,'C_LOCK')&1~=0 then error('A repeat is locked in REAPER.') end
        assert(r.DeleteTrackMediaItem(r.GetMediaItem_Track(item),item),'Could not delete a repeat')
      end
      set(owner,MEMBERS,'')
      set(owner,LEGACY_SPAN,'')
    end
  end
  function self:sync(project,changed)
    local all=items(project)
    local byid=index(project)
    local members=member_ids(changed)
    local plans={}
    -- The items being edited are the group. Item GUIDs saved by a previous
    -- session can refer to moved/replaced clips elsewhere in the arrangement.
    -- Never use those invisible items as the endpoint of the current group.
    for _,owner in ipairs(changed) do
      if self:enabled(owner) then
        local position=r.GetMediaItemInfo_Value(owner,'D_POSITION')
        local ending=position+r.GetMediaItemInfo_Value(owner,'D_LENGTH')
        local startqn=r.TimeMap2_timeToQN(project,position)
        local period=r.TimeMap2_timeToQN(project,ending)-startqn
        assert(period>0,'Invalid phrase length')
        local target=ending
        for _,item in ipairs(changed) do
          target=math.max(target,r.GetMediaItemInfo_Value(item,'D_POSITION')+r.GetMediaItemInfo_Value(item,'D_LENGTH'))
        end
        -- Stop at the next independent item; never overlay the user's arrangement.
        local track=r.GetMediaItem_Track(owner)
        for _,item in ipairs(all) do if item~=owner and r.GetMediaItem_Track(item)==track and self:owner(item,project,byid)~=owner then
          local pos=r.GetMediaItemInfo_Value(item,'D_POSITION')
          if pos>=ending-1e-8 then target=math.min(target,pos) end
        end end
        local targetqn=r.TimeMap2_timeToQN(project,target)
        local count=math.max(0,math.ceil((targetqn-startqn)/period-1e-8)-1)
        assert(count<=256,'Too many repeats. Lengthen the phrase (256 repeats max).')
        local copies=self:copies(project,owner)
        for _,copy in ipairs(copies) do assert(r.GetMediaItemInfo_Value(copy,'C_LOCK')&1==0,'A repeat is locked in REAPER.') end
        local ok,chunk=r.GetItemStateChunk(owner,'',false); assert(ok,'Could not read the phrase')
        assert(chunk:find('POOLEDEVTS%s+%b{}'),'This MIDI source does not support shared repeats.')
        local legacy=get(owner,LEGACY_SPAN)~=''
        local rebind=self:context_changed(owner,changed)
        if legacy or rebind then assert(r.GetMediaItemInfo_Value(owner,'C_LOCK')&1==0,'The phrase is locked.') end
        plans[#plans+1]={owner=owner,track=track,startqn=startqn,period=period,targetqn=targetqn,count=count,copies=copies,chunk=chunk,legacy=legacy,rebind=rebind}
      end
    end
    for _,p in ipairs(plans) do
      if p.legacy then set(p.owner,LEGACY_SPAN,'') end
      if p.rebind then set(p.owner,MEMBERS,members) end
      for n=1,p.count do
        local copy=p.copies[n]
        local itemid=copy and guid(copy) or r.genGuid()
        local chunk=p.chunk:gsub('(\nIGUID )(%b{})',function(prefix) return prefix..itemid end)
        chunk=chunk:gsub('(\nGUID )(%b{})',function(prefix) return prefix..r.genGuid() end)
        chunk=chunk:gsub('(\nFXID )(%b{})',function(prefix) return prefix..r.genGuid() end)
        chunk=chunk:gsub('\nIID %d+','')
        if not copy then copy=r.AddMediaItemToTrack(p.track) end
        -- Tag new items before a fallible write so rollback can identify them.
        set(copy,OWNER,guid(p.owner))
        assert(r.SetItemStateChunk(copy,chunk,false),'Could not write a repeat')
        set(copy,MEMBERS,''); set(copy,LEGACY_SPAN,''); set(copy,OWNER,guid(p.owner))
        local a=r.TimeMap2_QNToTime(project,p.startqn+n*p.period)
        local z=r.TimeMap2_QNToTime(project,math.min(p.targetqn,p.startqn+(n+1)*p.period))
        assert(r.SetMediaItemInfo_Value(copy,'D_POSITION',a),'Could not move a repeat')
        assert(r.SetMediaItemInfo_Value(copy,'D_LENGTH',z-a),'Could not set a repeat end')
        r.SetMediaItemSelected(copy,false)
        local take=r.GetActiveTake(copy)
        if take then r.GetSetMediaItemTakeInfo_String(take,'P_NAME',r.GetTakeName(r.GetActiveTake(p.owner))..' [repeat '..(n+1)..']',true) end
        r.UpdateItemInProject(copy)
      end
      for n=#p.copies,p.count+1,-1 do assert(r.DeleteTrackMediaItem(p.track,p.copies[n]),'Could not delete a repeat') end
    end
  end
  return self
end
return R

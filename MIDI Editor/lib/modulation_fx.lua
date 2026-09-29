-- Host MIDI links, not the input-only MIDI Learn facility. Track FX only:
-- a clip's CC must reach the plug-in during ordinary project playback.
local F={}
function F.new(r,A,M)
  local self={}
  local function get(c,key)
    local ok,value=r.TrackFX_GetNamedConfigParm(c.track,c.fx,'param.'..c.param..'.'..key)
    return ok and value or nil
  end
  function self:touched(b)
    if not b or not b:valid() then return nil end
    local ok,ti,item,_,fx,param=r.GetTouchedOrFocusedFX(0)
    if not ok or ti<0 or item>=0 or fx&0x3000000~=0 then return nil end
    local track=r.GetTrack(b.project,ti)
    if track~=b.track or param<0 or param>=r.TrackFX_GetNumParams(track,fx) then return nil end
    local _,name=r.TrackFX_GetParamName(track,fx,param,'')
    local _,ident=r.TrackFX_GetParamIdent(track,fx,param,'')
    local _,fxname=r.TrackFX_GetFXName(track,fx,'')
    return {track=track,fx=fx,param=param,guid=r.TrackFX_GetFXGUID(track,fx),ident=ident,name=name,
      label=fxname..' > '..name,value=r.TrackFX_GetParamNormalized(track,fx,param)}
  end
  function self:signature(c)
    return c and c.guid..':'..c.param..':'..string.format('%.12g',c.value) or ''
  end
  function self:valid(c,b)
    return b:valid() and c.track==b.track and r.TrackFX_GetFXGUID(c.track,c.fx)==c.guid
      and select(2,r.TrackFX_GetParamName(c.track,c.fx,c.param,''))==c.name
  end
  function self:linked(lane,b)
    if not lane.fx_guid or lane.fx_guid=='' then return true end
    for fx=0,r.TrackFX_GetCount(b.track)-1 do if r.TrackFX_GetFXGUID(b.track,fx)==lane.fx_guid then
      local param=lane.param_ident~='' and r.TrackFX_GetParamFromIdent(b.track,fx,lane.param_ident) or -1
      if param<0 then for p=0,r.TrackFX_GetNumParams(b.track,fx)-1 do if select(2,r.TrackFX_GetParamName(b.track,fx,p,''))==lane.param_name then param=p; break end end end
      if param<0 then return false end
      local c={track=b.track,fx=fx,param=param}
      return tonumber(get(c,'mod.active'))==1 and tonumber(get(c,'plink.active'))==1 and tonumber(get(c,'plink.effect'))==-100
        and tonumber(get(c,'plink.midi_bus'))==0
        and tonumber(get(c,'plink.midi_msg'))==176 and tonumber(get(c,'plink.midi_msg2'))==lane.cc
        and (tonumber(get(c,'plink.midi_chan'))==lane.channel+1 or tonumber(get(c,'plink.midi_chan'))==0)
    end end
    return false
  end
  function self:prepare(c,b,lanes,channel)
    if not self:valid(c,b) then return nil,'Move an instrument parameter on the active track.' end
    for _,lane in ipairs(lanes) do if lane.fx_guid==c.guid and lane.param_ident==c.ident and lane.param_name==c.name then
      if self:linked(lane,b) then return lane,nil,nil end
      return nil,'This parameter mapping changed in REAPER. Check MIDI link in the FX window.'
    end end
    -- A second clip on the same track uses the existing Fluent MIDI Editor mapping.
    -- Only reuse a link whose ownership is recorded in another MIDI source.
    if tonumber(get(c,'plink.active'))==1 and tonumber(get(c,'lfo.active'))~=1 and tonumber(get(c,'acs.active'))~=1
      and tonumber(get(c,'plink.scale'))==1 and tonumber(get(c,'plink.offset'))==0 then
      for i=0,r.CountTrackMediaItems(c.track)-1 do local item=r.GetTrackMediaItem(c.track,i)
        for j=0,r.CountTakes(item)-1 do local take=r.GetTake(item,j)
          if r.TakeIsMIDI(take) then local ok,raw=r.MIDI_GetAllEvts(take,''); if ok then
            for _,known in ipairs(A.read(M.decode(raw))) do
              if known.managed and known.fx_guid==c.guid and known.param_ident==c.ident and known.param_name==c.name
                and known.channel==channel and self:linked(known,b) then
                local value=A.new_lane(channel,known.cc,b.edit_source_start,b.edit_source_end,c.value,c.label)
                for _,existing in ipairs(lanes) do if existing.key==known.key then value=M.copy(existing); value.label=c.label end end
                value.fx_guid,value.param_ident,value.param_name=c.guid,c.ident,c.name
                return value,nil,nil
              end
            end
          end end
        end
      end
    end
    if tonumber(get(c,'plink.active'))==1 or tonumber(get(c,'lfo.active'))==1 or tonumber(get(c,'acs.active'))==1 then
      return nil,'The parameter already has modulation or a MIDI link. Pick another or remove the existing link in FX.'
    end
    local env=r.GetFXEnvelope(c.track,c.fx,c.param,false)
    if env then return nil,'The parameter has an automation envelope. Remove it in REAPER before mapping a CC.' end
    -- Check every take on this track, not just the active clip, and existing
    -- host links. Never allocate a CC already used by another clip or mapping.
    local used={}
    for i=0,r.CountTrackMediaItems(c.track)-1 do local item=r.GetTrackMediaItem(c.track,i)
      for j=0,r.CountTakes(item)-1 do local take=r.GetTake(item,j)
        if r.TakeIsMIDI(take) then local ok,raw=r.MIDI_GetAllEvts(take,''); if ok then
          local _,all=A.read(M.decode(raw)); for _,lane in pairs(all) do if lane.channel==channel then used[lane.cc]=true end end
        end end
      end
    end
    for fx=0,r.TrackFX_GetCount(c.track)-1 do for p=0,r.TrackFX_GetNumParams(c.track,fx)-1 do
      local test={track=c.track,fx=fx,param=p}
      if tonumber(get(test,'plink.active'))==1 and tonumber(get(test,'plink.effect'))==-100 then
        local ch,msg,cc=tonumber(get(test,'plink.midi_chan')),tonumber(get(test,'plink.midi_msg')),tonumber(get(test,'plink.midi_msg2'))
        if (ch==0 or ch==channel+1) and msg==176 and cc then used[cc]=true end
      end
    end end
    local candidates={}; for cc=20,31 do candidates[#candidates+1]=cc end; for cc=102,119 do candidates[#candidates+1]=cc end
    local cc; for _,candidate in ipairs(candidates) do if not used[candidate] then cc=candidate; break end end
    if not cc then return nil,'No free CC on this channel. Pick another MIDI channel.' end
    local lane=A.new_lane(channel,cc,b.edit_source_start,b.edit_source_end,c.value,c.label)
    lane.fx_guid, lane.param_ident,lane.param_name=c.guid,c.ident,c.name
    local changes={{'mod.active','1'},{'mod.baseline','0'},{'plink.effect','-100'},{'plink.param','-1'},
      {'plink.midi_bus','0'},{'plink.midi_chan',tostring(channel+1)},{'plink.midi_msg','176'},
      {'plink.midi_msg2',tostring(cc)},{'plink.scale','1'},{'plink.offset','0'},{'plink.active','1'}}
    local old={}; for _,entry in ipairs(changes) do old[entry[1]]=get(c,entry[1]) or '0' end
    local prefix='param.'..c.param..'.'
    local effect={}
    function effect.validate()
      if not self:valid(c,b) then return false,'The plugin or clip changed during mapping.' end
      for _,entry in ipairs(changes) do if (get(c,entry[1]) or '0')~=old[entry[1]] then return false,'Modulation settings changed in FX. Map it again.' end end
      return true
    end
    function effect.apply()
      for _,entry in ipairs(changes) do assert(r.TrackFX_SetNamedConfigParm(c.track,c.fx,prefix..entry[1],entry[2]),'Could not set MIDI link: '..entry[1]) end
      assert(self:linked(lane,b),'REAPER did not keep the MIDI link')
    end
    function effect.rollback()
      for i=#changes,1,-1 do local key=changes[i][1]; assert(r.TrackFX_SetNamedConfigParm(c.track,c.fx,prefix..key,old[key]),'Could not revert MIDI link') end
    end
    return lane,nil,effect
  end
  return self
end
return F

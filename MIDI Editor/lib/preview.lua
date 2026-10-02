-- SWS track-local audition. Never arms tracks or broadcasts to all MIDI inputs.
local P={}
-- While Preview is on, the instrument track skips media buffering and
-- anticipative FX (REAPER's per-track performance options), so a note sounds
-- within an audio block instead of after the render-ahead. The original flags
-- are kept in the track's extstate until restored, so a crash cannot lose them.
local PERF_LIVE=3
local PERF_KEY='P_EXT:FluentMIDIEditor_perf'
local VOICES=16
function P.new(r)
  local self={available=r.CF_CreatePreview~=nil}
  local voices={}
  local function restore(track)
    local ok,saved=r.GetSetMediaTrackInfo_String(track,PERF_KEY,'',false)
    if ok and tonumber(saved) then
      r.SetMediaTrackInfo_Value(track,'I_PERFFLAGS',tonumber(saved))
      r.GetSetMediaTrackInfo_String(track,PERF_KEY,'',true)
    end
  end
  -- Flags left behind by an editor that did not close cleanly.
  for i=0,r.CountTracks(0)-1 do restore(r.GetTrack(0,i)) end
  local live
  -- Makes track (in project) live for previews; nil restores the last one.
  function self:live(project,track)
    if live and (live.track~=track or live.project~=project) then
      if r.ValidatePtr2(live.project,live.track,'MediaTrack*') then restore(live.track) end
      live=nil
    end
    if not track or live or not self.available or not r.ValidatePtr2(project,track,'MediaTrack*') then return end
    local flags=math.floor(r.GetMediaTrackInfo_Value(track,'I_PERFFLAGS'))
    local ok,saved=r.GetSetMediaTrackInfo_String(track,PERF_KEY,'',false)
    if not (ok and tonumber(saved)) then r.GetSetMediaTrackInfo_String(track,PERF_KEY,tostring(flags),true) end
    if flags&PERF_LIVE~=PERF_LIVE then r.SetMediaTrackInfo_Value(track,'I_PERFFLAGS',flags|PERF_LIVE) end
    live={project=project,track=track}
  end
  local function silence(v)
    if v.handle then pcall(r.CF_Preview_Stop,v.handle) end
    if v.source then r.PCM_Source_Destroy(v.source) end
    if v.path then os.remove(v.path) end
  end
  function self:stop()
    for i=#voices,1,-1 do silence(voices[i]); voices[i]=nil end
    self.hold=nil
  end
  -- True while pitch is sounding; the piano roll lights that key.
  function self:sounding(pitch)
    for _,v in ipairs(voices) do if v.pitches[pitch] then return true end end
    return false
  end
  local function vlq(n)
    local bytes={n&0x7F}; n=n>>7
    while n>0 do table.insert(bytes,1,(n&0x7F)|0x80); n=n>>7 end
    return string.char(table.unpack(bytes))
  end
  -- Plays one note or a chord: notes is a list of {pitch,vel,channel,sec}, each
  -- sounding for its own length. hold keeps them going until :stop(). layer
  -- lets notes already sounding ring on (selecting more notes adds to them).
  function self:play(project,track,notes,hold,layer)
    if not layer then self:stop() end
    if not self.available or not r.ValidatePtr2(project,track,'MediaTrack*') then return end
    self:live(project,track)
    -- A type-0 SMF at 120 bpm, so a second is 1920 ticks whatever the project tempo.
    local events,seen,pitches,last={},{},{},0
    for _,n in ipairs(notes) do
      local key=n.pitch..':'..n.channel
      if #events<64 and not seen[key] then
        seen[key]=true; pitches[n.pitch]=true
        local ticks=math.max(60,math.floor(math.min(n.sec,30)*1920))
        events[#events+1]={0,0x90|n.channel,n.pitch,n.vel}
        events[#events+1]={ticks,0x80|n.channel,n.pitch,0}
        last=math.max(last,ticks)
      end
    end
    if #events==0 then return end
    table.sort(events,function(a,b) if a[1]~=b[1] then return a[1]<b[1] end return a[2]<b[2] end)
    local body,now={string.char(0,0xFF,0x51,3,7,0xA1,0x20)},0
    for _,e in ipairs(events) do body[#body+1]=vlq(e[1]-now)..string.char(e[2],e[3],e[4]); now=e[1] end
    local data=table.concat(body)..string.char(0,0xFF,0x2F,0)
    local path=(os.getenv('TEMP') or r.GetResourcePath())..'/fluent-midi-editor-'..r.genGuid()..'.mid'
    local f=io.open(path,'wb'); if not f then return end
    f:write('MThd'..string.pack('>I4I2I2I2',6,0,1,960)..'MTrk'..string.pack('>I4',#data)..data); f:close()
    local v={path=path,pitches=pitches}
    v.source=r.PCM_Source_CreateFromFile(path)
    if v.source then v.handle=r.CF_CreatePreview(v.source) end
    if not v.handle or not r.CF_Preview_SetOutputTrack(v.handle,project,track) or not r.CF_Preview_Play(v.handle) then silence(v); return end
    v.deadline=r.time_precise()+last/1920+0.05
    if #voices>=VOICES then silence(table.remove(voices,1)) end
    voices[#voices+1]=v
    if hold then self.hold=true end
  end
  function self:tick()
    local now=r.time_precise()
    for i=#voices,1,-1 do if now>voices[i].deadline then silence(table.remove(voices,i)) end end
    if #voices==0 then self.hold=nil end
  end
  -- Stops every voice and gives the track its own performance flags back.
  function self:close() self:stop(); self:live(nil,nil) end
  return self
end
return P

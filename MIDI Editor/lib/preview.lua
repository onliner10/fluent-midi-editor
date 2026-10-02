-- SWS track-local audition. Never arms tracks or broadcasts to all MIDI inputs.
local P={}
function P.new(r)
  local self={available=r.CF_CreatePreview~=nil}
  function self:stop()
    self.deadline=nil; self.pitches=nil; self.hold=nil
    if self.handle then pcall(r.CF_Preview_Stop,self.handle); self.handle=nil end
    if self.source then r.PCM_Source_Destroy(self.source); self.source=nil end
    if self.path then os.remove(self.path); self.path=nil end
  end
  -- True while pitch is sounding; the piano roll lights that key.
  function self:sounding(pitch) return self.deadline~=nil and self.pitches~=nil and self.pitches[pitch]==true end
  local function vlq(n)
    local bytes={n&0x7F}; n=n>>7
    while n>0 do table.insert(bytes,1,(n&0x7F)|0x80); n=n>>7 end
    return string.char(table.unpack(bytes))
  end
  -- Plays one note or a chord: notes is a list of {pitch,vel,channel,sec}, each
  -- sounding for its own length. hold keeps them going until :stop().
  function self:play(project,track,notes,hold)
    self:stop()
    if not self.available or not r.ValidatePtr2(project,track,'MediaTrack*') then return end
    local path=(os.getenv('TEMP') or r.GetResourcePath())..'/fluent-midi-editor-'..r.genGuid()..'.mid'
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
    local f=io.open(path,'wb'); if not f then return end
    f:write('MThd'..string.pack('>I4I2I2I2',6,0,1,960)..'MTrk'..string.pack('>I4',#data)..data); f:close()
    self.path=path
    self.source=r.PCM_Source_CreateFromFile(path)
    if not self.source then self:stop(); return end
    self.handle=r.CF_CreatePreview(self.source)
    if not self.handle then self:stop(); return end
    if not r.CF_Preview_SetOutputTrack(self.handle,project,track) or not r.CF_Preview_Play(self.handle) then self:stop(); return end
    self.pitches=pitches; self.hold=hold; self.deadline=r.time_precise()+last/1920+0.05
  end
  function self:tick() if self.deadline and r.time_precise()>self.deadline then self:stop() end end
  return self
end
return P

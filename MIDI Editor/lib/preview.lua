-- SWS track-local audition. Never arms tracks or broadcasts to all MIDI inputs.
local P={}
function P.new(r)
  local self={available=r.CF_CreatePreview~=nil}
  function self:stop()
    if self.handle then pcall(r.CF_Preview_Stop,self.handle); self.handle=nil end
    if self.source then r.PCM_Source_Destroy(self.source); self.source=nil end
    if self.path then os.remove(self.path); self.path=nil end
  end
  function self:play(project,track,pitch,velocity,channel)
    self:stop()
    if not self.available or not r.ValidatePtr2(project,track,'MediaTrack*') then return end
    local path=(os.getenv('TEMP') or r.GetResourcePath())..'/fluent-midi-editor-'..r.genGuid()..'.mid'
    local f=io.open(path,'wb'); if not f then return end
    -- A type-0 SMF with a 125 ms note and a real note-off, independent of tempo.
    local events=string.char(0,0xFF,0x51,3,7,0xA1,0x20,0,0x90|channel,pitch,velocity,
      0x81,0x70,0x80|channel,pitch,0,0,0xFF,0x2F,0)
    f:write('MThd'..string.pack('>I4I2I2I2',6,0,1,960)..'MTrk'..string.pack('>I4',#events)..events); f:close()
    self.path=path
    self.source=r.PCM_Source_CreateFromFile(path)
    if not self.source then self:stop(); return end
    self.handle=r.CF_CreatePreview(self.source)
    if not self.handle then self:stop(); return end
    if not r.CF_Preview_SetOutputTrack(self.handle,project,track) or not r.CF_Preview_Play(self.handle) then self:stop(); return end
    self.deadline=r.time_precise()+0.35
  end
  function self:tick() if self.deadline and r.time_precise()>self.deadline then self:stop(); self.deadline=nil end end
  return self
end
return P

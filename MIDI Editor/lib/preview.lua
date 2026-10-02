-- SWS track-local audition. Never arms tracks or broadcasts to all MIDI inputs.
local P={}
function P.new(r)
  local self={available=r.CF_CreatePreview~=nil}
  function self:stop()
    self.deadline=nil; self.pitches=nil
    if self.handle then pcall(r.CF_Preview_Stop,self.handle); self.handle=nil end
    if self.source then r.PCM_Source_Destroy(self.source); self.source=nil end
    if self.path then os.remove(self.path); self.path=nil end
  end
  -- True while pitch is sounding; the piano roll lights that key.
  function self:sounding(pitch) return self.deadline~=nil and self.pitches~=nil and self.pitches[pitch]==true end
  -- Plays one note or a chord: notes is a list of {pitch,vel,channel}.
  function self:play(project,track,notes)
    self:stop()
    if not self.available or not r.ValidatePtr2(project,track,'MediaTrack*') then return end
    local path=(os.getenv('TEMP') or r.GetResourcePath())..'/fluent-midi-editor-'..r.genGuid()..'.mid'
    local f=io.open(path,'wb'); if not f then return end
    -- A type-0 SMF with a 125 ms note and a real note-off, independent of tempo.
    local on,off,seen,pitches={},{},{},{}
    for _,n in ipairs(notes) do
      if #on>=8*4 then break end
      local key=n.pitch..':'..n.channel
      if not seen[key] then
        seen[key]=true; pitches[n.pitch]=true
        on[#on+1]=string.char(0,0x90|n.channel,n.pitch,n.vel)
        off[#off+1]=string.char(#off==0 and 0x81 or 0,#off==0 and 0x70 or 0,0x80|n.channel,n.pitch,0)
      end
    end
    if #on==0 then return end
    local events=string.char(0,0xFF,0x51,3,7,0xA1,0x20)..table.concat(on)..table.concat(off)..string.char(0,0xFF,0x2F,0)
    f:write('MThd'..string.pack('>I4I2I2I2',6,0,1,960)..'MTrk'..string.pack('>I4',#events)..events); f:close()
    self.path=path
    self.source=r.PCM_Source_CreateFromFile(path)
    if not self.source then self:stop(); return end
    self.handle=r.CF_CreatePreview(self.source)
    if not self.handle then self:stop(); return end
    if not r.CF_Preview_SetOutputTrack(self.handle,project,track) or not r.CF_Preview_Play(self.handle) then self:stop(); return end
    self.pitches=pitches; self.deadline=r.time_precise()+0.35
  end
  function self:tick() if self.deadline and r.time_precise()>self.deadline then self:stop(); self.deadline=nil; self.pitches=nil end end
  return self
end
return P

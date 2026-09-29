-- Retain note geometry between frames. Selection and velocity are read live;
-- callers invalidate geometry after in-place note insertion/removal/movement.
local R={}
function R.new(layout)
  local self={builds=0,views=0}
  function self:invalidate() self.notes=nil end
  function self:update(notes,ghosts,clips,source,active)
    if self.notes~=notes or self.ghosts~=ghosts or self.source~=source or self.clips~=clips then
      self.notes,self.ghosts,self.clips,self.source=notes,ghosts,clips,source
      self.entries={}; self.copies={}
      local function edges(n)
        if n.ghost then return n.s,n.e end
        local b=clips[n.take_index]
        return math.max(n.s,b.view_start),math.min(n.e,b.view_end)
      end
      self.layout=layout.build(notes,ghosts,edges)
      for i,n in ipairs(notes) do local a,z=edges(n)
        if z>a then self.entries[#self.entries+1]={n=n,i=i,a=a,z=z} end
      end
      for _,n in ipairs(ghosts) do
        if n.e>n.s then self.copies[#self.copies+1]={n=n,a=n.s,z=n.e} end
      end
      self.active=nil; self.viewport=nil; self.overview=nil
      self.builds=self.builds+1
    end
    if self.active~=active then
      self.active=active; self.order={}
      for pass=1,2 do for _,entry in ipairs(self.entries) do
        if (entry.n.take_index==active)==(pass==2) then self.order[#self.order+1]=entry end
      end end
      self.viewport=nil
    end
    return self.layout
  end
  function self:view(start,span,low,high)
    local v=self.viewport
    if v and v.start==start and v.span==span and v.low==low and v.high==high then return v end
    v={start=start,span=span,low=low,high=high,notes={},ghosts={},velocity={},ghost_velocity={}}
    local ending=start+span
    for pass,list in ipairs({self.order,self.copies}) do
      local visible=pass==1 and v.notes or v.ghosts
      local velocity=pass==1 and v.velocity or v.ghost_velocity
      for _,entry in ipairs(list) do local n=entry.n
        -- A long note starting offscreen is still visible, but its velocity
        -- handle belongs to its original onset and must not move to the edge.
        if entry.z>start and entry.a<ending and n.pitch>=low and n.pitch<=high then visible[#visible+1]=entry end
        if n.s>=start and n.s<=ending then velocity[#velocity+1]=entry end
      end
    end
    self.viewport=v; self.views=self.views+1
    return v
  end
  function self:miniature(total,width)
    if self.overview and self.total==total and self.width==width then return self.overview end
    self.total,self.width=total,width
    local buckets={}
    for pass,list in ipairs({self.entries,self.copies}) do for _,entry in ipairs(list) do
      local n=entry.n; local row=math.floor((127-n.pitch)/127*12)
      local key=pass..':'..(n.take_index or 1)..':'..row
      local bucket=buckets[key]
      if not bucket then bucket={}; buckets[key]=bucket end
      local a=math.max(0,math.floor(entry.a/total*width))
      local z=math.min(width,math.max(a+1,math.ceil(entry.z/total*width)))
      if z>a then bucket[#bucket+1]={a=a,z=z,row=row,track=n.take_index,ghost=pass==2} end
    end end
    local result={}
    for _,bucket in pairs(buckets) do
      table.sort(bucket,function(a,b) return a.a<b.a end)
      local current
      for _,bar in ipairs(bucket) do
        if current and bar.a<=current.z+1 then current.z=math.max(current.z,bar.z)
        else result[#result+1]=bar; current=bar end
      end
    end
    -- Repeated marks sit behind the editable phrase in the overview as well.
    table.sort(result,function(a,b)
      if a.ghost~=b.ghost then return a.ghost end
      if a.track~=b.track then return a.track<b.track end
      if a.row~=b.row then return a.row<b.row end
      return a.a<b.a
    end)
    self.overview=result
    return result
  end
  return self
end
return R

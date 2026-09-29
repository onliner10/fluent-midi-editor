-- Divide only overlapping notes from different clips into visible, clickable
-- bands within the same pitch row. Never alter their MIDI pitch or timing.
local N={}
function N.build(notes,ghosts,edges)
  local entries,result={},{}
  for _,list in ipairs({notes,ghosts or {}}) do for _,n in ipairs(list) do
    local a,z=n.s,n.e; if edges then a,z=edges(n) end
    if z>a then entries[#entries+1]={note=n,a=a,z=z} end
  end end
  table.sort(entries,function(a,b)
    if a.note.pitch~=b.note.pitch then return a.note.pitch<b.note.pitch end
    if a.a~=b.a then return a.a<b.a end
    return a.z<b.z
  end)
  local first=1
  while first<=#entries do
    local last,ending=first,entries[first].z
    while last<#entries and entries[last+1].note.pitch==entries[first].note.pitch and entries[last+1].a<ending-1e-8 do
      last=last+1; ending=math.max(ending,entries[last].z)
    end
    local tracks,seen={},{}
    for i=first,last do local track=entries[i].note.take_index or 1
      if not seen[track] then tracks[#tracks+1]=track; seen[track]=true end
    end
    table.sort(tracks)
    local lanes={}; for i,track in ipairs(tracks) do lanes[track]=i end
    for i=first,last do
      local n=entries[i].note; local lane=lanes[n.take_index or 1]
      result[n]={top=(lane-1)/#tracks,bottom=lane/#tracks,count=#tracks}
    end
    first=last+1
  end
  return result
end
function N.bounds(layout,n,row_y,row_height)
  local band=layout[n]
  if not band or not row_y then return nil end
  return row_y+band.top*row_height,row_y+band.bottom*row_height
end
return N

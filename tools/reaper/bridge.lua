-- Runs inside a headless REAPER, loaded from Scripts/__startup.lua by reaper.sh.
-- Executes <dir>/inbox/<n>.lua in order and writes <dir>/outbox/<n>.out and
-- <n>.status ('ok' or 'fail'). A chunk may return a function: it is then called
-- once per defer cycle until it returns a truthy value, so a job can wait for
-- deferred scripts (the editor) to run a few frames.
return function(dir,root)
  local r=reaper
  -- Globals, so files a job loads with dofile() see them too.
  ROOT,BRIDGE=root,dir
  local function write(path,text)
    local f=assert(io.open(path..'.tmp','w')); f:write(text); f:close()
    assert(os.rename(path..'.tmp',path))
  end
  local next_id,job=1,nil
  local function finish(ok,err)
    local out=table.concat(job.lines,'\n')
    if not ok then out=out..(out~='' and '\n' or '')..tostring(err) end
    write(dir..'/outbox/'..job.id..'.out',out)
    write(dir..'/outbox/'..job.id..'.status',ok and 'ok' or 'fail')
    job=nil
  end
  local function start(id,path)
    job={id=id,lines={}}
    local env=setmetatable({},{__index=_G})
    env.print=function(...)
      local parts={}
      for i=1,select('#',...) do parts[i]=tostring((select(i,...))) end
      job.lines[#job.lines+1]=table.concat(parts,'\t')
    end
    local chunk,err=loadfile(path,'t',env)
    if not chunk then return finish(false,err) end
    local ok,result=xpcall(chunk,debug.traceback)
    if not ok then return finish(false,result) end
    if type(result)=='function' then job.step=result; job.deadline=r.time_precise()+60
    else finish(true) end
  end
  local function tick()
    if job and job.step then
      local ok,done=xpcall(job.step,debug.traceback)
      if not ok then finish(false,done)
      elseif done then finish(true)
      elseif r.time_precise()>job.deadline then finish(false,'timed out waiting for the job') end
    end
    if not job then
      local path=dir..'/inbox/'..next_id..'.lua'
      local f=io.open(path)
      if f then f:close(); next_id=next_id+1; start(next_id-1,path) end
    end
    r.defer(tick)
  end
  write(dir..'/ready',tostring(r.GetAppVersion()))
  r.defer(tick)
end

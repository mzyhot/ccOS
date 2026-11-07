-- Scripted OpenRouter transport, used by the OS harness without any real key.
-- Validates the actual wire JSON and multi-round tool-result protocol.
return function(ctx)
  local count,closed=0,0
  local function tool(id,name,args,J)return{id=id,type="function",["function"]={name=name,arguments=J.encode(args)}}end
  local http={}
  function http.request(options)
    count=count+1
    local J=ccos.json
    local payload=J.decode(options.body)
    assert(options.url=="https://openrouter.ai/api/v1/chat/completions","Unexpected endpoint")
    assert(options.headers.Authorization=="Bearer sk-or-test-key","Missing authorization")
    assert(not options.body:find("sk-or-test-key",1,true),"Secret leaked into messages")
    assert(payload.stream==false and #payload.tools>=25,"Missing OS tool definitions")
    assert(payload.provider.require_parameters==true,"Tool-compatible routing required")
    local calls
    if ctx.scenario=="agent-timeout"then return true
    elseif ctx.scenario=="agent-cancel-http"then
      ctx.after(20,function()ctx.push("http_success",options.url,{close=function()closed=closed+1 end})end);return true
    elseif ctx.scenario=="agent-deny"then
      if count==1 then calls={tool("denied","write_file",{path="/notes/denied.txt",content="Should not be written"},J)}
      else local last=payload.messages[#payload.messages];assert(last.role=="tool"and J.decode(last.content).ok==false,"Denied call must produce a tool error")end
    elseif ctx.scenario=="agent-error"then
      ctx.after(2,function()ctx.push("http_failure",options.url,"HTTP 401 Unauthorized",{close=function()closed=closed+1 end})end);return true
    elseif ctx.scenario=="agent-malformed"then
      if count==1 then calls={{id="bad",type="function",["function"]={name="write_file",arguments="not JSON"}}}
      else
        local last=payload.messages[#payload.messages];assert(last.role=="tool"and J.decode(last.content).ok==false,"Malformed call was not returned as an error")
      end
    elseif count==1 then
      calls={tool("list","list_files",{path="/notes"},J),tool("read","read_file",{path="/notes/todo.txt"},J),tool("system","get_system",{},J),tool("time","get_time",{},J)}
    elseif count==2 then
      calls={tool("write","write_file",{path="/notes/agent.txt",content="hello\n"},J),tool("edit","edit_file",{path="/notes/agent.txt",old_text="hello",new_text="hello ccOS"},J),tool("append","append_file",{path="/notes/agent.txt",content="done\n"},J),tool("mkdir","make_directory",{path="/programs/agent"},J),tool("program","write_file",{path="/programs/agent/probe.lua",content="print('Agent ran')\n"},J)}
    elseif count==3 then
      calls={tool("run","run_program",{path="/programs/agent/probe.lua"},J),tool("zone","set_setting",{name="timezone",value="fixed"},J),tool("offset","set_setting",{name="utcOffset",value="330"},J),tool("format","set_setting",{name="clock24",value="false"},J),tool("padding","set_setting",{name="leadingZero",value="false"},J),tool("volume","control_audio",{action="volume",value=0.4},J),tool("app","open_app",{id="calc"},J),tool("paper","call_peripheral",{name="printer_0",method="getPaperLevel",arguments_json="[]"},J),tool("signal","redstone",{side="left",level=7},J)}
    elseif count==4 then
      local pid
      for _,msg in ipairs(payload.messages)do if msg.role=="tool"and msg.tool_call_id=="run"then pid=J.decode(msg.content).result.process end end
      assert(pid,"Program did not return a process id")
      calls={tool("output","read_window",{id=pid},J),tool("verify","read_file",{path="/notes/agent.txt"},J),tool("windows","list_windows",{},J),tool("private","read_file",{path="/ccos/private/openrouter.cfg"},J)}
    elseif count==5 then
      local output,private
      for _,msg in ipairs(payload.messages)do
        if msg.role=="tool"and msg.tool_call_id=="output"then output=J.decode(msg.content)end
        if msg.role=="tool"and msg.tool_call_id=="private"then private=J.decode(msg.content)end
      end
      assert(output and output.ok and output.result.text:find("Agent ran",1,true),"Agent could not observe program output")
      assert(private and private.ok==false,"Private key was readable through a file tool")
    else error("Too many inference rounds")end
    local message={role="assistant",content=calls and ""or "Finished: created and edited files, ran the program, updated settings and volume."}
    if calls then message.tool_calls=J.array(calls)end
    local raw=J.encode({choices=J.array({{message=message}})})
    ctx.after(2,function()
      local handle={read=function(n)return raw:sub(1,n or #raw)end,readAll=function()return raw end,getResponseCode=function()return 200 end,close=function()closed=closed+1 end}
      ctx.push("http_success",options.url,handle)
    end)
    return true
  end
  http.stats=function()return count,closed end
  return http
end

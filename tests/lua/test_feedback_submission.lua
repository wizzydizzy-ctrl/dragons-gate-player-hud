local Adapter=require("mudlet_adapter")

test("anonymous feedback transport validates and posts without opening a browser",function()
  local saved={postHTTP=postHTTP,registerAnonymousEventHandler=registerAnonymousEventHandler,killAnonymousEventHandler=killAnonymousEventHandler,tempTimer=tempTimer,killTimer=killTimer,yajl=yajl,DGHUD=rawget(_G,"DGHUD"),openUrl=openUrl}
  local handlers,posted={},nil
  yajl={to_string=function(value) return "encoded:"..tostring(value.component) end,to_value=function() return {ok=true,report_id="DG-TEST"} end}
  registerAnonymousEventHandler=function(name,fn) handlers[name]=fn; return name end; killAnonymousEventHandler=function() return true end; tempTimer=function(_,fn) handlers.timeout=fn; return 44 end; killTimer=function() return true end
  postHTTP=function(payload,url,headers) posted={payload=payload,url=url,headers=headers}; return true end
  openUrl=function() error("browser must not open") end; DGHUD={settings={edition="player",version="1.2.3"}}
  local result; local adapter=Adapter.new(); assert(adapter:submitFeedback({kind="request",summary="Better clock",details="Please add sunrise and sunset information."},function(value,err) result={value=value,err=err} end))
  eq(posted.url,"https://dghud-maps.wallfamilyarchive.com/v1/diagnostics"); eq(posted.payload,"encoded:feature_request"); handlers.sysPostHttpDone(nil,posted.url,"{}"); eq(result.value.report_id,"DG-TEST"); eq(result.err,nil)
  postHTTP=saved.postHTTP; registerAnonymousEventHandler=saved.registerAnonymousEventHandler; killAnonymousEventHandler=saved.killAnonymousEventHandler; tempTimer=saved.tempTimer; killTimer=saved.killTimer; yajl=saved.yajl; rawset(_G,"DGHUD",saved.DGHUD); openUrl=saved.openUrl
end)

test("anonymous feedback rejects incomplete forms before network access",function()
  local adapter=Adapter.new(); local ok,err=adapter:submitFeedback({kind="feedback",summary="No",details="too short"},function() end); eq(ok,nil); eq(err,"summary must be 3-200 characters")
end)

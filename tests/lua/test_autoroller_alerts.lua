local Alerts=require("autoroller_alerts")
local Audio=require("autoroller_audio")
local function fixture(settings)
  local f={now=100,timers={},next=0,played={},stops={},shown={},hidden=0,messages={}}
  local adapter={chatSoundTime=function() return f.now end,
    schedule=function(_,delay,fn) f.next=f.next+1; f.timers[f.next]={delay=delay,fn=fn}; return f.next end,
    cancelTimer=function(_,id) if f.cancelFails then error("cancel failed") end; f.timers[id]=nil; return true end,
    reportRoller=function(_,text) f.messages[#f.messages+1]=text end}
  local audio={play=function(_,config,preview)
    if f.playThrows then error("backend error") end
    f.played[#f.played+1]={config=config,preview=preview}; if f.playFails then return nil,"Playback unavailable." end
    return true,f.warning,f.duration or 1
  end,stop=function(_,preview) f.stops[#f.stops+1]=preview; return true end,
  chooseCustom=function() return f.choice,f.choiceError end}
  local view={showRollerResultAlert=function(_,event) f.shown[#f.shown+1]=event end,
    hideRollerResultAlert=function() f.hidden=f.hidden+1 end}
  f.config=settings or Audio.defaults(); f.alerts=Alerts.new(adapter,audio,view,function() return f.config end)
  function f:fire(id,advance) local timer=assert(self.timers[id]); self.timers[id]=nil; self.now=self.now+(advance or timer.delay); timer.fn() end
  return f
end
local function target() return {kind="target_hit",reason="target 60",rolls=7,protocol="creator",roll={total=61,maximum=77},placement="manual"} end
test("autoroller completion notice and default audio are independent of command sending",function()
  local f=fixture(); assert(f.alerts:result(target())); eq(#f.shown,1); eq(#f.played,1)
  eq(f.played[1].config.sound,"three_tone"); eq(f.played[1].config.volume,75); eq(next(f.timers),nil)
end)
test("autoroller completion duplicate prompts do not repeat sound or notice",function()
  local f=fixture(); assert(f.alerts:result(target())); eq(f.alerts:result(target()),false)
  eq(#f.played,1); eq(#f.shown,1)
  f.alerts:clear(); assert(f.alerts:result(target())); eq(#f.played,2)
end)
test("autoroller failure and non completion events cannot become target alerts",function()
  local f=fixture()
  for _,kind in ipairs({"error","disconnected","max_rolls","held","manual_stop"}) do eq(f.alerts:result({kind=kind}),false) end
  eq(f.alerts:result(nil),false); eq(#f.played,0); eq(#f.shown,0)
end)
test("autoroller sound off retains a visible result and allows preview",function()
  local f=fixture({enabled=false}); assert(f.alerts:result(target())); eq(#f.played,0); eq(#f.shown,1)
  assert(f.alerts:action("preview",{enabled=false,volume=20,sound="horn"})); eq(#f.played,1)
  eq(f.played[1].preview,true); eq(f.played[1].config.volume,20); eq(f.config.enabled,false)
end)
test("autoroller reminders repeat every ten seconds and have a five minute expiry",function()
  local f=fixture({repeat_enabled=true}); assert(f.alerts:result(target())); eq(f.timers[f.alerts.expiry.id].delay,300)
  local timer=f.alerts.timer.id; eq(f.timers[timer].delay,10); f:fire(timer); eq(#f.played,2)
  f:fire(f.alerts.timer.id); eq(#f.played,3); eq(f.now,120)
  f.now=390; f:fire(f.alerts.timer.id,10); eq(#f.played,3); eq(f.alerts.acknowledged,true)
  eq(next(f.timers),nil); eq(#f.shown,1)
end)
test("autoroller long selected sounds do not overlap repeat reminders",function()
  local f=fixture({repeat_enabled=true}); f.duration=24
  f.alerts:result(target()); eq(f.timers[f.alerts.timer.id].delay,24.1)
end)
test("autoroller expiry stops its audio but leaves the held result notice",function()
  local f=fixture({repeat_enabled=true}); f.alerts:result(target())
  local hidden=f.hidden; f:fire(f.alerts.expiry.id); eq(f.alerts.acknowledged,true)
  eq(next(f.timers),nil); eq(f.hidden,hidden); eq(#f.shown,1)
end)
test("autoroller silence invalidates even timers whose cancellation fails",function()
  local f=fixture({repeat_enabled=true}); f.alerts:result(target())
  local oldTimer=f.timers[f.alerts.timer.id].fn; local oldExpiry=f.timers[f.alerts.expiry.id].fn
  f.cancelFails=true; assert(f.alerts:action("silence")); local hidden=f.hidden
  oldTimer(); oldExpiry(); eq(#f.played,1); eq(f.hidden,hidden); eq(f.alerts.timer,nil); eq(f.alerts.expiry,nil)
end)
test("autoroller clear and shutdown prevent stale reminders and new alerts",function()
  local f=fixture({repeat_enabled=true}); f.alerts:result(target()); local callback=f.timers[f.alerts.timer.id].fn
  f.alerts:clear(); callback(); eq(#f.played,1); eq(f.alerts.event,nil)
  f.alerts:result(target()); eq(#f.played,2); f.alerts:shutdown()
  eq(f.alerts:result(target()),false); eq(f.alerts:action("preview",{}),nil); eq(next(f.timers),nil)
end)
test("autoroller save updates reminder settings without accepting a held result",function()
  local f=fixture({repeat_enabled=true}); f.alerts:result(target()); local event=f.alerts.event
  f.config={enabled=false,repeat_enabled=true}; f.alerts:settingsChanged(); eq(next(f.timers),nil); eq(f.alerts.event,event)
  f.config={enabled=true,repeat_enabled=true,volume=50}; f.alerts:settingsChanged()
  f:fire(f.alerts.timer.id); eq(#f.played,2); eq(f.played[2].config.volume,50)
  f.alerts:silence(); f.alerts:settingsChanged(); eq(next(f.timers),nil)
end)
test("autoroller preview stops live reminders without dismissing or accepting the roll",function()
  local f=fixture({repeat_enabled=true}); f.alerts:result(target()); local event=f.alerts.event; local hidden=f.hidden
  f.alerts:action("preview",{sound="alarm"}); eq(next(f.timers),nil); eq(f.hidden,hidden); eq(f.alerts.event,event)
  eq(#f.played,2); eq(f.played[2].preview,true); assert(f.alerts:action("stop_preview")); eq(f.stops[#f.stops],true)
end)
test("autoroller custom choice cancelled or failed never mutates saved settings",function()
  local f=fixture(); f.choiceError="cancelled"; local config=f.config
  local value,err=f.alerts:action("choose",{}); eq(value,nil); eq(err,"cancelled"); eq(f.config,config)
  f.choice={custom_name="my sound.wav",custom_file=string.rep("a",64)..".wav"}
  eq(f.alerts:action("choose",{}),f.choice); eq(f.config,config)
end)
test("autoroller sound errors cannot cancel or accept the held result",function()
  local f=fixture({repeat_enabled=true}); f.playFails=true; assert(f.alerts:result(target()))
  eq(#f.shown,1); eq(next(f.timers),nil); eq(#f.messages,1); eq(f.alerts.event.kind,"target_hit")
  f.alerts:clear(); f.playThrows=true; assert(f.alerts:result(target())); eq(#f.shown,2)
end)
test("autoroller fallback warnings are displayed once per completion",function()
  local f=fixture({repeat_enabled=true}); f.warning="Custom sound unavailable; using three-tone."
  f.alerts:result(target()); f:fire(f.alerts.timer.id); eq(#f.played,2); eq(#f.messages,1)
end)
test("autoroller no clock cannot create unlimited reminders",function()
  local f=fixture({repeat_enabled=true}); f.now=nil; f.alerts:result(target())
  eq(#f.played,1); eq(next(f.timers),nil)
end)
test("autoroller invalid preview settings and unknown actions do not play audio",function()
  local f=fixture(); eq(f.alerts:action("preview",{volume=101}),nil)
  eq(f.alerts:action("anything",{}),nil); eq(#f.played,0)
end)
test("autoroller idle rolling cleanup avoids redundant audio and popup work",function()
  local f=fixture(); for i=1,100 do f.alerts:clear() end
  eq(#f.stops,0); eq(f.hidden,0)
  f.alerts:action("preview",{}); f.alerts:clear(); eq(f.hidden,1); eq(f.alerts.preview_active,false)
end)
test("autoroller failed replacement previews retain ownership until cleanup",function()
  for _,failure in ipairs({"playFails","playThrows"}) do
    local f=fixture(); assert(f.alerts:action("preview",{})); f[failure]=true
    eq(f.alerts:action("preview",{sound="horn"}),nil); eq(f.alerts.preview_active,true)
    local stops=#f.stops; f.alerts:shutdown(); assert(#f.stops>stops)
    eq(f.stops[#f.stops],true); eq(f.alerts.preview_active,false)
  end
end)
test("autoroller failed preview stops keep cleanup ownership without accepting a result",function()
  local f=fixture(); assert(f.alerts:action("preview",{}))
  f.alerts.audio.stop=function() return nil,"Stop unavailable." end
  eq(f.alerts:action("stop_preview"),nil); eq(f.alerts.preview_active,true)
  assert(f.alerts:result(target())); eq(f.alerts.preview_active,true)
  f.alerts:clear(); eq(f.alerts.preview_active,true); eq(f.alerts.event,nil)
  local stops=0; f.alerts.audio.stop=function() stops=stops+1; return true end
  f.alerts:shutdown(); eq(stops,2); eq(f.alerts.preview_active,false)
end)

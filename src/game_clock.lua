local Clock={}; Clock.__index=Clock

local function positive(value,fallback)
  value=tonumber(value)
  return value and value>0 and value or fallback
end

function Clock.new(settings,now)
  settings=type(settings)=="table" and settings or {}
  return setmetatable({
    speed=positive(settings.speed,2),
    sunrise_hour=math.max(0,math.min(23,math.floor(tonumber(settings.sunrise_hour) or 6))),
    sunset_hour=math.max(0,math.min(23,math.floor(tonumber(settings.sunset_hour) or 18))),
    days_per_month=math.max(1,math.floor(tonumber(settings.days_per_month) or 30)),
    months_per_year=math.max(1,math.floor(tonumber(settings.months_per_year) or 12)),
    now=type(now)=="function" and now or os.time,
  },Clock)
end

function Clock:sync(value,epoch)
  if type(value)~="table" then return nil,"invalid game time" end
  local hour,minute=tonumber(value.hour),tonumber(value.minute)
  if not hour or not minute or hour<0 or hour>23 or minute<0 or minute>59 then return nil,"invalid game time" end
  self.days_per_month=math.max(1,math.floor(tonumber(value.days_per_month) or self.days_per_month))
  self.months_per_year=math.max(1,math.floor(tonumber(value.months_per_year) or self.months_per_year))
  self.base={hour=math.floor(hour),minute=math.floor(minute),day=math.floor(tonumber(value.day) or 1),month=math.floor(tonumber(value.month) or 1),year=math.floor(tonumber(value.year) or 1)}
  self.synced_at=tonumber(epoch) or self.now()
  return true
end

function Clock:current(epoch)
  if not self.base or not self.synced_at then return nil end
  local elapsed=math.max(0,(tonumber(epoch) or self.now())-self.synced_at)
  local advanced=math.floor(elapsed*self.speed/60)
  local total=self.base.hour*60+self.base.minute+advanced
  local days=math.floor(total/1440); total=total%1440
  local hour=math.floor(total/60)
  local dayIndex=(self.base.day-1)+days
  local monthIndex=(self.base.month-1)+math.floor(dayIndex/self.days_per_month)
  return {hour=hour,minute=total%60,day=dayIndex%self.days_per_month+1,month=monthIndex%self.months_per_year+1,year=self.base.year+math.floor(monthIndex/self.months_per_year),
    period=(hour>=self.sunrise_hour and hour<self.sunset_hour) and "Daytime" or "Night"}
end

function Clock.format(value,seconds)
  if not value then return "—" end
  local hour=tonumber(value.hour) or 0; local suffix=hour>=12 and "PM" or "AM"; local shown=hour%12; if shown==0 then shown=12 end
  if seconds then return string.format("%d:%02d:%02d %s",shown,tonumber(value.minute) or 0,tonumber(value.second) or 0,suffix) end
  return string.format("%d:%02d %s",shown,tonumber(value.minute) or 0,suffix)
end

return Clock

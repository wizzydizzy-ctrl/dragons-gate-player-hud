local Size={MIN_HEIGHT=80,MAX_HEIGHT=600}
local presets={
  compact={target_height=120,min_height=80,max_height=160,height_percent=.21},
  normal={target_height=240,min_height=160,max_height=320,height_percent=.21},
  large={target_height=320,min_height=200,max_height=480,height_percent=.21},
}
local function finite(value)
  if type(value)~="number" and type(value)~="string" then return nil end
  local number=tonumber(value)
  if not number or number~=number or number==math.huge or number==-math.huge then return nil end
  return number
end
local function copy(input)
  local result={}
  for key,value in pairs(type(input)=="table" and input or {}) do result[key]=value end
  return result
end
function Size.clamp(value)
  local number=finite(value)
  return number and math.floor(math.max(Size.MIN_HEIGHT,math.min(Size.MAX_HEIGHT,number))+.5) or nil
end
function Size.mode(chat)
  if type(chat)~="table" then return "normal" end
  if presets[chat.size_mode] then return chat.size_mode end
  if chat.size_mode=="custom" and finite(chat.height_pixels) then return "custom" end
  return "normal"
end
function Size.forLayout(chat)
  local result=copy(chat); local mode=Size.mode(chat)
  result.size_mode=mode
  result.height_pixels=nil
  if mode=="custom" then
    result.height_pixels=Size.clamp(chat.height_pixels)
  elseif type(chat)=="table" and chat.size_mode==nil then
    -- Profiles with older geometry overrides retain them until the user
    -- explicitly chooses a preset or Reset Size.
    return result
  else
    for key,value in pairs(presets[mode]) do result[key]=value end
  end
  return result
end
function Size.change(chat,wanted)
  local result=copy(chat)
  local mode=type(wanted)=="string" and wanted:lower():match("^%s*(.-)%s*$") or nil
  if mode=="reset" then mode="normal" end
  if presets[mode] then
    result.size_mode=mode; result.height_pixels=nil
    return result
  end
  local pixels=finite(wanted)
  if not pixels or pixels<Size.MIN_HEIGHT or pixels>Size.MAX_HEIGHT then
    return nil,"Choose Compact, Normal, Large, Reset Size, or a height from 80 to 600 pixels."
  end
  result.size_mode="custom"; result.height_pixels=Size.clamp(pixels)
  return result
end
return Size

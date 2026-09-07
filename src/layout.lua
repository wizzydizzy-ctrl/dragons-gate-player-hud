local Layout={}
function Layout.lowerPanelGeometry(layout,psiVisible,webVisible,roundtimeActive)
  local available=math.max(0,(layout.window_height or 0)-(layout.header_height or 0)-(layout.command_line_clearance or 0))
  local inset=layout.lower_panel_padding
  local compass=layout.lower_compass_cell*3
  local utility=layout.lower_utility_height*2+5
  local roundtime=roundtimeActive and (layout.lower_roundtime_height or 0) or 0
  local roundtime_gap=roundtime>0 and (layout.lower_roundtime_gap or 0) or 0
  local fixed_bottom=inset+roundtime+roundtime_gap+utility+6+compass
  local function contentTop() return inset end
  local room=layout.lower_room_height
  local mapper=layout.mapper_visible and layout.lower_mapper_height or 0
  local mapper_min=(layout.lower_mapper_min_height or 0)+(layout.lower_mapper_toolbar_height or 0)
  local room_min=layout.lower_room_min_height or 1
  local function required(r,m)
    return contentTop()+r+layout.lower_row_gap+fixed_bottom+(m>0 and (m+layout.lower_mapper_gap) or 0)
  end
  local pressure=math.max(0,required(room,mapper)-available)
  local cut=math.min(pressure,room-room_min); room=room-cut; pressure=pressure-cut
  cut=math.min(pressure,math.max(0,mapper-mapper_min)); mapper=mapper-cut; pressure=pressure-cut
  if pressure>0 and mapper>0 then mapper=0; pressure=math.max(0,required(room,mapper)-available) end
  cut=math.min(pressure,room-room_min); room=room-cut; pressure=pressure-cut
  local panel=math.min(available,required(room,mapper))
  local content_top=contentTop()
  local roundtime_y=roundtime>0 and panel-inset-roundtime or panel-inset
  local utility_y=roundtime_y-roundtime_gap-utility
  local compass_y=utility_y-6-compass
  local mapper_y=mapper>0 and compass_y-layout.lower_mapper_gap-mapper or compass_y
  return {panel_height=panel,optional_count=(psiVisible and 1 or 0)+(webVisible and 1 or 0),show_psi=psiVisible==true,
    show_web=webVisible==true,room_height=room,
    mapper_height=mapper,content_top=content_top,mapper_y=mapper_y,compass_y=compass_y,
    utility_y=utility_y,compass_height=compass,utility_height=utility,
    roundtime_visible=roundtime>0,roundtime_y=roundtime_y,roundtime_height=roundtime}
end
function Layout.detailsPlacement() return "right" end
function Layout.detailsCardRows(columns) return 5 end
function Layout.detailsFit(rail_bottom,inventory_y,details_height,minimum_inventory_height)
  return (tonumber(rail_bottom) or 0)-(tonumber(details_height) or 0)-12-(tonumber(inventory_y) or 0)>=(tonumber(minimum_inventory_height) or 0)
end
local function clamp(value,minimum,maximum) return math.max(minimum,math.min(maximum,math.floor(value+0.5))) end
local function chatMetrics(width,height,layout,settings)
  settings=type(settings)=="table" and settings or {}
  local default_percent=.21
  local target=tonumber(settings.target_height) or 240
  local minimum=tonumber(settings.min_height) or 160
  local maximum=tonumber(settings.max_height) or 320
  local percent=tonumber(settings.height_percent) or default_percent
  local minimum_console_remainder=math.max(1,math.floor(tonumber(settings.minimum_console_remainder) or 120))
  local chat_chrome_height=44
  local chat_output_minimum=16
  local chat_functional_minimum=chat_chrome_height+chat_output_minimum
  if maximum<minimum then maximum=minimum end
  local bottom=tonumber(layout.bottom) or 0
  layout.header_height=math.min(layout.top,math.max(0,height-bottom-chat_functional_minimum-1))
  local configured_height=clamp(height*percent*(target/(1080*default_percent)),minimum,maximum)
  local available=math.max(0,height-layout.header_height-bottom)
  local adaptive_console_remainder=math.min(minimum_console_remainder,math.max(1,available-chat_functional_minimum))
  local available_chat=math.min(math.max(0,available-1),math.max(chat_functional_minimum,available-adaptive_console_remainder))
  layout.minimum_console_remainder=minimum_console_remainder
  layout.chat_functional_minimum=chat_functional_minimum
  layout.chat_height=math.min(configured_height,available_chat)
  layout.chat_x=layout.console_left
  layout.chat_width=layout.console_width
  layout.chat_padding=8
  layout.chat_scrollbar_allowance=18
  layout.chat_font=clamp(width/148,11,15)
  layout.chat_character_width=math.max(6,layout.chat_font*.62)
  layout.chat_inner_width=math.max(1,layout.chat_width-(2*layout.chat_padding)-layout.chat_scrollbar_allowance)
  layout.chat_wrap_columns=math.max(1,math.floor(layout.chat_inner_width/layout.chat_character_width))
  layout.console_top=layout.header_height+layout.chat_height
  layout.console_remainder=math.max(0,height-bottom-layout.console_top)
  layout.chat_output_height=math.max(0,layout.chat_height-chat_chrome_height)
  layout.top=layout.console_top
  return layout
end
local function metrics(width,height,layout,chatSettings,mapperSettings,vitals)
  layout.console_gutter=layout.mode=="compact" and 0 or math.min(12,math.floor(width*.005+.5))
  layout.console_left=layout.left+layout.console_gutter
  layout.console_right=layout.right+layout.console_gutter
  layout.console_width=width-layout.console_left-layout.console_right
  layout.body_font=clamp(width/100,16,22); layout.small_font=clamp((layout.body_font-2)*2,28,40); layout.heading_font=clamp(layout.body_font+5,21,27)
  layout.equipment_font=clamp(layout.body_font-3,13,18)
  layout.equipment_line_height=layout.equipment_font+4
  layout.header_clock_font=layout.mode=="medium" and 10 or clamp(layout.body_font-5,11,17)
  layout.color_toggle_font=clamp(layout.body_font-5,10,14)
  layout.color_toggle_height=clamp(layout.color_toggle_font+8,20,24)
  layout.attribute_strip_font=clamp(layout.console_width/100,10,14)
  layout.panel_padding=clamp(width/120,12,22); layout.gauge_height=clamp(layout.small_font+10,38,50); layout.row_gap=clamp(layout.body_font*.7,11,15)
  layout.equipment_padding=clamp(layout.panel_padding*.7,8,14)
  layout.combat_font=clamp(layout.equipment_font-1,12,17); layout.combat_line_height=layout.combat_font+3; layout.combat_padding=clamp(layout.equipment_padding-1,7,12)
  layout.title_height=layout.heading_font+30
  layout.room_height=layout.heading_font+layout.body_font*6+54; layout.exit_height=layout.small_font+16
  layout.identity_height=layout.heading_font+layout.body_font*6+56
  layout.inventory_font=clamp(layout.body_font-2,14,20); layout.inventory_row_height=layout.inventory_font+10
  layout.list_font=clamp(layout.inventory_font-4,10,14); layout.list_title_font=layout.list_font+3; layout.list_row_height=math.ceil(layout.list_font*1.3); layout.list_visible_rows=5
  layout.list_padding=clamp(layout.panel_padding*.5,6,10)
  layout.list_horizontal_scrollbar_height=clamp(layout.list_font+3,16,20)
  layout.details_line_height=layout.body_font+6; layout.compass_font=clamp(layout.body_font,16,22); layout.compass_cell=layout.compass_font+14
  layout.utility_font=clamp(layout.body_font-4,12,18); layout.utility_height=layout.utility_font+12
  local function scaled(value) return math.floor(value*.8+.5) end
  layout.lower_scale=.8
  layout.lower_body_font=scaled(layout.body_font); layout.lower_small_font=layout.lower_body_font; layout.lower_heading_font=scaled(layout.heading_font)
  layout.lower_panel_padding=scaled(layout.panel_padding); layout.lower_gauge_height=layout.lower_small_font+14; layout.lower_row_gap=scaled(layout.row_gap)
  layout.lower_title_height=0; layout.lower_room_height=scaled(layout.room_height)
  layout.lower_room_min_height=math.max(layout.lower_heading_font+layout.lower_body_font+20,56)
  layout.lower_compass_font=scaled(layout.compass_font); layout.lower_compass_cell=scaled(layout.compass_cell)
  layout.lower_utility_font=scaled(layout.utility_font); layout.lower_utility_height=scaled(layout.utility_height); layout.lower_section_gap=scaled(44)
  layout.lower_roundtime_font=math.max(11,layout.lower_utility_font-1)
  layout.lower_roundtime_height=layout.lower_roundtime_font+10
  layout.lower_roundtime_gap=5
  layout.vitals_strip_padding=6
  layout.vitals_strip_gap=6
  local active=2+((vitals and vitals.psi and vitals.psi.visible) and 1 or 0)+((vitals and vitals.web and vitals.web.visible) and 1 or 0)
  layout.vitals_strip_rows=(layout.mode=="compact" and active>2) and 2 or 1
  layout.vitals_strip_height=layout.lower_gauge_height*layout.vitals_strip_rows+layout.vitals_strip_gap*(layout.vitals_strip_rows-1)+layout.vitals_strip_padding*2
  -- Mudlet's command line/search strip occupies the bottom of the window but is
  -- not part of the console border. Keep HUD controls above that native chrome.
  local desired_clearance=clamp(layout.body_font+12,28,36)
  local safe_clearance=math.max(0,height-layout.vitals_strip_height-60-50-1)
  layout.command_line_clearance=math.min(desired_clearance,safe_clearance)
  layout.bottom=layout.vitals_strip_height+layout.command_line_clearance; layout.window_height=height
  chatMetrics(width,height,layout,chatSettings)
  layout.lower_mapper_gap=layout.lower_row_gap
  if layout.mode=="compact" or (type(mapperSettings)=="table" and mapperSettings.enabled==false) then
    layout.mapper_visible=false; layout.lower_mapper_height=0; layout.lower_mapper_min_height=0; layout.lower_mapper_toolbar_height=0; layout.lower_room_visible_height=0
  else
    mapperSettings=type(mapperSettings)=="table" and mapperSettings or {}
    local responsiveMinimum=layout.mode=="wide" and 140 or 90
    local minimum=math.max(responsiveMinimum,math.floor(tonumber(mapperSettings.minimum_height) or 90))
    local toolbar=scaled(30)
    layout.lower_mapper_min_height=minimum
    layout.lower_mapper_toolbar_height=toolbar
    local available=math.max(0,height-layout.top)
    local percent=math.max(.20,math.min(.70,tonumber(mapperSettings.height_percent) or .40))
    local maximum=clamp(tonumber(mapperSettings.maximum_height) or 380,minimum,700)
    local desired=clamp(available*percent,minimum,maximum)
    layout.mapper_visible=available>=minimum+toolbar+180
    layout.lower_mapper_height=layout.mapper_visible and desired+toolbar or 0
    layout.lower_room_visible_height=layout.lower_room_height
  end
  return layout
end
function Layout.compute(width,height,chatSettings,mapperSettings,vitals)
  width=tonumber(width) or 1200; height=tonumber(height) or 800
  local rail=math.floor(width*.17)
  local result
  if width>=1400 then result=metrics(width,height,{mode="wide",left=rail,right=rail,top=74,bottom=0,show_character_rail=true,show_room_compass=height>=700,vitals_side="center"},chatSettings,mapperSettings,vitals)
  elseif width>=800 then result=metrics(width,height,{mode="medium",left=rail,right=rail,top=66,bottom=0,show_character_rail=true,show_room_compass=height>=650,vitals_side="center"},chatSettings,mapperSettings,vitals)
  else result=metrics(width,height,{mode="compact",left=0,right=0,top=116,bottom=0,show_character_rail=false,show_room_compass=false,vitals_side="center"},chatSettings,mapperSettings,vitals) end
  result.window_width=width
  result.window_height=height
  return result
end
return Layout

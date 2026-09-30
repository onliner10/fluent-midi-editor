-- The design system. Every colour, size and control of the editor's panels
-- comes from here; other files never draw a raw ImGui widget, push a style or
-- write a colour. docs/design.md explains the rules. tests/test_design.py
-- (lint, contrast) and tests/reaper/layout_test.lua (the layout audit below)
-- enforce them.
local T={}

-- Colour tokens. Name them by role, not by look.
T.color={
  -- surfaces, darkest to lightest
  well=0x191B1EFF,      -- inputs, sliders, the piano roll and graphs
  bg=0x1D1F23FF,        -- window
  panel=0x25282DFF,     -- sidebar, piano roll header rows, modulation panel
  raised=0x30343AFF,    -- buttons
  hover=0x3B4047FF, press=0x464C54FF,
  line=0x363A41FF,      -- borders and separators
  -- text, most to least important
  text=0xE6E8EBFF,      -- content and labels
  muted=0xA0A8B1FF,     -- secondary information
  faint=0x7D858EFF,     -- headings, hints, axis labels
  on_accent=0x1D1F23FF, -- text on the accent fill
  -- the one accent: selection, on-state, playhead, the primary action
  accent=0xF2A04EFF, accent_hover=0xFFB872FF, accent_press=0xE08F3EFF, accent_text=0xFFCB94FF,
  -- piano roll
  key_white=0x454C55FF, key_black=0x25292EFF, row_white=0x282B30FF, row_black=0x222529FF,
  row_line=0x1E202330, bar_line=0x89939E78, beat_line=0x78838F40, step_line=0x78838F20,
  velocity_bar=0x89939E60, velocity_mid=0xFFFFFF13, graph_grid=0x78838F38,
  range_fill=0xA5CBE217, range_ruler=0xFFAD5935, range_edge=0xFFAD5970,
  past_end=0x10121570, note_muted=0x697279FF, note_mute_line=0x272D30FF,
  note_selected=0xFFFFFFFF, note_text_dark=0x18232BFF,
  view_fill=0xFFFFFF10, view_edge=0xFFFFFF38, repeat_curve=0xF2A04E70,
  popup=0x2A2D33FA,
}
-- One colour per clip, in track order. Colours are data here, not decoration.
T.clips={0x76C7BDFF,0xDE9CC5FF,0xE5C377FF,0x89B3EFFF,0xAECF84FF,0xCCAFF2FF}
-- Spacing scale. Every gap and padding is one of these.
T.space={xs=4,sm=8,md=16,lg=24}
-- Sizes. Controls are all `control` high; widths are these tokens or automatic.
T.size={control=24,button=56,icon=32,field=64,combo=80,wide=136,sidebar=240,radius=6}

-- A colour with another alpha (0-255).
function T.alpha(color,a) return (color&0xFFFFFF00)|a end
-- WCAG contrast ratio of two opaque colours.
function T.contrast(a,b)
  local function lum(c)
    local function ch(v) v=v/255; return v<=0.03928 and v/12.92 or ((v+0.055)/1.055)^2.4 end
    return 0.2126*ch((c>>24)&255)+0.7152*ch((c>>16)&255)+0.0722*ch((c>>8)&255)
  end
  local x,y=lum(a),lum(b); if x<y then x,y=y,x end
  return (x+0.05)/(y+0.05)
end

function T.new(ImGui,ctx)
  local C,S,Z=T.color,T.space,T.size
  local ui={C=C,space=S,size=Z,clips=T.clips,alpha=T.alpha}
  local colors={
    {ImGui.Col_WindowBg,C.bg},{ImGui.Col_ChildBg,C.panel},{ImGui.Col_PopupBg,C.popup},
    {ImGui.Col_Border,C.line},{ImGui.Col_Separator,C.line},{ImGui.Col_SeparatorHovered,C.accent},
    {ImGui.Col_TitleBg,C.bg},{ImGui.Col_TitleBgActive,C.panel},{ImGui.Col_TitleBgCollapsed,C.bg},
    {ImGui.Col_FrameBg,C.well},{ImGui.Col_FrameBgHovered,C.well},{ImGui.Col_FrameBgActive,C.well},
    {ImGui.Col_Button,C.raised},{ImGui.Col_ButtonHovered,C.hover},{ImGui.Col_ButtonActive,C.press},
    {ImGui.Col_Header,T.alpha(C.text,0x0F)},{ImGui.Col_HeaderHovered,T.alpha(C.text,0x17)},{ImGui.Col_HeaderActive,T.alpha(C.text,0x21)},
    {ImGui.Col_CheckMark,C.accent},{ImGui.Col_SliderGrab,C.accent},{ImGui.Col_SliderGrabActive,C.accent_hover},
    {ImGui.Col_Text,C.text},{ImGui.Col_TextDisabled,C.faint},
    {ImGui.Col_ScrollbarBg,T.alpha(C.bg,0)},{ImGui.Col_ScrollbarGrab,C.hover},
    {ImGui.Col_ScrollbarGrabHovered,C.press},{ImGui.Col_ScrollbarGrabActive,C.press},
    {ImGui.Col_ResizeGrip,T.alpha(C.accent,0)},{ImGui.Col_ResizeGripHovered,T.alpha(C.accent,0x66)},
    {ImGui.Col_ResizeGripActive,T.alpha(C.accent,0xAA)},
  }
  -- What a frame holds besides its padding (the text line), measured in the
  -- window each frame; frames are then padded to exactly the control height.
  local content
  local function vars()
    local pad=(Z.control-(content or ImGui.GetTextLineHeight(ctx)))/2
    return {
      {ImGui.StyleVar_WindowRounding,Z.radius},{ImGui.StyleVar_ChildRounding,Z.radius},{ImGui.StyleVar_PopupRounding,Z.radius},
      {ImGui.StyleVar_FrameRounding,5},{ImGui.StyleVar_GrabRounding,4},{ImGui.StyleVar_ScrollbarRounding,Z.radius},
      {ImGui.StyleVar_ScrollbarSize,10},{ImGui.StyleVar_GrabMinSize,12},
      {ImGui.StyleVar_WindowPadding,S.sm,S.sm},{ImGui.StyleVar_FramePadding,S.sm+2,pad},
      {ImGui.StyleVar_ItemSpacing,S.sm,S.sm},{ImGui.StyleVar_ItemInnerSpacing,6,6},
      {ImGui.StyleVar_PopupBorderSize,1},{ImGui.StyleVar_ChildBorderSize,1},{ImGui.StyleVar_FrameBorderSize,0},
    }
  end
  local pushed=0
  -- Around the whole window. pop() is safe to pcall after a failed frame.
  function ui:push()
    for _,c in ipairs(colors) do ImGui.PushStyleColor(ctx,c[1],c[2]) end
    local list=vars(); pushed=#list
    for _,v in ipairs(list) do ImGui.PushStyleVar(ctx,v[1],v[2],v[3]) end
  end
  function ui:pop() ImGui.PopStyleVar(ctx,pushed); ImGui.PopStyleColor(ctx,#colors) end

  ---------------------------------------------------------------------------
  -- Layout audit. Every component records where it was drawn; end_frame()
  -- reports controls that overlap, leave their panel or break the control
  -- height. Tests turn it on; it costs nothing otherwise.
  local audit,items,panels,anchors=false,{},{},{}
  local CONTROL_KINDS={button=true,combo=true,input=true,slider=true,switch=true,row=true,arrow=true}
  function ui:begin_frame(enabled)
    local _,pad=ImGui.GetStyleVar(ctx,ImGui.StyleVar_FramePadding)
    content=ImGui.GetFrameHeight(ctx)-2*pad
    audit=enabled; items={}; anchors={}
    if audit then
      local x,y=ImGui.GetWindowPos(ctx); local w,h=ImGui.GetWindowSize(ctx)
      panels={{id='window',x1=x,y1=y,x2=x+w,y2=y+h}}
    end
  end
  local function track(kind,label,x1,y1,x2,y2)
    if not audit then return end
    if not x1 then x1,y1=ImGui.GetItemRectMin(ctx); x2,y2=ImGui.GetItemRectMax(ctx) end
    items[#items+1]={kind=kind,label=label or kind,x1=x1,y1=y1,x2=x2,y2=y2,panel=panels[#panels]}
  end
  -- A named area drawn by hand (the ruler, a graph), for tests to find.
  function ui:anchor(name,x1,y1,x2,y2) if audit then anchors[name]={x1,y1,x2,y2} end end
  -- Problems found this frame, and every item as "kind label x1 y1 x2 y2".
  function ui:end_frame()
    if not audit then return end
    local problems,layout={},{}
    local function where(it) return string.format('%s "%s" (%.0f,%.0f)-(%.0f,%.0f)',it.kind,it.label,it.x1,it.y1,it.x2,it.y2) end
    for i,a in ipairs(items) do
      local p=a.panel
      if a.x1<p.x1-0.5 or a.y1<p.y1-0.5 or a.x2>p.x2+0.5 or a.y2>p.y2+0.5 then
        problems[#problems+1]=where(a)..' leaves panel '..p.id
      end
      if CONTROL_KINDS[a.kind] and math.abs(a.y2-a.y1-Z.control)>0.5 then
        problems[#problems+1]=where(a)..' is not '..Z.control..' px high'
      end
      for j=i+1,#items do local b=items[j]
        if a.panel==b.panel and math.min(a.x2,b.x2)-math.max(a.x1,b.x1)>0.5 and math.min(a.y2,b.y2)-math.max(a.y1,b.y1)>0.5 then
          problems[#problems+1]=where(a)..' overlaps '..where(b)
        end
      end
      layout[#layout+1]=string.format('%s\t%s\t%.0f\t%.0f\t%.0f\t%.0f',a.kind,a.label,a.x1,a.y1,a.x2,a.y2)
    end
    for name,r in pairs(anchors) do layout[#layout+1]=string.format('anchor\t%s\t%.0f\t%.0f\t%.0f\t%.0f',name,r[1],r[2],r[3],r[4]) end
    return problems,layout
  end

  ---------------------------------------------------------------------------
  -- Layout
  local function text_w(s) return (ImGui.CalcTextSize(ctx,(s:gsub('##.*','')))) end
  local function width_of(size,label)
    if size=='fill' then return -1 end
    -- {rest=w}: fill the row but leave w for what follows on it.
    if type(size)=='table' then return math.max(Z.combo,ImGui.GetContentRegionAvail(ctx)-assert(size.rest)) end
    if size then return (assert(Z[size],'unknown size token '..tostring(size))) end
    -- Automatic: the label plus padding, at least a button, on the 8 px grid.
    local w=math.max(Z.button,text_w(label)+2*(S.sm+2))
    return math.ceil(w/S.sm)*S.sm
  end
  -- The width a control will take, for right-aligning or centring it.
  function ui:width(label,size) return width_of(size,label) end
  function ui:text_width(s) return text_w(s) end
  function ui:line_height() return ImGui.GetTextLineHeight(ctx) end
  function ui:same_line() ImGui.SameLine(ctx) end
  -- Put the next item at the right edge of the current row.
  function ui:right_align(width)
    ImGui.SameLine(ctx)
    local x=ImGui.GetCursorPosX(ctx); local room=ImGui.GetContentRegionAvail(ctx)
    ImGui.SetCursorPosX(ctx,x+math.max(0,room-width))
  end
  -- Centre the next item of this width in the current panel.
  function ui:center(width)
    local room=ImGui.GetContentRegionAvail(ctx)
    ImGui.SetCursorPosX(ctx,ImGui.GetCursorPosX(ctx)+math.max(0,(room-width)/2))
  end
  -- Centre a block of this height vertically in what is left of the panel.
  function ui:middle(height)
    local _,room=ImGui.GetContentRegionAvail(ctx)
    ImGui.SetCursorPosY(ctx,ImGui.GetCursorPosY(ctx)+math.max(0,(room-height)/2))
  end
  function ui:gap(size) ImGui.Dummy(ctx,0,S[size or 'sm']) end
  function ui:indent(level) ImGui.SetCursorPosX(ctx,ImGui.GetCursorPosX(ctx)+(level or 1)*S.lg) end
  function ui:separator() ImGui.Separator(ctx) end
  -- A panel: a bordered child region laid out to fit, so it never scrolls
  -- unless scroll is asked for. fn draws its content.
  function ui:panel(id,w,h,fn,scroll)
    local flags=scroll and 0 or ImGui.WindowFlags_NoScrollbar|ImGui.WindowFlags_NoScrollWithMouse
    -- ReaImGui: EndChild only after BeginChild returned true.
    if not ImGui.BeginChild(ctx,id,w,h,ImGui.ChildFlags_Borders,flags) then return end
    if audit then
      local x,y=ImGui.GetWindowPos(ctx); local pw,ph=ImGui.GetWindowSize(ctx)
      panels[#panels+1]={id=id,x1=x,y1=y,x2=x+pw,y2=y+ph}
    end
    local ok,err=xpcall(fn,debug.traceback)
    if audit then panels[#panels]=nil end
    ImGui.EndChild(ctx)
    if not ok then error(err,0) end
  end
  -- Items stacked in a column beside the previous item.
  function ui:column(fn)
    ImGui.BeginGroup(ctx); local ok,err=xpcall(fn,debug.traceback); ImGui.EndGroup(ctx)
    if not ok then error(err,0) end
  end

  ---------------------------------------------------------------------------
  -- Text
  function ui:text(s) ImGui.Text(ctx,s); track('text',s) end
  function ui:muted(s) ImGui.TextColored(ctx,C.muted,s); track('text',s) end
  function ui:faint(s) ImGui.TextColored(ctx,C.faint,s); track('text',s) end
  -- Text in a data colour (a clip's colour).
  function ui:colored(s,color) ImGui.TextColored(ctx,color,s); track('text',s) end
  function ui:wrapped(s) ImGui.TextWrapped(ctx,s); track('text',s) end
  -- Something needs attention: wrapped, in the accent.
  function ui:warning(s)
    ImGui.PushStyleColor(ctx,ImGui.Col_Text,C.accent_text); ImGui.TextWrapped(ctx,s); ImGui.PopStyleColor(ctx)
    track('text',s)
  end
  -- A section title: small caps, faint, with room above unless first.
  function ui:heading(s,first)
    if not first then ui:gap('xs') end
    ImGui.TextColored(ctx,C.faint,s:upper()); track('text',s)
  end
  -- Text beside controls on the same row, centred on their height; strong
  -- for a panel title.
  function ui:label(s,strong) ImGui.AlignTextToFramePadding(ctx); if strong then ui:text(s) else ui:muted(s) end end
  -- Key / action rows, as in a cheat sheet.
  local HINT_GAP=2
  function ui:key_hints(rows)
    ImGui.PushStyleVar(ctx,ImGui.StyleVar_ItemSpacing,S.sm,HINT_GAP)
    local x=ImGui.GetCursorPosX(ctx)
    for _,row in ipairs(rows) do
      ImGui.Text(ctx,row[1]); track('text',row[1]); ImGui.SameLine(ctx,x+11*S.sm)
      ImGui.TextColored(ctx,C.muted,row[2]); track('text',row[2])
    end
    ImGui.PopStyleVar(ctx)
  end
  function ui:key_hints_height(rows) return #rows*(ImGui.GetTextLineHeight(ctx)+HINT_GAP) end

  ---------------------------------------------------------------------------
  -- Controls. Each takes an optional tooltip and a size token (see T.size),
  -- or nil for an automatic width on the grid. Tooltips name the shortcut.
  function ui:tip(text)
    if text and ImGui.IsItemHovered(ctx,ImGui.HoveredFlags_DelayNormal) then ImGui.SetTooltip(ctx,text) end
  end
  local function button(label,size,tip,colors,border)
    for _,c in ipairs(colors or {}) do ImGui.PushStyleColor(ctx,c[1],c[2]) end
    if border then ImGui.PushStyleVar(ctx,ImGui.StyleVar_FrameBorderSize,1) end
    local clicked=ImGui.Button(ctx,label,width_of(size,label),Z.control)
    if border then ImGui.PopStyleVar(ctx) end
    if colors then ImGui.PopStyleColor(ctx,#colors) end
    track('button',label); ui:tip(tip)
    return clicked
  end
  function ui:button(label,tip,size) return button(label,size,tip) end
  -- A toggle reads as on by its tinted fill, outline and accent text.
  function ui:toggle(label,on,tip,size)
    if not on then return button(label,size,tip) end
    return button(label,size,tip,{{ImGui.Col_Button,T.alpha(C.accent,0x30)},{ImGui.Col_ButtonHovered,T.alpha(C.accent,0x48)},
      {ImGui.Col_ButtonActive,T.alpha(C.accent,0x60)},{ImGui.Col_Text,C.accent_text},{ImGui.Col_Border,T.alpha(C.accent,0x90)}},true)
  end
  -- The one main action of a view.
  function ui:primary(label,tip,size)
    return button(label,size,tip,{{ImGui.Col_Button,C.accent},{ImGui.Col_ButtonHovered,C.accent_hover},
      {ImGui.Col_ButtonActive,C.accent_press},{ImGui.Col_Text,C.on_accent}})
  end
  -- A disclosure arrow for a collapsible panel.
  function ui:arrow(id,open,tip)
    local clicked=ImGui.ArrowButton(ctx,id,open and ImGui.Dir_Down or ImGui.Dir_Right)
    track('arrow',id); ui:tip(tip)
    return clicked
  end
  -- An on/off switch with its label. Returns changed, value.
  function ui:switch(label,value,tip)
    local x,y=ImGui.GetCursorScreenPos(ctx); local text=label:gsub('##.*','')
    local clicked=ImGui.InvisibleButton(ctx,label,28+S.sm+text_w(text),Z.control)
    local hovered=ImGui.IsItemHovered(ctx)
    if clicked then value=not value end
    local dl=ImGui.GetWindowDrawList(ctx); local cy=y+Z.control/2
    local fill=value and (hovered and C.accent_hover or C.accent) or (hovered and C.press or C.hover)
    ImGui.DrawList_AddRectFilled(dl,x,cy-8,x+28,cy+8,fill,8)
    ImGui.DrawList_AddCircleFilled(dl,value and x+20 or x+8,cy,6,value and C.on_accent or C.text)
    ImGui.DrawList_AddText(dl,x+28+S.sm,cy-ImGui.GetTextLineHeight(ctx)/2,C.text,text)
    track('switch',text); ui:tip(tip)
    return clicked,value
  end
  -- A dropdown that looks like the buttons next to it. fn lists ui:option()s.
  function ui:combo(id,preview,size,fn,tip)
    ImGui.PushStyleColor(ctx,ImGui.Col_FrameBg,C.raised); ImGui.PushStyleColor(ctx,ImGui.Col_FrameBgHovered,C.hover)
    ImGui.PushStyleColor(ctx,ImGui.Col_Button,C.raised); ImGui.PushStyleColor(ctx,ImGui.Col_ButtonHovered,C.hover)
    ImGui.SetNextItemWidth(ctx,width_of(size,preview))
    local open=ImGui.BeginCombo(ctx,id,preview,ImGui.ComboFlags_HeightLarge)
    ImGui.PopStyleColor(ctx,4)
    local ok,err=true
    if open then
      local was=audit; audit=false
      ok,err=xpcall(fn,debug.traceback); audit=was
      ImGui.EndCombo(ctx)
    end
    track('combo',id); if not open then ui:tip(tip) end
    if not ok then error(err,0) end
  end
  -- An entry in a dropdown or popup list; color tints its text (clip colours).
  function ui:option(label,selected,color)
    if color then ImGui.PushStyleColor(ctx,ImGui.Col_Text,color) end
    local chosen=ImGui.Selectable(ctx,label,selected)
    if color then ImGui.PopStyleColor(ctx) end
    return chosen
  end
  -- A full-width list row: colour swatch, label, and a right-aligned note.
  function ui:list_row(id,selected,swatch,label,note,tip)
    local x,y=ImGui.GetCursorScreenPos(ctx); local w=ImGui.GetContentRegionAvail(ctx)
    local clicked=ImGui.Selectable(ctx,id,selected,0,w,Z.control)
    local dl=ImGui.GetWindowDrawList(ctx); local cy=y+Z.control/2; local th=ImGui.GetTextLineHeight(ctx)
    if selected then ImGui.DrawList_AddRectFilled(dl,x,y+3,x+2,y+Z.control-3,swatch,1) end
    ImGui.DrawList_AddRectFilled(dl,x+S.sm,cy-4,x+S.sm+8,cy+4,swatch,2)
    local nw=note and text_w(note) or 0
    ImGui.DrawList_PushClipRect(dl,x,y,x+w-nw-2*S.sm,y+Z.control,true)
    ImGui.DrawList_AddText(dl,x+S.lg,cy-th/2,selected and C.text or C.muted,label)
    ImGui.DrawList_PopClipRect(dl)
    if note then ImGui.DrawList_AddText(dl,x+w-nw-S.sm,cy-th/2,C.faint,note) end
    -- Selectable's item box includes the gap around it; record the drawn row.
    track('row',label,x,y,x+w,y+Z.control); ui:tip(tip)
    return clicked
  end
  -- Returns submitted (Enter), text, active.
  function ui:input_text(id,text,size,tip)
    ImGui.SetNextItemWidth(ctx,width_of(size,text))
    local submitted,value=ImGui.InputText(ctx,id,text,ImGui.InputTextFlags_EnterReturnsTrue|ImGui.InputTextFlags_AutoSelectAll)
    local active=ImGui.IsItemActive(ctx)
    track('input',id); ui:tip(tip)
    return submitted,value,active
  end
  -- Returns changed, value.
  function ui:input_int(label,value,size,tip)
    ImGui.SetNextItemWidth(ctx,width_of(size,label))
    local changed,v=ImGui.InputInt(ctx,label,value)
    track('input',label); ui:tip(tip)
    return changed,v
  end
  -- Sliders return changed, value, released (the edit is finished).
  function ui:slider_int(id,value,min,max,format,size,tip)
    ImGui.SetNextItemWidth(ctx,width_of(size or 'fill',id))
    local changed,v=ImGui.SliderInt(ctx,id,value,min,max,format)
    local released=ImGui.IsItemDeactivatedAfterEdit(ctx)
    track('slider',id); ui:tip(tip)
    return changed,v,released
  end
  function ui:slider_double(id,value,min,max,format,size,tip)
    ImGui.SetNextItemWidth(ctx,width_of(size or 'fill',id))
    local changed,v=ImGui.SliderDouble(ctx,id,value,min,max,format)
    local released=ImGui.IsItemDeactivatedAfterEdit(ctx)
    track('slider',id); ui:tip(tip)
    return changed,v,released
  end
  -- A region the caller draws and handles itself (piano roll, graph).
  -- Returns what ImGui.InvisibleButton returns.
  function ui:region(id,w,h,flags)
    local clicked=ImGui.InvisibleButton(ctx,id,w,h,flags or ImGui.ButtonFlags_MouseButtonLeft)
    track('region',id)
    return clicked
  end
  -- A handle laid over the gap above the cursor (a resize handle). Not
  -- audited: it sits in the gap between panels on purpose.
  function ui:handle_above(id,w,h)
    local x,y=ImGui.GetCursorScreenPos(ctx)
    ImGui.SetCursorScreenPos(ctx,x,y-h)
    local clicked=ImGui.InvisibleButton(ctx,id,w,h)
    ImGui.SetCursorScreenPos(ctx,x,y)
    return clicked
  end
  -- A thin divider between toolbar groups, on the same row.
  function ui:divider()
    ImGui.SameLine(ctx)
    local x,y=ImGui.GetCursorScreenPos(ctx)
    ImGui.DrawList_AddLine(ImGui.GetWindowDrawList(ctx),x,y+S.xs,x,y+Z.control-S.xs,C.line,1)
    ImGui.Dummy(ctx,1,Z.control); ImGui.SameLine(ctx)
  end
  return ui
end
return T

CoordMode, Pixel
#include %A_ScriptDir%//Gdip_all.ahk
global overlay_var

overlayToken := Gdip_Startup()

class Overlay
{
    __New(name, content, x_pos, y_pos, font_num:=3, font_size:=16, is_bold:=0, text_color:="White", has_background:=false, background_color:="Black", round_corners:=0)
    {
        this.name := name
        this.content := content
        this.x_pos := x_pos
        this.y_pos := y_pos
        this.font_num := font_num
        this.font_size := font_size
        this.is_bold := is_bold
        this.text_color := text_color
        this.has_background := has_background
        this.background_showing := false
        this.background_opacity := 100
        this.background_padding := 7
        this.round_corners := round_corners
        this.dimensions := [0, 0]
        this.paused := false

        fonts := ["Arial", "Verdana", "Helvetica", "Courier New", "Small Fonts", "Impact"]
        Gui, % this.name ": Color", 0x0101FF
        Gui, % this.name ": +E0x20 +E0x02000000 -caption +hWndoverlayHwnd +AlwaysOnTop +ToolWindow"
        this.hwnd := overlayHwnd
        font_choice := (font_num >= 1 && font_num <= 6) ? fonts[font_num] : font_num
        Gui, % this.name ": Font", q3 s%font_size% c%text_color%, % font_choice

        if (is_bold)
            Gui, % this.name ": Font", Bold

        this.has_timer := false
        this.has_countdown := false
        temp_content := content

        ; Handle regular timer
        if (RegExMatch(content, "!timer(\d{5})", matchTimer))
        {
            this.timer_format := [SubStr(matchTimer1, 1, 1), SubStr(matchTimer1, 2, 1), SubStr(matchTimer1, 3, 1), SubStr(matchTimer1, 4, 1), SubStr(matchTimer1, 5, 1)]
            temp_content := RegExReplace(content, "!timer\d{5}", format_time(0, this.timer_format[1], this.timer_format[2], this.timer_format[3], this.timer_format[4], this.timer_format[5]))
            this.has_timer := true
        }

        ; Handle countdown timer
        else if (RegExMatch(content, "!countdown(\d+),(\d+),(\d+),(\d+)", matchCountdown))
        {
            this.countdown_time := (matchCountdown1 * 3600 + matchCountdown2 * 60 + matchCountdown3) * 1000 ; Convert to milliseconds
            show_hours := matchCountdown1 > 0
            show_minutes := matchCountdown2 > 0 || show_hours
            show_seconds := matchCountdown3 > 0 || show_minutes
            this.timer_format := [show_hours, show_minutes, show_seconds, true, matchCountdown4]
            temp_content := RegExReplace(content, "!countdown\d+,\d+,\d+,\d+", format_time(this.countdown_time, this.timer_format[1], this.timer_format[2], this.timer_format[3], this.timer_format[4], this.timer_format[5], "countdown"))
            this.has_countdown := true
        }

        Gui, % this.name ": Add", Text, % " BackGroundTrans HwndcontrolHwnd x0 y0 w3000 +" pos " +0x200 voverlay_var", % temp_content
        this.controlHwnd := controlHwnd
        if (has_background || true)
        {
            this.__create_background(background_color)
            this.__update_background_position(temp_content)
        }

        Gui, % this.name ": Show", % "x" x_pos " y" y_pos " NoActivate AutoSize", % name " overlay"
        WinSet, TransColor, 0101FF, % "ahk_id " this.hwnd
        Gui, % this.name ": Hide"
        Gui, % this.name "_bg: Hide"
    }

    toggle_visibility(force:="none")
    {
        if ((this.showing && force == "none") || force == "hide")
        {
            this.showing := false
            Gui, % this.name ": Hide"
        }
        else if (force == "none" || force == "show")
        {
            this.showing := true
            Gui, % this.name ": Show", NA
        }
        return this.showing
    }

    toggle_timer(force:="none")
    {
        if (!this.has_timer && !this.has_countdown)
            return false

        timer_function := Func("timer_function").bind(this)

        if (this.timer_running && force == "pause")
        {
            SetTimer, % timer_function, Off
            this.timer_running := false
            this.paused := true
        }
        else if ((this.timer_running && (force == "none" || force == "stop")) || this.paused && force == "stop")
        {
            SetTimer, % timer_function, Off
            this.start_time := 0
            timer_function(this)
            this.update_content(this.content)
            this.timer_running := false
            this.paused := false
        }
        else if (force == "none" || force == "start")
        {
            SetTimer, % timer_function, 25
            this.start_time := A_TickCount
            this.timer_running := true
            this.paused := false
        }
        return
    }

    add_time(time_to_add, in_seconds:=true) ; only works while timer is running
    {
        if (!this.has_timer)
            return false

        if (this.has_timer)
        {
            if (in_seconds)
                this.start_time -= time_to_add * 1000
            else
                this.start_time -= time_to_add
        }
        return
    }

    update_content(new_content)
    {
        this.has_timer := false
        this.has_countdown := false
        temp_content := new_content

        ; Handle regular timer
        if (RegExMatch(new_content, "!timer(\d{5})", matchTimer))
        {
            this.timer_format := [SubStr(matchTimer1, 1, 1), SubStr(matchTimer1, 2, 1), SubStr(matchTimer1, 3, 1), SubStr(matchTimer1, 4, 1), SubStr(matchTimer1, 5, 1)]
            temp_content := RegExReplace(new_content, "!timer\d{5}", format_time(0, this.timer_format[1], this.timer_format[2], this.timer_format[3], this.timer_format[4], this.timer_format[5]))
            this.has_timer := true
        }

        ; Handle countdown timer
        else if (RegExMatch(new_content, "!countdown(\d+),(\d+),(\d+),(\d+)", matchCountdown))
        {
            this.countdown_time := (matchCountdown1 * 3600 + matchCountdown2 * 60 + matchCountdown3) * 1000 ; Convert to milliseconds
            show_hours := matchCountdown1 > 0
            show_minutes := matchCountdown2 > 0 || show_hours
            show_seconds := matchCountdown3 > 0 || show_minutes
            this.timer_format := [show_hours, show_minutes, show_seconds, true, matchCountdown4]
            temp_content := RegExReplace(new_content, "!countdown\d+,\d+,\d+,\d+", format_time(this.countdown_time, this.timer_format[1], this.timer_format[2], this.timer_format[3], this.timer_format[4], this.timer_format[5], "countdown"))
            this.has_countdown := true
        }

        this.content := new_content

        this.__update_background_position(temp_content)
        if (!this.timer_running)
            GuiControl % this.name ":", overlay_var, % temp_content
        Sleep, 0
        if (this.showing)
            Gui, % this.name ": Show", NA
        return
    }

    update_position(new_x_pos, new_y_pos)
    {
        this.x_pos := new_x_pos
        this.y_pos := new_y_pos

        temp_content := this.content

        if (RegExMatch(temp_content, "!timer(\d{5})", matchTimer))
            temp_content := RegExReplace(temp_content, "!timer\d{5}", format_time(0, this.timer_format[1], this.timer_format[2], this.timer_format[3], this.timer_format[4], this.timer_format[5]))

        else if (RegExMatch(temp_content, "!countdown(\d+),(\d+),(\d+),(\d+)", matchCountdown))
            temp_content := RegExReplace(temp_content, "!countdown\d+,\d+,\d+,\d+", format_time(this.countdown_time, this.timer_format[1], this.timer_format[2], this.timer_format[3], this.timer_format[4], this.timer_format[5], "countdown"))

        this.__update_background_position(temp_content)
        if (!this.showing)
        {
            Gui, % this.name ": Show", % "x" this.x_pos " y" this.y_pos " NoActivate HIDE"
            WinMove, % "ahk_id " this.hwnd ,, % this.x_pos, % this.y_pos
            Gui, % this.name ": Hide"
        }
        else
            WinMove, % "ahk_id " this.hwnd ,, % this.x_pos, % this.y_pos
        return
    }

    change_color(new_color)
    {
        this.text_color := new_color
        fonts := ["Arial", "Verdana", "Helvetica", "Courier New", "Small Fonts", "Impact"]
        Gui, % this.name ": Font", % "q3 s" this.font_size " c" new_color, % fonts[font_num]
        GuiControl % this.name ": Font", overlay_var
    }

    __create_background(background_color)
    {
        Gui, % this.name "_bg: +E0x20 -caption +AlwaysOnTop +ToolWindow +HwndbackgroundHwnd"
        this.background_hwnd := backgroundHwnd
        Gui, % this.name "_bg: Color", % background_color
        Gui, % this.name "_bg: Show", % "x" this.x_pos " y" this.y_pos " NA", % this.name " BG"
        this.background_transparency(100)
        this.toggle_background_visibility("hide")
        return
    }

    toggle_background_visibility(force:="none")
    {
        if ((this.background_showing && force == "none") || force == "hide")
        {
            this.background_showing := false
            Gui, % this.name "_bg: Hide"
        }
        else if ((force == "none" || force == "show") && this.has_background)
        {
            this.background_showing := true
            Gui, % this.name "_bg: Show", NA
            if (this.showing)
                Gui, % this.name ": Show", NA
        }
        return this.background_showing
    }

    change_background_color(new_color) 
    {
        Gui, % this.name "_bg: Color", % new_color
        return
    }

    background_transparency(percent)
    {
        percent := (percent < 0) ? 0 : (percent > 100) ? 100 : percent
        this.background_opacity := percent
        WinSet, Transparent, % Round(percent * 255 / 100), % "ahk_id " this.background_hwnd
        return
    }

    __update_background_position(content)
    {
        if (!this.has_background)
            return
        ; Use LOGFONT to calculate text dimensions
        fontMetric := New LOGFONT(this.controlHwnd)  ; Assuming 'hwnd' is the control handle of the text
        dimensions := fontMetric.GetDimensionsInPixels(content)
        ; Update background GUI size and position
        ; if ((this.has_timer || this.has_countdown) && this.font_num >= 5)
        ;     dimensions.w += this.font_size//5

        if (!this.background_showing)
        {
            WinSet, Transparent, 0, % "ahk_id " this.background_hwnd
            Gui, % this.name "_bg: Show", % "w" dimensions.w+(2*this.background_padding) " h" dimensions.h+(2*this.background_padding) " x" this.x_pos-this.background_padding " y" this.y_pos-this.background_padding  " NA"
            Winset, Region, % " 0-0 w" dimensions.w+(2*this.background_padding) " h" dimensions.h+(2*this.background_padding) " R" this.round_corners "-" this.round_corners , % "ahk_id " this.background_hwnd
            ; WinMove, % "ahk_id " this.background_hwnd,, % this.x_pos, % this.y_pos
            Gui, % this.name "_bg: Hide"
            WinSet, Transparent, %  Round(this.background_opacity * 255 / 100) , % "ahk_id " this.background_hwnd
        }
        else 
        {
            Gui, % this.name "_bg: Show", % "w" dimensions.w+(2*this.background_padding) " h" dimensions.h+(2*this.background_padding) " x" this.x_pos-this.background_padding " y" this.y_pos-this.background_padding  " NA"
            Winset, Region, % " 0-0 w" dimensions.w+(2*this.background_padding) " h" dimensions.h+(2*this.background_padding) " R" this.round_corners "-" this.round_corners , % "ahk_id " this.background_hwnd
        }
        if (this.showing)
            WinSet, Top, , % "ahk_id " this.hwnd

        this.dimensions := [dimensions.w+(2*this.background_padding), dimensions.h+(2*this.background_padding)]
        return
    }

    get_dimensions()
    {
        return this.dimensions
    }

    destroy_overlay()
    {
        Gui, % this.name ": Hide"
        Gui, % this.name ": Destroy"
        return
    }
}

timer_function(overlay)
{
    if (overlay.timer_running)
    {
        ; Check for regular timer
        if (overlay.has_timer)
        {
            new_time := format_time(overlay.start_time, overlay.timer_format[1], overlay.timer_format[2], overlay.timer_format[3], overlay.timer_format[4], overlay.timer_format[5])
            temp_content := RegExReplace(overlay.content, "!timer\d{5}", new_time)
        }
        ; Check for countdown timer
        else if (overlay.has_countdown)
        {
            remainingTime := overlay.start_time + overlay.countdown_time - A_TickCount
            if (remainingTime < 0)
            {
                overlay.timer_running := false
                new_time := format_time(overlay.countdown_time, overlay.timer_format[1], overlay.timer_format[2], overlay.timer_format[3], overlay.timer_format[4], overlay.timer_format[5], "countdown")
            }
            Else
            {
                new_time := format_time(remainingTime, overlay.timer_format[1], overlay.timer_format[2], overlay.timer_format[3], overlay.timer_format[4], overlay.timer_format[5], "countdown")
            }

            temp_content := RegExReplace(overlay.content, "!countdown\d+,\d+,\d+,\d+", new_time)

        }

        GuiControl, % overlay.name ":", overlay_var, % temp_content
    }
    return
}

format_time(start_time, show_hours, show_minutes, show_seconds, show_ms, round_ms, timer_type:="elapsed")
{
    currentTick := A_TickCount  ; Get current tick count
    elapsedMS := (timer_type = "elapsed") ? (currentTick - start_time) : start_time
    if (start_time == 0)
        elapsedMS := 0

    numSeconds := Floor(elapsedMS / 1000)
    numHours := Floor(numSeconds / 3600)
    numMinutes := Mod(Floor(numSeconds / 60), 60)
    numSeconds := Mod(numSeconds, 60)
    numMS := Mod(elapsedMS, 1000)  ; Representing milliseconds

    ; Determine the highest and lowest units to be shown
    highestUnit := show_hours ? 1 : (show_minutes ? 2 : (show_seconds ? 3 : 4))
    lowestUnit := show_ms ? 4 : (show_seconds ? 3 : (show_minutes ? 2 : 1))

    ; Adjust visibility flags based on the highest and lowest units
    show_hours := (highestUnit <= 1 && lowestUnit >= 1)
    show_minutes := (highestUnit <= 2 && lowestUnit >= 2)
    show_seconds := (highestUnit <= 3 && lowestUnit >= 3)
    show_ms := (highestUnit <= 4 && lowestUnit >= 4)

    formattedTime := ""
    
    if (show_hours) {
        formattedTime .= Format("{:02}", numHours)
        if (show_minutes || show_seconds || show_ms) 
            formattedTime .= ":"
    }
    
    if (show_minutes) {
        formattedTime .= Format("{:02}", numMinutes)
        if (show_seconds || show_ms) 
            formattedTime .= ":"
    }
    
    if (show_seconds) {
        formattedTime .= Format("{:02}", numSeconds)
        if (show_ms) 
            formattedTime .= "."
    }
    
    if (show_ms) 
        formattedTime .= SubStr(Format("{:03}", numMS), 1, round_ms)
    
    return formattedTime
}

; class LOGFONT by Capn Odin
Class LOGFONT{
	Static WM_GETFONT := 0x31, LONG := 4, BYTE := 1
	
	HFONT := 0, Hwnd
	
	Height := 0, Width := 0, Escapement := 0, Orientation := 0, Weight := 0
	
	Italic := 0, Underline := 0, StrikeOut := 0, CharSet := 0, OutPrecision := 0, ClipPrecision := 0, Quality := 0, PitchAndFamily := 0
	
	FaceName := ""
	
	__New(Hwnd){
		this.Hwnd := Hwnd
		this.UpdateFont()
	}
	
	UpdateFont(){
		this.HFONT := DllCall("SendMessage", "Ptr", this.Hwnd, "UInt", this.WM_GETFONT, "Ptr", 0, "Ptr", 0, "Ptr")
		amount := DllCall("GetObject", "Ptr", this.HFONT, "Int", 0, "Ptr", 0)
		VarSetCapacity(buff, amount)
		amount := DllCall("GetObject", "Ptr", this.HFONT, "Int", amount, "Ptr", &buff)
		this.GetData(buff, amount)
	}
	
	GetData(ByRef buff, amount){
		; Of Type LONG
		this.Height		:= NumGet(buff, this.LONG * 0, "Int") ; Verified I think
		this.Width		:= NumGet(buff, this.LONG * 1, "Int")
		this.Escapement := NumGet(buff, this.LONG * 2, "Int")
		this.Orientation:= NumGet(buff, this.LONG * 3, "Int")
		this.Weight		:= NumGet(buff, this.LONG * 4, "Int") ; Verified
		
		offset := this.LONG * 4
		
		; Of Type BYTE
		this.Italic			:= NumGet(buff, this.BYTE * 4 + offset, "UChar") ; Verified
		this.Underline		:= NumGet(buff, this.BYTE * 5 + offset, "UChar") ; Verified
		this.StrikeOut		:= NumGet(buff, this.BYTE * 6 + offset, "UChar") ; Verified
		this.CharSet		:= NumGet(buff, this.BYTE * 7 + offset, "UChar")
		this.OutPrecision	:= NumGet(buff, this.BYTE * 1 + offset, "UChar")
		this.ClipPrecision	:= NumGet(buff, this.BYTE * 2 + offset, "UChar")
		this.Quality		:= NumGet(buff, this.BYTE * 3 + offset, "UChar")
		this.PitchAndFamily := NumGet(buff, this.BYTE * 0 + offset, "UChar")
		
		offset += this.BYTE * 7 - 1
		
		this.FaceName := ""
		
		; Of Type Char Array
		While (offset < amount){
			this.FaceName .= Chr(NumGet(buff, offset += 1, "Char"))
		}
		
	}
	
	PixelWidth(str){
		return this.GetDimensionsInPixels(str)["w"]
	}
	
	PixelHeight(str){
		return this.GetDimensionsInPixels(str)["h"]
	}
	
	GetDimensionsInPixels(str){
		hDC := DllCall("GetDC", "Uint", this.Hwnd)
		hFold := DllCall("SelectObject", "Uint", hDC, "Uint", this.HFONT)
		DllCall("GetTextExtentPoint32", "Uint", hDC, "str", str, "int", StrLen(str), "int64P", nSize)
		
		DllCall("SelectObject", "Uint", hDC, "Uint", hFold)
		DllCall("ReleaseDC", "Uint", this.Hwnd, "Uint", hDC)
		
		nWidth  := nSize & 0xFFFFFFFF
		nHeight := nSize >> 32 & 0xFFFFFFFF
		
		Return {"w" : nWidth, "h" : nHeight}
	}
	
	Print(){
		LONG := "Height:`t`t" this.Height "`nWidth:`t`t" this.Width "`nEscapement:`t" this.Escapement "`nOrientation:`t" this.Orientation "`nWeight:`t`t" this.Weight
		
		BYTE := "Italic:`t`t" this.Italic "`nUnderline:`t`t" this.Underline "`nStrikeOut:`t`t" this.StrikeOut "`nCharSet:`t`t" this.CharSet "`nOutPrecision:`t" this.OutPrecision "`nClipPrecision:`t" this.ClipPrecision "`nQuality:`t`t" this.Quality "`nPitchAndFamily:`t" this.PitchAndFamily
		
		return "-" RegExReplace(this.FaceName, "[^a-zA-Z ]") "-`n" LONG "`n" BYTE
	}
	
}

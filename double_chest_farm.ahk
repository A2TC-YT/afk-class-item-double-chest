#Requires AutoHotkey >=1.1.36 <1.2
#SingleInstance, Force
#Include *i %A_ScriptDir%/overlay_class.ahk
#Include *i %A_ScriptDir%/Gdip_ALL.ahk
SendMode Input
CoordMode, Mouse, Screen
CoordMode, Pixel, Screen
SetWorkingDir, %A_ScriptDir%
SetBatchLines, -1
SetKeyDelay, -1
SetMouseDelay, -1
; Register message handlers
OnMessage(0x1003, "on_chest_open")
OnMessage(0x1004, "on_exotic_drop")
OnExit("on_script_exit")
global VERSION := "2.0.0"

; Startup Checks
; =================================== ;
    if InStr(A_ScriptDir, "AppData")
    {
        MsgBox, You must extract all files from the .zip folder you downloaded before running this script.
        Exitapp  
    }

	if (!FileExist( A_ScriptDir "/overlay_class.ahk" ) || !FileExist( A_ScriptDir "/Gdip_all.ahk" ))
    {
        MsgBox, Required files were not found in the same directory as this script. Place it in the same directory as overlay_class.ahk and Gdip_all.ahk.
        Exitapp  
    }

    WinGet, D2PID, PID, ahk_class Tiger D3D Window
    if(IsAdminProcess(D2PID)) {
        if not A_IsAdmin {
            Run *RunAs "%A_AhkPath%" "%A_ScriptFullPath%"
        }
    }
; =================================== ;

; Game Window Initialization
; =================================== ;
    ; will be coordinates of destinys client area (actual game window not including borders)
    global DESTINY_X := 0
    global DESTINY_Y := 0
    global DESTINY_WIDTH := 0
    global DESTINY_HEIGHT := 0
    global D2_WINDOW_HANDLE := -1

    find_d2()

    if (DESTINY_WIDTH > 1280 || DESTINY_HEIGHT > 720) ; make sure they are actually on windowed mode :D
    {
        MsgBox, % "This script is only designed to work with the game in windowed and a resolution of 1280x720. Your resolution is " DESTINY_WIDTH "x" DESTINY_HEIGHT "."
        ExitApp
    }
; =================================== ;

; (d)ynamic function to allow execution while zipped
global dGdip_Startup := "Gdip_Startup"
global dGdip_BitmapFromScreen := "Gdip_BitmapFromScreen"
global dGdip_GetPixel := "Gdip_GetPixel"
global dGdip_DisposeImage := "Gdip_DisposeImage"
global dGdip_SaveBitmapToFile := "Gdip_SaveBitmapToFile"

pToken := %dGdip_Startup%()

global DEBUG := false

global CHEST_PID, EXOTIC_PID

; Data Initialization
; =================================== ;
    global CURRENT_GUARDIAN := "Hunter"
    global TOTALS_DISPLAY := "All"
    global CLASSES := ["Hunter", "Titan", "Warlock"]
    global CHARACTER_SLOTS := ["Top", "Middle", "Bottom"]
    global AACHEN_CHOICES := ["Kinetic", "Void"]
    global CLASS_STAT_TYPES := ["current_runs", "total_runs", "current_exotics", "total_exotics", "current_time", "total_time"]
    global CHEST_STAT_TYPES := ["current_appearances", "total_appearances", "current_pickups", "total_pickups"]
    global CHEST_IDS := ["21", "20", "17", "19", "18", "16"]

    global PLAYER_DATA := {}

    for _, class_type in CLASSES {
        PLAYER_DATA[class_type] := {"Settings": {}, "ClassStats": {}, "ChestStats": {}}
    
        PLAYER_DATA[class_type]["Settings"]["Slot"] := "Top"
        PLAYER_DATA[class_type]["Settings"]["Aachen"] := "Kinetic"
    
        for _, class_stat_type in CLASS_STAT_TYPES {
            PLAYER_DATA[class_type]["ClassStats"][class_stat_type] := 0
        }
    
        for _, chest_id in CHEST_IDS {
            PLAYER_DATA[class_type]["ChestStats"][chest_id] := {}
            for _, chest_stat_type in CHEST_STAT_TYPES {
                PLAYER_DATA[class_type]["ChestStats"][chest_id][chest_stat_type] := 0
            }
        }
    }

    global CURRENT_LOOP_START_TIME := 0

    global CHEST_OPENED := false
    global EXOTIC_DROP := false
    
    global API_URL := "https://api.zenairo.com/d2/heartbeat"
    global HEARTBEAT_ON := false

    global RECORDED_RUNTIME := 0
    global RECORDED_LOOPS := 0
    global RECORDED_CHESTS := 0
    global RECORDED_EXOTICS := 0
    
    read_ini()
; =================================== ;

; Popup Dialog
; =================================== ;
    global INPUT_POPUP_HANDLED := false
    classDropdown := build_dropdown_string(CLASSES, CURRENT_GUARDIAN)
    slotDropdown := build_dropdown_string(CHARACTER_SLOTS, PLAYER_DATA[CURRENT_GUARDIAN]["Settings"]["Slot"])
    aachenDropdown := build_dropdown_string(AACHEN_CHOICES, PLAYER_DATA[CURRENT_GUARDIAN]["Settings"]["Aachen"])
    ; gui to get users character and character slot on character select screen
    Gui, user_input: New, , Select class and their slot on the character select screen
    Gui, user_input: -Caption -Border +hWnduser_input_hwnd +AlwaysOnTop
    Gui, user_input: Add, Text,, Select Class:
    Gui, user_input: Add, DropDownList, vClassChoice gClassChoiceChanged, % classDropdown
    Gui, user_input: Add, Text,, Select Slot:`n(on character select)
    Gui, user_input: Add, DropDownList, vSlotChoice, % slotDropdown
    Gui, user_input: Add, Text,, Which Aachen do you have:
    Gui, user_input: Add, DropDownList, vAachenChoice, % aachenDropdown
    Gui, user_input: Add, Text,, Totals:
    Gui, user_input: Add, Radio, x+10 vTotalModeAll gTotalModeChanged, All
    Gui, user_input: Add, Radio, x+10 vTotalModeClass gTotalModeChanged, Class
    GuiControl,, TotalModeAll, % (TOTALS_DISPLAY = "All") ? 1 : 0
    GuiControl,, TotalModeClass, % (TOTALS_DISPLAY = "Class") ? 1 : 0
    Gui, user_input: Add, Button, x10 y+10 guser_input_OK Default, OK
    Gui, user_input: Add, Checkbox, x+30 yp+5 vDebugChoice, Debug
    Gui, user_input: Show
; =================================== ;

; Stats GUI
; =================================== ;
    ; Offsets for Overlay class
    OVERLAY_OFFSET_X := DESTINY_X
    OVERLAY_OFFSET_Y := DESTINY_Y
    global GUI_VISIBLE := false

    ; background for all the stats
    Gui, info_BG: +E0x20 -Caption -Border +hWndExtraInfoBGGUI +ToolWindow
    Gui, info_BG: Color, 292929
    Gui, info_BG: Show, % "x" destiny_x-350 " y" destiny_y " w" 350 * dpiInverse " h" DESTINY_HEIGHT+1 " NA"
    Winset, Region, % "w500 h" DESTINY_HEIGHT+1 " 0-0 r15-15", ahk_id %ExtraInfoBGGUI%
    WinSet, Transparent, 255, ahk_id %ExtraInfoBGGUI%

    ; label text (wont change ever)
    label_version := new Overlay("label_version", "v" . VERSION, -340, 4, 4, 10, False, 0xFFFFFF)
    label_current := new Overlay("label_current", "Current Session Stats:", -340, 60, 1, 14, False, 0xFFFFFF)
    label_total := new Overlay("label_total", "Total AFK Stats (" . (TOTALS_DISPLAY = "All" ? "All" : CURRENT_GUARDIAN) . "):", -340, 425, 1, 14, False, 0xFFFFFF)
    label_start_hotkey := new Overlay("label_start_hotkey", "Start: F3", 10, DESTINY_HEIGHT+15, 1, 18, False, 0xFFFFFF, true, 0x292929, 15)
    label_stop_hotkey := new Overlay("label_stop_hotkey", "Reload: F4", 130, DESTINY_HEIGHT+15, 1, 18, False, 0xFFFFFF, true, 0x292929, 15)
    label_close_hotkey := new Overlay("label_close_hotkey", "Close: F5", 275, DESTINY_HEIGHT+15, 1, 18, False, 0xFFFFFF, true, 0x292929, 15)
    label_center_d2_hotkey := new Overlay("label_center_d2_hotkey", "Center D2: F6", 405, DESTINY_HEIGHT+15, 1, 18, False, 0xFFFFFF, true, 0x292929, 15)
    ; extra info gui stuff 
    global info_ui := new Overlay("info_ui", "Doing Nothing :3", -340, 28, 1, 18, False, 0xFFFFFF)
    global runs_till_orbit_ui := new Overlay("runs_till_orbit_ui", "Runs till next orbit - 0", -340, 120, 1, 16, False, 0xFFFFFF)

    global current_class := new Overlay("current_class", "Selected Class - " . CURRENT_GUARDIAN, -340, 90, 1, 14, False, 0xFFFFFF)
    global current_time_afk_ui := new Overlay("current_time_afk_ui", "Time AFK - !timer11101", -340, 150, 1, 16, False, 0xFFFFFF) 
    global current_runs_ui := new Overlay("current_runs_ui", "Runs - 0", -340, 180, 1, 16, False, 0xFFFFFF) 
    global current_chests_ui := new Overlay("current_chests_ui", "Chests - 0", -340, 210, 1, 16, False, 0xFFFFFF) 
    global current_exotics_ui := new Overlay("current_exotics_ui", "Exotics - 0", -340, 240, 1, 16, False, 0xFFFFFF) 
    global current_exotic_drop_rate_ui := new Overlay("current_exotic_drop_rate_ui", "Exotic Drop Rate - 0.00%", -340, 270, 1, 16, False, 0xFFFFFF) 
    global current_average_loop_time_ui := new Overlay("current_average_loop_time_ui", "Average Loop Time - 0:00.00", -340, 300, 1, 16, False, 0xFFFFFF) 
    global current_missed_chests_percent_ui := new Overlay("current_missed_chests_percent_ui", "Percent Chests Missed - 0.00%", -340, 330, 1, 16, False, 0xFFFFFF) 
    global current_chest_counters1 := new Overlay("current_chest_counters1", "21:[---/---]  20:[---/---]  17:[---/---]", -340, 360, 4, 10, False, 0xFFFFFF) 
    global current_chest_counters2 := new Overlay("current_chest_counters2", "19:[---/---]  18:[---/---]  16:[---/---]", -340, 380, 4, 10, False, 0xFFFFFF) 

    global total_time_afk_ui := new Overlay("total_time_afk_ui", "Time AFK - !timer11101", -340, 455, 1, 16, False, 0xFFFFFF) 
    global total_runs_ui := new Overlay("total_runs_ui", "Runs - 0", -340, 485, 1, 16, False, 0xFFFFFF) 
    global total_chests_ui := new Overlay("total_chests_ui", "Chests - 0", -340, 515, 1, 16, False, 0xFFFFFF) 
    global total_exotics_ui := new Overlay("total_exotics_ui", "Exotics - 0", -340, 545, 1, 16, False, 0xFFFFFF) 
    global total_exotic_drop_rate_ui := new Overlay("total_exotic_drop_rate_ui", "Exotic Drop Rate - 0.00%", -340, 575, 1, 16, False, 0xFFFFFF) 
    global total_average_loop_time_ui := new Overlay("total_average_loop_time_ui", "Average Loop Time - 0:00.00", -340, 605, 1, 16, False, 0xFFFFFF) 
    global total_missed_chests_percent_ui := new Overlay("total_missed_chests_percent_ui", "Percent Chests Missed - 0.00%", -340, 635, 1, 16, False, 0xFFFFFF) 
    global total_chest_counters1 := new Overlay("total_chest_counters1", "21:[---/---]  20:[---/---]  17:[---/---]", -340, 665, 4, 10, False, 0xFFFFFF) 
    global total_chest_counters2 := new Overlay("total_chest_counters2", "19:[---/---]  18:[---/---]  16:[---/---]", -340, 685, 4, 10, False, 0xFFFFFF) 

    global overlay_elements := [label_version, label_total, label_current, label_start_hotkey, label_stop_hotkey, label_close_hotkey, label_center_d2_hotkey, info_ui, runs_till_orbit_ui, current_class, current_time_afk_ui, current_runs_ui, current_chests_ui, current_exotics_ui, current_exotic_drop_rate_ui, current_average_loop_time_ui, current_missed_chests_percent_ui, current_chest_counters1, current_chest_counters2, total_time_afk_ui, total_runs_ui, total_chests_ui, total_exotics_ui, total_exotic_drop_rate_ui, total_average_loop_time_ui, total_missed_chests_percent_ui, total_chest_counters1, total_chest_counters2]

    toggle_gui("show")

    total_time_afk_ui.update_content("Time AFK - " format_timestamp(compute_total_stat("time"), true, true, true, false))
    update_ui()
; =================================== ;

; Keybind loading
; =================================== ; 
    keys_we_press := [
        ,"hold_zoom"
        ,"primary_weapon"
        ,"special_weapon"
        ,"heavy_weapon"
        ,"move_forward"
        ,"move_backward"
        ,"move_left"
        ,"move_right"
        ,"jump"
        ,"toggle_sprint"
        ,"interact"
        ,"ui_open_director" ; map
        ,"ui_open_start_menu_settings_tab"]

    global key_binds := get_d2_keybinds(keys_we_press) ; this gives us a dictionary of keybinds

    for key, value in key_binds ; make sure the keybinds are set (except for settings, dont technically need that one but having it bound speeds it up)
    {
        if (!value)
        {
            if (key != "ui_open_start_menu_settings_tab")
            {
                MsgBox, % "You need to set the keybind for " key " in the game settings."
                ExitApp
            }
        }
    }
; =================================== ;

WinActivate, Destiny 2

global STARTUP_SUCCESSFUL := true

Return

; Hotkeys
; =================================== ;

; hotkey to help make menuing while devving
; F2::get_mouse_pos_relative_to_d2()

F3:: ; main hotkey that runs the script
{
    if (!INPUT_POPUP_HANDLED)
        return

    ; Timers during the farm loop cause random interrupts during timing sensitive areas
    SetTimer, check_tabbed_out, Off 
    
    DetectHiddenWindows, On
    WinGet, MainPID, PID, %A_ScriptFullPath% - AutoHotkey v
    ; Start the child scripts
    ; MsgBox, %A_AhkPath%
    Run, %A_AhkPath% "monitor_loot.ahk" %MainPID% "chest", , , CHEST_PID
    Run, %A_AhkPath% "monitor_loot.ahk" %MainPID% "exotic", , , EXOTIC_PID
    
    HEARTBEAT_ON := true
    send_heartbeat()

    info_ui.update_content("Starting chest farm")
    WinActivate, ahk_exe destiny2.exe ; make sure destiny is active window
    set_fireteam_privacy("closed")
    Sleep, 1000
    change_character()
    Sleep, 500
    loop, ; loop until we actually load in lol
    {
        if (orbit_landing())
            break
        Sleep, 500
        change_character()
        Sleep, 500
    }
    loop_successful := false
    CURRENT_LOOP_START_TIME := A_TickCount
    current_time_afk_ui.toggle_timer("start")
    total_time_afk_ui.update_content("Time AFK - !timer11101") ; yippee there is a LOT of just ui stuff in here for updating the stats
    total_time_afk_ui.toggle_timer("start")
    total_time_afk_ui.add_time(compute_total_stat("time"), false)
    info_ui.update_content("Loading in")
    Sleep, 15000 
    loop, ; Orbit loop
    {
        remaining_chests := 40 ; use this to know how many loops to do before we reach overthrow level 2
        runs_till_orbit_ui.update_content("Runs till next orbit - " Ceil(remaining_chests/2))
        loop, ; Run landing loop (break out of this if overthrow L2)
        {
            if (loop_successful) ; Reset the time only if the loop made it to the end.
            {
                CURRENT_LOOP_START_TIME := A_TickCount
                loop_successful := false
            }
            if (!wait_for_spawn(45000)) ; if we dont spawn in, change character and try again
            {
                info_ui.update_content("Didn't detect spawn in :(")
                Sleep, 5000
                break
            }
            WinActivate, ahk_exe destiny2.exe ; really make sure we are tabbed in
            info_ui.update_content("Waiting for chest spawns")
            Sleep, 1000
            if (PLAYER_DATA[CURRENT_GUARDIAN]["Settings"]["Aachen"] == "Kinetic")
                Send, % "{" key_binds["primary_weapon"] "}" ; make sure aachen is equipped
            else 
                Send, % "{" key_binds["special_weapon"] "}"
            Sleep, 1000
            chest_spawns := force_first_chest() ; go to first corner and get chest spawns
            if (!chest_spawns[1]) ; if no first chest we relaunch
            {
                WinActivate, ahk_exe destiny2.exe ; triple check, just in case
                reload_landing()
                update_ui()
                continue
            }
            info_ui.update_content("Going to chests - " chest_spawns[1] " and " chest_spawns[2])
            log_chest("appearance", chest_spawns[1])
            group_5_chest_opened := group_5_chests() ; open chest 21 if its spawned
            if (group_5_chest_opened)
            {
                log_chest("pickup", chest_spawns[1])
                remaining_chests--
            }
            update_chest_ui()

            if (chest_spawns[2]) ; open the second chest (one from group 4)
            {
                log_chest("appearance", chest_spawns[2])
                group_4_chest_opened := group_4_chests(chest_spawns[2])
                if (group_4_chest_opened)
                {
                    log_chest("pickup", chest_spawns[2])
                    remaining_chests--
                }
                update_chest_ui()
            }
            WinActivate, ahk_exe destiny2.exe ; make absolutely, positively, certain we are tabbed in
            ; (not remaining=0 means OT L2 not reached. .. or .. not (remaining=40 and index>=20) means chest tracking broken but OT L2 not reached)
            ; both conditions mean we do not have to orbit. simply reload.
            if (!(remaining_chests <= 0 || (remaining_chests == 40 && A_Index >= 20)))
            {
                info_ui.update_content("Relaunching Landing")
                reload_landing()
            }
            
            StopMonitoring(EXOTIC_PID)
            if (EXOTIC_DROP)
                PLAYER_DATA[CURRENT_GUARDIAN]["ClassStats"]["current_exotics"]++
            EXOTIC_DROP := false
            
            ; Run completion
            loop_successful := true
            PLAYER_DATA[CURRENT_GUARDIAN]["ClassStats"]["current_runs"]++
            PLAYER_DATA[CURRENT_GUARDIAN]["ClassStats"]["current_time"] += A_TickCount - CURRENT_LOOP_START_TIME

            ; UI updates
            runs_till_orbit_ui.update_content("Runs till next orbit - " Ceil(remaining_chests/2))
            update_ui()

            ; send_heartbeat()
            
            ; Break out to orbit if Overthrow L2
            if (remaining_chests <= 0 || (remaining_chests == 40 && A_Index >= 20))
                break
        }
        info_ui.update_content("Orbit and relaunch") ; opened 40 chests, time to orbit and relaunch
        WinActivate, ahk_exe destiny2.exe ; one more for good measure
        change_character()
        Sleep, 500
        loop, ; same thing as start, go until we actually start loading in
        {
            if (orbit_landing())
                break
            Sleep, 500
            change_character()
            Sleep, 500
        }
        Sleep, 30000
        
        ; Keep the user's heartbeat alive as orbit_landing takes more time than a normal loop.
        send_heartbeat()
    }
    Return
}

F4:: ; reload the script, release any possible held keys, save stats
{
    Reload
    Return
}

F5:: ; same thing but close the script
{
    ExitApp
}

F6::
{
    WinGetPos,,, Width, Height, ahk_exe destiny2.exe
    WinMove, ahk_exe destiny2.exe,, (A_ScreenWidth/2)-((Width-(350 * dpiInverse))/2), (A_ScreenHeight/2)-(Height/2)
    Sleep 1000
    ; we also want it to reload script so gui is in the right spot
    Reload
    Return
}

; F7:: ; testing hotkey
; {
;     GoSub, check_for_exotic_drop
;     return
; }
; =================================== ;

; Chest Functions
; =================================== ;
force_first_chest() ; walk to the corner to guarantee chest 21 spawns, also calls find_chests to, yknow, find teh chests :P
{   
    WinActivate, ahk_exe destiny2.exe
    Sleep, 20
    DllCall("mouse_event", uint, 1, int, 9091, int, 0) ; do 2 360s because yeah
    Sleep, 10
    DllCall("mouse_event", uint, 1, int, -9091, int, 0)
    Sleep, 10
    Send, % "{" key_binds["hold_zoom"] " Down}"
    Sleep, 50
    Send, % "{" key_binds["hold_zoom"] " Up}"
    Sleep, 140
    DllCall("mouse_event", uint, 1, int, -840, int, 0)
    Send, % "{" key_binds["move_forward"] " Down}"
    Send, % "{" key_binds["toggle_sprint"] " Down}"
    Sleep, 8000
    Send, % "{" key_binds["toggle_sprint"] " Up}"
    Send, % "{" key_binds["move_forward"] " Up}"
    Sleep, 1000
    DllCall("mouse_event", uint, 1, int, 2840, int, 0)
    Send, % "{" key_binds["move_forward"] " Down}"
    Sleep, 3000
    Send, % "{" key_binds["move_forward"] " Up}"
    Sleep, 11000
    return find_chests()
}

find_chests() ; figures out which chest in group 4 is spawned and also waits for chest 21 to spawn
{
    ; group 5 is chests 21,22, 23, 24, 25
    ; group 4 is chests 16, 17, 18, 19, 20
    ; group 3 is chests 11, 12, 13, 14, 15 (probably wont be used)
    ; group 2 is chests 6, 7, 8, 9, 10 (probably wont be used)
    ; group 1 is chests 1, 2, 3, 4, 5 (probably wont be used)

    forced_chest_x := 1755
    forced_chest_y := -50

    ; 16, 17, 18, 19, 20
    group_4_x_coords := [-4585, -275, -1963, -3436, 3470]
    group_4_y_coords := [-102, -1033, -55, -710, -1038]

    ; 11, 12, 13, 14, 15 (these are outdated, would need ot be updated to use anyways lol)
    group_3_x_coords := [-12220, -6810, -12430, -19130, -19580]
    group_3_y_coords := [-290, -300, 920, 680, 990]

    all_chests_found := false
    ; group 5, 4, 3 (not doing third chest group for now)
    chest_spots := [0, 0]

    Send, % "{" key_binds["hold_zoom"] " Down}"
    Sleep, 700

    look_delay := 100
    started_looking := A_TickCount

    while (not all_chests_found) ; basically just loop until chests are all found (group 4 chest and also chest 21)
    {
        for index, chest in chest_spots ; make it so we dont have to check groups that already have foud chests
        {
            if (chest) 
                continue
            if (index == 1)
            {
                DllCall("mouse_event",uint,1,int,forced_chest_x,int,forced_chest_y)
                Sleep, % look_delay
                if (simpleColorCheck("629|365|23|19", 23, 19) > 0.15) ; this looks where the chest icon would appear if it spawns and checks for white pixels, it can sometimes mess up if some very specific things spawn in
                    chest_spots[index] := 21
                Sleep, % look_delay
                DllCall("mouse_event",uint,1,int,-forced_chest_x,int,-forced_chest_y)
            }
            else if (index == 2)
            {
                loop, 5
                {
                    DllCall("mouse_event",uint,1,int,group_4_x_coords[A_Index],int,group_4_y_coords[A_Index])
                    Sleep, % look_delay
                    if (simpleColorCheck("629|365|23|19", 23, 19) > 0.15)
                    {
                        chest_spots[index] := 15 + A_Index
                        Sleep, % look_delay
                        DllCall("mouse_event",uint,1,int,-group_4_x_coords[A_Index],int,-group_4_y_coords[A_Index])
                        break
                    }
                    Sleep, % look_delay
                    DllCall("mouse_event",uint,1,int,-group_4_x_coords[A_Index],int,-group_4_y_coords[A_Index])
                }
            }
            else if (index == 3) ; this checks for which group 3 chest spawns :D (we dont use it right now (or probably ever))
            {
                loop, 5
                {
                    DllCall("mouse_event",uint,1,int,group_3_x_coords[A_Index],int,group_3_y_coords[A_Index])
                    Sleep, % look_delay
                    if (simpleColorCheck("629|365|23|19", 23, 19) > 0.15)
                    {
                        chest_spots[index] := 10 + A_Index
                        Sleep, % look_delay
                        DllCall("mouse_event",uint,1,int,-group_3_x_coords[A_Index],int,-group_3_y_coords[A_Index])
                        break
                    }
                    Sleep, % look_delay
                    DllCall("mouse_event",uint,1,int,-group_3_x_coords[A_Index],int,-group_3_y_coords[A_Index])
                }
            }
        if (chest_spots[1] && chest_spots[2])
            all_chests_found := true
        }
        if (A_TickCount - started_looking > 20000) ; stop looking focefully after 20 seconds of looking
            break
    }
    Sleep, 100
    Send, % "{" key_binds["hold_zoom"] " Up}"
    Sleep, 700
    return chest_spots
}

group_5_chests(chest_number:=21) ; picks up chest 21
{
    group_5_chest_opened := false
    CHEST_OPENED := false
    ; we can force only chest 21 to spawn every time, so we will do that
    Send, % "{" key_binds["move_backward"] " Down}"
    PreciseSleep(200)
    Send, % "{" key_binds["move_backward"] " Up}"
    PreciseSleep(100)
    Send, % "{" key_binds["move_right"] " Down}"
    PreciseSleep(235)
    Send, % "{" key_binds["move_right"] " Up}"
    PreciseSleep(300)
    DllCall("mouse_event", uint, 1, int, 530, int, 0)
    Send, % "{" key_binds["move_forward"] " Down}"
    Send, % "{" key_binds["toggle_sprint"] " Down}"
    PreciseSleep(6400)
    DllCall("mouse_event", uint, 1, int, -980, int, 0)
    PreciseSleep(3300)
    Send, % "{" key_binds["toggle_sprint"] " Up}"
    Send, % "{" key_binds["move_forward"] " Up}"
    PreciseSleep(200)
    Send, % "{" key_binds["move_left"] " Down}"
    Send, % "{" key_binds["move_backward"] " Down}"
    PreciseSleep(1000)
    Send, % "{" key_binds["move_backward"] " Up}"
    Send, % "{" key_binds["move_left"] " Up}"
    DllCall("mouse_event", uint, 1, int, 4200, int, 400)
    StartMonitoring(CHEST_PID)
    StartMonitoring(EXOTIC_PID)
    Send, % "{" key_binds["interact"] " Down}"
    PreciseSleep(1100)
    Send, % "{" key_binds["interact"] " Up}"
    if (CHEST_OPENED)
        group_5_chest_opened := true
    else 
        StopMonitoring(CHEST_PID)
    CHEST_OPENED := false
    DllCall("mouse_event", uint, 1, int, -4400, int, -500)
    return group_5_chest_opened
}

group_4_chests(chest_number) ; picks up chests 16-20 
{
    group_4_chest_opened := false
    if (!chest_number)
        return group_4_chest_opened
    Send, % "{" key_binds["move_right"] " Down}"
    PreciseSleep(400)
    Send, % "{" key_binds["move_right"] " Up}"
    PreciseSleep(100)
    DllCall("mouse_event", uint, 1, int, 350, int, 0)
    PreciseSleep(100)
    Send, % "{" key_binds["move_forward"] " Down}"
    Send, % "{" key_binds["toggle_sprint"] " Down}"
    PreciseSleep(2400)
    Send, % "{" key_binds["toggle_sprint"] " Up}"
    Send, % "{" key_binds["move_forward"] " Up}"
    PreciseSleep(200)

    ; Stop exotic tracking and record the previous.
    StopMonitoring(EXOTIC_PID)
    if (EXOTIC_DROP)
        PLAYER_DATA[CURRENT_GUARDIAN]["ClassStats"]["current_exotics"]++
    EXOTIC_DROP := false

    if (chest_number == 20)
    {
        if (CURRENT_GUARDIAN == "Hunter")
        {
            DllCall("mouse_event", uint, 1, int, 2535, int, 400)
            Send, % "{" key_binds["jump"] " Down}"
            PreciseSleep(400)
            Send, % "{" key_binds["jump"] " Up}"
            PreciseSleep(100)
            Send, % "{" key_binds["jump"] " Down}"
            PreciseSleep(500)
            Send, % "{" key_binds["move_forward"] " Down}"
            PreciseSleep(100)
            Send, % "{" key_binds["jump"] " Up}"
            PreciseSleep(100)
            Send, % "{" key_binds["jump"] " Down}"
            PreciseSleep(600)
            Send, % "{" key_binds["jump"] " Up}"
            PreciseSleep(100)
            Send, % "{" key_binds["toggle_sprint"] " Down}"
            StartMonitoring(CHEST_PID)
            StartMonitoring(EXOTIC_PID)
            Send, % "{" key_binds["interact"] " Down}"
            Send, % "{" key_binds["heavy_weapon"] "}"
            PreciseSleep(2210)
            Send, % "{" key_binds["toggle_sprint"] " Up}"
            Send, % "{" key_binds["move_forward"] " Up}"
            DllCall("mouse_event", uint, 1, int, 130, int, 500)
            PreciseSleep(1300)
            Send, % "{" key_binds["interact"] " Up}"
        }
        else if (CURRENT_GUARDIAN == "Warlock")
        {
            DllCall("mouse_event", uint, 1, int, 2535, int, 400)
            Send, % "{" key_binds["jump"] "}"
            PreciseSleep(100)
            Send, % "{" key_binds["jump"] "}"
            PreciseSleep(500)
            Send, % "{" key_binds["move_forward"] " Down}"
            PreciseSleep(1200)
            Send, % "{" key_binds["jump"] "}"
            PreciseSleep(100)
            Send, % "{" key_binds["toggle_sprint"] " Down}"
            StartMonitoring(CHEST_PID)
            StartMonitoring(EXOTIC_PID)
            Send, % "{" key_binds["interact"] " Down}"
            Send, % "{" key_binds["heavy_weapon"] "}"
            PreciseSleep(2400)
            Send, % "{" key_binds["toggle_sprint"] " Up}"
            Send, % "{" key_binds["move_forward"] " Up}"
            DllCall("mouse_event", uint, 1, int, 130, int, 450)
            PreciseSleep(1300)
            Send, % "{" key_binds["interact"] " Up}"
        }
        else 
        {
            DllCall("mouse_event", uint, 1, int, 2535, int, 400)
            Send, % "{" key_binds["jump"] " Down}"
            PreciseSleep(400)
            Send, % "{" key_binds["jump"] "}"
            PreciseSleep(100)
            Send, % "{" key_binds["jump"] "}"
            PreciseSleep(500)
            Send, % "{" key_binds["move_forward"] " Down}"
            PreciseSleep(800)
            Send, % "{" key_binds["jump"] "}"
            PreciseSleep(100)
            Send, % "{" key_binds["toggle_sprint"] " Down}"
            StartMonitoring(CHEST_PID)
            StartMonitoring(EXOTIC_PID)
            Send, % "{" key_binds["interact"] " Down}"
            Send, % "{" key_binds["heavy_weapon"] "}"
            PreciseSleep(2350)
            Send, % "{" key_binds["toggle_sprint"] " Up}"
            Send, % "{" key_binds["move_forward"] " Up}"
            DllCall("mouse_event", uint, 1, int, 130, int, 450)
            PreciseSleep(1300)
            Send, % "{" key_binds["interact"] " Up}"
        }
    }
    else if (chest_number == 17)
    {
        if (CURRENT_GUARDIAN == "Hunter")
        {
            DllCall("mouse_event", uint, 1, int, -3350, int, 400)
            Send, % "{" key_binds["move_forward"] " Down}"
            Send, % "{" key_binds["jump"] " Down}"
            PreciseSleep(600)
            Send, % "{" key_binds["jump"] " Up}"
            PreciseSleep(100)
            Send, % "{" key_binds["jump"] " Down}"
            PreciseSleep(600)
            Send, % "{" key_binds["jump"] " Up}"
            PreciseSleep(100)
            Send, % "{" key_binds["jump"] " Down}"
            PreciseSleep(600)
            Send, % "{" key_binds["jump"] " Up}"
            PreciseSleep(100)
            Send, % "{" key_binds["toggle_sprint"] " Down}"
            DllCall("mouse_event", uint, 1, int, -380, int, 400)
            Send, % "{" key_binds["heavy_weapon"] "}"
            PreciseSleep(1250)
            Send, % "{" key_binds["toggle_sprint"] " Up}"
            StartMonitoring(CHEST_PID)
            StartMonitoring(EXOTIC_PID)
            Send, % "{" key_binds["interact"] " Down}"
            Send, % "{" key_binds["move_forward"] " Up}"
            PreciseSleep(1300)
            Send, % "{" key_binds["interact"] " Up}"
        }
        else if (CURRENT_GUARDIAN == "Warlock")
        {
            DllCall("mouse_event", uint, 1, int, -3350, int, 400)
            Send, % "{" key_binds["move_forward"] " Down}"
            Send, % "{" key_binds["jump"] "}"
            PreciseSleep(100)
            Send, % "{" key_binds["jump"] "}"
            PreciseSleep(1300)
            Send, % "{" key_binds["jump"] "}"
            PreciseSleep(700)
            Send, % "{" key_binds["toggle_sprint"] " Down}"
            DllCall("mouse_event", uint, 1, int, -400, int, 400)
            Send, % "{" key_binds["heavy_weapon"] "}"
            PreciseSleep(900)
            Send, % "{" key_binds["toggle_sprint"] " Up}"
            StartMonitoring(CHEST_PID)
            StartMonitoring(EXOTIC_PID)
            Send, % "{" key_binds["interact"] " Down}"
            Send, % "{" key_binds["move_forward"] " Up}"
            PreciseSleep(1300)
            Send, % "{" key_binds["interact"] " Up}"
        }
        else
        {
            DllCall("mouse_event", uint, 1, int, -3350, int, 400)
            Send, % "{" key_binds["move_forward"] " Down}"
            Send, % "{" key_binds["jump"] "}"
            PreciseSleep(100)
            Send, % "{" key_binds["jump"] "}"
            PreciseSleep(1300)
            Send, % "{" key_binds["jump"] "}"
            PreciseSleep(700)
            Send, % "{" key_binds["toggle_sprint"] " Down}"
            DllCall("mouse_event", uint, 1, int, -400, int, 400)
            Send, % "{" key_binds["heavy_weapon"] "}"
            PreciseSleep(1055)
            Send, % "{" key_binds["toggle_sprint"] " Up}"
            StartMonitoring(CHEST_PID)
            StartMonitoring(EXOTIC_PID)
            Send, % "{" key_binds["interact"] " Down}"
            Send, % "{" key_binds["move_forward"] " Up}"
            PreciseSleep(1300)
            Send, % "{" key_binds["interact"] " Up}"
        }
    }
    else if (chest_number == 19)
    {
        if (CURRENT_GUARDIAN == "Hunter")
        {
            DllCall("mouse_event", uint, 1, int, -1410, int, 400)
            Send, % "{" key_binds["move_forward"] " Down}"
            Send, % "{" key_binds["toggle_sprint"] " Down}"
            PreciseSleep(1800)
            Send, % "{" key_binds["jump"] " Down}"
            Send, % "{" key_binds["toggle_sprint"] " Up}"
            PreciseSleep(600)
            Send, % "{" key_binds["jump"] " Up}"
            PreciseSleep(100)
            Send, % "{" key_binds["jump"] " Down}"
            PreciseSleep(600)
            Send, % "{" key_binds["jump"] " Up}"
            PreciseSleep(100)
            Send, % "{" key_binds["jump"] " Down}"
            PreciseSleep(600)
            Send, % "{" key_binds["jump"] " Up}"
            StartMonitoring(CHEST_PID)
            StartMonitoring(EXOTIC_PID)
            Send, % "{" key_binds["interact"] " Down}"
            DllCall("mouse_event", uint, 1, int, -80, int, 250)
            Send, % "{" key_binds["heavy_weapon"] "}"
            PreciseSleep(2230)
            DllCall("mouse_event", uint, 1, int, 130, int, 250)
            Send, % "{" key_binds["move_forward"] " Up}"
            PreciseSleep(1300)
            Send, % "{" key_binds["interact"] " Up}"
        }
        else if (CURRENT_GUARDIAN == "Warlock")
        {
            DllCall("mouse_event", uint, 1, int, -1410, int, 400)
            Send, % "{" key_binds["move_forward"] " Down}"
            Send, % "{" key_binds["toggle_sprint"] " Down}"
            PreciseSleep(1800)
            Send, % "{" key_binds["jump"] "}"
            Send, % "{" key_binds["toggle_sprint"] " Up}"
            PreciseSleep(180)
            Send, % "{" key_binds["jump"] "}"
            PreciseSleep(1600)
            Send, % "{" key_binds["jump"] "}"
            StartMonitoring(CHEST_PID)
            StartMonitoring(EXOTIC_PID)
            Send, % "{" key_binds["interact"] " Down}"
            DllCall("mouse_event", uint, 1, int, -80, int, 250)
            Send, % "{" key_binds["heavy_weapon"] "}"
            PreciseSleep(2350)
            DllCall("mouse_event", uint, 1, int, 130, int, 250)
            Send, % "{" key_binds["move_forward"] " Up}"
            PreciseSleep(1300)
            Send, % "{" key_binds["interact"] " Up}"
        }
        else 
        {
            DllCall("mouse_event", uint, 1, int, -1410, int, 400)
            Send, % "{" key_binds["move_forward"] " Down}"
            Send, % "{" key_binds["toggle_sprint"] " Down}"
            PreciseSleep(1900)
            Send, % "{" key_binds["jump"] "}"
            Send, % "{" key_binds["toggle_sprint"] " Up}"
            PreciseSleep(200)
            Send, % "{" key_binds["jump"] "}"
            PreciseSleep(1600)
            Send, % "{" key_binds["jump"] "}"
            StartMonitoring(CHEST_PID)
            StartMonitoring(EXOTIC_PID)
            Send, % "{" key_binds["interact"] " Down}"
            DllCall("mouse_event", uint, 1, int, -80, int, 250)
            Send, % "{" key_binds["heavy_weapon"] "}"
            PreciseSleep(2350)
            DllCall("mouse_event", uint, 1, int, 130, int, 250)
            Send, % "{" key_binds["move_forward"] " Up}"
            PreciseSleep(1300)
            Send, % "{" key_binds["interact"] " Up}"
        }
    }
    else if (chest_number == 18)
    {
        DllCall("mouse_event", uint, 1, int, -1310, int, 400)
        Send, % "{" key_binds["move_forward"] " Down}"
        Send, % "{" key_binds["toggle_sprint"] " Down}"
        PreciseSleep(3500)
        Send, % "{" key_binds["toggle_sprint"] " Up}"
        DllCall("mouse_event", uint, 1, int, 1200, int, 450)
        PreciseSleep(2800)
        Send, % "{" key_binds["interact"] " Down}"
        StartMonitoring(CHEST_PID)
        StartMonitoring(EXOTIC_PID)
        Send, % "{" key_binds["heavy_weapon"] "}"
        PreciseSleep(2420)
        Send, % "{" key_binds["move_forward"] " Up}"
        PreciseSleep(1300)
        Send, % "{" key_binds["interact"] " Up}"
    }
    else if (chest_number == 16)
    {
        DllCall("mouse_event", uint, 1, int, -1310, int, 400)
        Send, % "{" key_binds["move_forward"] " Down}"
        Send, % "{" key_binds["toggle_sprint"] " Down}"
        PreciseSleep(3500)
        Send, % "{" key_binds["toggle_sprint"] " Up}"
        DllCall("mouse_event", uint, 1, int, 1200, int, 300)
        PreciseSleep(2100)
        DllCall("mouse_event", uint, 1, int, -1570, int, 0)
        PreciseSleep(4200)
        Send, % "{" key_binds["interact"] " Down}"
        StartMonitoring(CHEST_PID)
        StartMonitoring(EXOTIC_PID)
        DllCall("mouse_event", uint, 1, int, 610, int, 50)
        Send, % "{" key_binds["heavy_weapon"] "}"
        PreciseSleep(1450)
        Send, % "{" key_binds["move_forward"] " Up}"
        DllCall("mouse_event", uint, 1, int, -100, int, 50)
        PreciseSleep(1300)
        Send, % "{" key_binds["interact"] " Up}"
    }
    if (CHEST_OPENED)
        group_4_chest_opened := true
    else 
        StopMonitoring(CHEST_PID)
    CHEST_OPENED := false
    return group_4_chest_opened
}

StartMonitoring(target_pid) {
    PostMessage, 0x1001, 0, 0, , % "ahk_pid " target_pid
}

StopMonitoring(target_pid) {
    PostMessage, 0x1002, 0, 0, , % "ahk_pid " target_pid
}

on_chest_open(wParam, lParam, msg, hwnd) {
    CHEST_OPENED := true
}

on_exotic_drop(wParam, lParam, msg, hwnd) {
    EXOTIC_DROP := true
}

log_chest(data, chest_id)
{
    ; Log the chest to both current and total. Creates duplicate count info after stat refactoring.
    ; for _, chest_stat_type in CHEST_STAT_TYPES {
    ;     if (InStr(chest_stat_type, data))
    ;     {
    ;         PLAYER_DATA[CURRENT_GUARDIAN]["ChestStats"][chest_id][chest_stat_type]++
    ;     }
    ; }
    ; Log the chest only to current. Adds need to commit numbers on exit. Added after stat refactor.
    PLAYER_DATA[CURRENT_GUARDIAN]["ChestStats"][chest_id]["current_" data "s"]++
}

current_chest(stat)
{
    sum := 0
    for _, chest_id in CHEST_IDS {
        sum += PLAYER_DATA[CURRENT_GUARDIAN]["ChestStats"][chest_id]["current_" . stat]
    }
    return sum
}

total_chest(stat)
{
    sum := 0
    if (TOTALS_DISPLAY = "All")
    {
        for _, class_type in CLASSES {
            for _, chest_id in CHEST_IDS {
                sum += PLAYER_DATA[class_type]["ChestStats"][chest_id]["current_" . stat]
                sum += PLAYER_DATA[class_type]["ChestStats"][chest_id]["total_" . stat]
            }
        }
    }
    Else
    {
        for _, chest_id in CHEST_IDS {
            sum += PLAYER_DATA[CURRENT_GUARDIAN]["ChestStats"][chest_id]["current_" . stat]
            sum += PLAYER_DATA[CURRENT_GUARDIAN]["ChestStats"][chest_id]["total_" . stat]
        }
    }
    return sum
}

current_counter(id)
{
    return chest_counter(id, PLAYER_DATA[CURRENT_GUARDIAN]["ChestStats"][id]["current_appearances"], PLAYER_DATA[CURRENT_GUARDIAN]["ChestStats"][id]["current_pickups"])
}

total_counter(id)
{
    appearances := 0
    pickups := 0
    if (TOTALS_DISPLAY = "All")
    {
        for _, class_type in CLASSES {
            appearances += PLAYER_DATA[class_type]["ChestStats"][id]["current_appearances"]
            appearances += PLAYER_DATA[class_type]["ChestStats"][id]["total_appearances"]
            pickups += PLAYER_DATA[class_type]["ChestStats"][id]["current_pickups"]
            pickups += PLAYER_DATA[class_type]["ChestStats"][id]["total_pickups"]
        }
    }
    Else
    {
        appearances += PLAYER_DATA[CURRENT_GUARDIAN]["ChestStats"][id]["current_appearances"]
        appearances += PLAYER_DATA[CURRENT_GUARDIAN]["ChestStats"][id]["total_appearances"]
        pickups += PLAYER_DATA[CURRENT_GUARDIAN]["ChestStats"][id]["current_pickups"]
        pickups += PLAYER_DATA[CURRENT_GUARDIAN]["ChestStats"][id]["total_pickups"]
    }
    return chest_counter(id, appearances, pickups)
}

chest_counter(id, appearances, pickups)
{
    return id ":" Format("[{:3}/{:3}]", pickups, appearances)
}

compute_total_stat(stat)
{
    total_runs := 0
    if (TOTALS_DISPLAY = "All")
    {
        for _, class_type in CLASSES {
            total_runs += PLAYER_DATA[class_type]["ClassStats"]["total_" . stat]
            total_runs += PLAYER_DATA[class_type]["ClassStats"]["current_" . stat]
        }
    }
    else
    {
        total_runs := PLAYER_DATA[CURRENT_GUARDIAN]["ClassStats"]["total_" . stat] + PLAYER_DATA[CURRENT_GUARDIAN]["ClassStats"]["current_" . stat]
    }
    return total_runs        
}

update_ui() ; Fully update UI, optimized to only compute values once.
{
    ; Compute these once.
    c_current_pickups := current_chest("pickups")
    c_current_appearances := current_chest("appearances")
    ; Current
    ; Time AFK
    ; -Handled by timer.
    ; Runs
    current_runs_ui.update_content("Runs - " PLAYER_DATA[CURRENT_GUARDIAN]["ClassStats"]["current_runs"])
    ; Chests
    ; -update_chest_ui()
    ; Exotics
    current_exotics_ui.update_content("Exotics - " PLAYER_DATA[CURRENT_GUARDIAN]["ClassStats"]["current_exotics"])
    ; Exotic Drop Rate
    current_exotic_drop_rate_ui.update_content("Exotic Drop Rate - " Round(PLAYER_DATA[CURRENT_GUARDIAN]["ClassStats"]["current_exotics"]/c_current_pickups*100,2) "%")
    ; Average Loop Time
    current_average_loop_time_ui.update_content("Average Loop Time - " format_timestamp(PLAYER_DATA[CURRENT_GUARDIAN]["ClassStats"]["current_time"]/PLAYER_DATA[CURRENT_GUARDIAN]["ClassStats"]["current_runs"], false, true, true, true, 2))
    ; Percent Chests Missed
    current_missed_chests_percent_ui.update_content("Percent Chests Missed - " Round(100 - (c_current_pickups/c_current_appearances)*100, 2) "%")
    ; Per chest stats
    ; -update_chest_ui()

    ; Compute these once.
    c_total_runs := compute_total_stat("runs")
    c_total_exotics := compute_total_stat("exotics")
    c_total_time := compute_total_stat("time")
    c_total_pickups := total_chest("pickups")
    c_total_appearances := total_chest("appearances")
    ; Total
    ; Time AFK
    ; -Handled by timer.
    ; Runs
    total_runs_ui.update_content("Runs - " c_total_runs)
    ; Chests
    ; -update_chest_ui()
    ; Exotics
    total_exotics_ui.update_content("Exotics - " c_total_exotics)
    ; Exotic Drop Rate
    total_exotic_drop_rate_ui.update_content("Exotic Drop Rate - " Round(c_total_exotics/c_total_pickups*100,2) "%")
    ; Average Loop Time
    total_average_loop_time_ui.update_content("Average Loop Time - " format_timestamp(c_total_time/c_total_runs, false, true, true, true, 2))
    ; Percent Chests Missed
    total_missed_chests_percent_ui.update_content("Percent Chests Missed - " Round(100 - (c_total_pickups/c_total_appearances)*100, 2) "%")
    ; Per chest stats
    ; -update_chest_ui()

    update_chest_ui(c_current_pickups, c_total_pickups)
}

update_chest_ui(current_chests := -1, total_chests := -1)
{
    current_chests_ui.update_content("Chests - "  . (current_chests = -1 ? current_chest("pickups") : current_chests))
    total_chests_ui.update_content("Chests - "  . (total_chests = -1 ? total_chest("pickups") : total_chests))

    current_chest_counters1.update_content(current_counter(21) "  " current_counter(20) "  " current_counter(17))
    current_chest_counters2.update_content(current_counter(19) "  " current_counter(18) "  " current_counter(16))
    total_chest_counters1.update_content(total_counter(21) "  " total_counter(20) "  " total_counter(17))
    total_chest_counters2.update_content(total_counter(19) "  " total_counter(18) "  " total_counter(16))
}

; Load Zone Functions
; =================================== ;
reload_landing() ; in the name innit
{
    loop, 5
    {   
        Send, % "{" key_binds["ui_open_director"] "}"
        Sleep, 1400
        d2_click(20, 381, 0) ; mouse to drag map and show landing icon
        PreciseSleep(850)
        d2_click(270, 338, 0) ; mouse stop drag and hover landing
        Sleep, 100
        Click, Up
        Sleep, 100
        Click, % DESTINY_X + 270 " " DESTINY_Y + 338 " "
        Click, Down
        Sleep, 1100
        Click, % DESTINY_X + 270 " " DESTINY_Y + 338 " "
        Click, Up
        Sleep, 1000
        landingOffset := 0
        loop, 10
        {
            ; check if we are still on the map screen (this means this function fucked up)
            percent_white := exact_color_check("920|58|56|7", 56, 7, 0xECECEC)
            if (percent_white >= 0.3)
            {
                d2_click(295 + landingOffset, 338, 0) ; try clicking a bit to the side
                Sleep, 100
                Click, Up
                Sleep, 100
                Click, % DESTINY_X + 295 + landingOffset " " DESTINY_Y + 338 " "
                Click, Down
                Sleep, 1100
                Click, % DESTINY_X + 295 + landingOffset " " DESTINY_Y + 338 " "
                Click, Up
                Sleep, 1000
            }
            percent_white := exact_color_check("920|58|56|7", 56, 7, 0xECECEC)
            if (!percent_white >= 0.3) ; we clicked succesfully
                break
            landingOffset := landingOffset + 25
        }
        if (!percent_white >= 0.3) ; we clicked succesfully
            break
        Send, % "{" key_binds["ui_open_director"] "}"
        Sleep, 2000
    }
    return
}

orbit_landing() ; loads into the landing from orbit
{
    loop, 5
    {
        Send, % "{" key_binds["ui_open_director"] "}"
        Sleep, 2500
        d2_click(640, 360, 0)
        Sleep, 500
        d2_click(640, 360)
        Sleep, 1800
        d2_click(20, 381, 0) ; mouse to drag map and show landing icon
        PreciseSleep(850)
        d2_click(270, 338, 0) ; mouse stop drag and hover landing
        Sleep, 100
        d2_click(270, 338) ; mouse click landing
        Sleep, 1500
        percent_white := simpleColorCheck("33|573|24|24", 24, 24)
        if (!percent_white >= 0.4) ; we missed the landing zone
        {
            d2_click(295, 338, 0) ; try clicking a bit to the side
            Sleep, 100
            d2_click(295, 338)
            Sleep, 1500
            percent_white := simpleColorCheck("33|573|24|24", 24, 24) ; check again, if still not in the right screen, close map and try again
            if (!percent_white >= 0.4)
            {
                Send, % "{" key_binds["ui_open_director"] "}"
                Sleep, 1500
                Continue
            }
        }
        d2_click(1080, 601, 0)
        Sleep, 100
        d2_click(1080, 601)
        return true
    }
    return false ; 5 fuckups in a row and it fails
}
; =================================== ;

; Destiny Helper Functions
; =================================== ;
change_character(slot := "")
{
    if (slot = "")
        slot := PLAYER_DATA[CURRENT_GUARDIAN]["Settings"]["Slot"]
    
    if (!key_binds["ui_open_start_menu_settings_tab"]) ; if no settings keybind use f1 :D (slower)
    {
        Send, {F1}
        Sleep, 3000
        d2_click(1144, 38, 0)
        Sleep, 100
        d2_click(1144, 38)
    }
    else
        Send, % "{" key_binds["ui_open_start_menu_settings_tab"] "}"
    Sleep, 1500
    d2_click(184, 461, 0)
    Sleep, 150
    d2_click(184, 461)
    Sleep, 700
    d2_click(1030, 165, 0)
    Sleep, 150
    d2_click(1030, 165)
    Sleep, 500
    Send, {Enter}
    Sleep, 5000
    search_start := A_TickCount
    while (simpleColorCheck("803|270|42|60", 42, 60) < 0.03)
    {
        if (A_TickCount - search_start > 90000)
            break
    }
    Sleep, 2000
    if (slot == "Top")
    {
        d2_click(900, 304, 0)
        Sleep, 100
        d2_click(900, 304)
    }
    else if (slot == "Middle")
    {
        d2_click(885, 379, 0)
        Sleep, 100
        d2_click(885, 379)
    }
    else if (slot == "Bottom")
    {
        d2_click(902, 448, 0)
        Sleep, 100
        d2_click(902, 448)
    }
    d2_click(640, 360, 0)
    Sleep, 6000
    search_start := A_TickCount
    while (true) ; wait for screen to be not black (just checking 3 random pixels)
    {
        if ((!check_pixel([0x000000], 50, 50)
            || !check_pixel([0x000000], 100, 100)
            || !check_pixel([0x000000], 400, 400))
            || A_TickCount - search_start > 90000)
        {
            break
        }
    }
    return
}

set_fireteam_privacy(choice="invite") ; sets fireteam privacy :D
{
    StringLower, choice, choice

    Switch choice {
        case "1", "public", "open":
            choice := 0
        case "2", "friend", "friends":
            choice := 2
        case "3", "invite":
            choice := 3
        case "4", "closed", "private":
            choice := 4
        default:
            choice := 4  
    }
    if (!key_binds["ui_open_start_menu_settings_tab"])
    {
        Send, {F1}
        Sleep, 3000
        d2_click(1144, 38, 0)
        Sleep, 100
        d2_click(1144, 38)
    }
    else
        Send, % "{" key_binds["ui_open_start_menu_settings_tab"] "}"
    Sleep, 900
    d2_click(192, 524, 0)
    Sleep, 900
    d2_click(192, 524)
    Sleep, 500
    d2_click(1187, 167, 0) 
    Sleep, 200
    Loop, 4 ; go to closed
    {
        d2_click(1187, 167)
        Sleep, 85
    }
    d2_click(989, 167, 0)
    Sleep, 85
    Loop, % 4 - choice ; go from closed back to choice
    {
        d2_click(989, 167)
        Sleep, 85
    }
    if (key_binds["ui_open_start_menu_settings_tab"])
        send, % "{" key_binds["ui_open_start_menu_settings_tab"] "}"
    else 
        send, {esc}
    return
}

game_restart() ; not used in this script but could be added to allwo it to run through crashes :partying_face:
{
    WinKill, Destiny 2 ; Close Destiny 2 window
    Sleep, 20000 ; Wait for 30 seconds to ensure the window has fully closed
    Run, steam://rungameid/1085660,, Hide ; This launches Destiny 2 through Steam
    Sleep, 20000
    WinWait, Destiny 2
    Sleep, 20000
    WinActivate, Destiny 2
    find_d2()
    while (simpleColorCheck("581|391|87|15", 87, 15) < 0.90)
    {
        if (A_TickCount - search_start > 90000)
            break
    }
    Sleep, 10
    Send, {enter}
    Send, {enter}
    Send, {enter}
    Sleep, 10000
    while (simpleColorCheck("802|274|64|20", 64, 20) < 0.12)
    {
        if (A_TickCount - search_start > 90000)
            break
    }
    d2_click(900, 374, 0)
    Sleep, 100 
    d2_click(900, 374)
    return
}

wait_for_spawn(time_out:=200000) ; waits for spawn in by checking for heavy ammo color and blue blip on minimap
{
    start_time := A_TickCount
    loop,
    {
        x_off := -2
        loop, 3
        {
            y_off := 0
            loop, 5
            {
                if(check_pixel([0xFFFFFF], 65 + x_off, 60 + y_off)) ; raid logo
                {
                    if(check_pixel([0xC19AFF, 0xC299FF], 387 + x_off, 667 + y_off)) ; heavy ammo
                        return true ; This subsequent check prevents some planets from throwing false positive
                }
                Sleep, 10
                if(check_pixel([0x6F98CB], 85 + x_off, 84 + y_off)) ; minimap
                    return true
                Sleep, 10
                if(check_pixel([0xC19AFF, 0xC299FF], 387 + x_off, 667 + y_off)) ; heavy ammo
                    return true
                Sleep, 10
                y_off := y_off + 2
            }
            x_off := x_off + 1
        }
        if (A_TickCount - start_time > time_out) ; times out eventually so we dont get stuck forever
            return false
    }
    return true
}
; =================================== ;

; Color Functions
; =================================== ;
simpleColorCheck(coords, w, h) ; bad function to check for pixels that are "white enough" in a given area
{
    ; convert the coords to be relative to destiny 
    coords := StrSplit(coords, "|")
    x := coords[1] + DESTINY_X
    y := coords[2] + DESTINY_Y
    coords := x "|" y "|" w "|" h
    pBitmap := %dGdip_BitmapFromScreen%(coords)
    ; save bitmap 
    ; %dGdip_SaveBitmapToFile%(pBitmap, A_ScriptDir . "\test.png")
    x := 0
    y := 0
    white := 0
    total := 0
    loop %h%
    {
        loop %w%
        {
            color := ( %dGdip_GetPixel%(pBitmap, x, y) & 0x00F0F0F0)
            if (color == 0xF0F0F0)
                white += 1
            total += 1
            x+= 1
        }
        x := 0
        y += 1
    }
    %dGdip_DisposeImage%(pBitmap)
    pWhite := white/total
    return pWhite
}

exact_color_check(coords, w, h, base_color) ; also bad function to check for specific color pixels in a given area
{
    ; convert the coords to be relative to destiny 
    coords := StrSplit(coords, "|")
    x := coords[1] + DESTINY_X
    y := coords[2] + DESTINY_Y
    coords := x "|" y "|" w "|" h
    pBitmap := %dGdip_BitmapFromScreen%(coords)
    ; save bitmap 
    ; %dGdip_SaveBitmapToFile%(pBitmap, A_ScriptDir . "\test.png")
    x := 0
    y := 0
    white := 0
    total := 0
    loop %h%
    {
        loop %w%
        {
            color := (%dGdip_GetPixel%(pBitmap, x, y) & 0x00FFFFFF)
            if (color == base_color)
                white += 1
            total += 1
            x+= 1
        }
        x := 0
        y += 1
    }
    %dGdip_DisposeImage%(pBitmap)
    pWhite := white/total
    return pWhite

}

check_pixel( allowed_colors, pixel_x, pixel_y )
{
    pixel_x := pixel_x + DESTINY_X
    pixel_y := pixel_y + DESTINY_Y

    PixelGetColor, pixel_color, pixel_x, pixel_y, RGB
    found := false
    for _, color in allowed_colors {
        if (pixel_color == color) {
            found := true
        }
    }

    if (DEBUG)
        draw_crosshair(pixel_x, pixel_y)

    return found
}
; =================================== ;

; Other Functions
; =================================== ;
find_d2() ; find the client area of d2
{
    ; Detect the Destiny 2 game window
    WinGet, Destiny2ID, ID, ahk_exe destiny2.exe
    D2_WINDOW_HANDLE := Destiny2ID

    if (!D2_WINDOW_HANDLE)
    {
        MsgBox, Unable to find Destiny 2. Please launch the game and then run the script.
        ExitApp
    }
    
    ; Get the dimensions of the game window's client area
    WinGetPos, X, Y, Width, Height, ahk_id %Destiny2ID%
    if(Y < 1) {
        WinMove, ahk_exe destiny2.exe,, X, 1
    }
    WinGetPos, X, Y, Width, Height, ahk_id %Destiny2ID%
    VarSetCapacity(Rect, 16)
    DllCall("GetClientRect", "Ptr", WinExist("ahk_id " . Destiny2ID), "Ptr", &Rect)
    ClientWidth := NumGet(Rect, 8, "Int")
    ClientHeight := NumGet(Rect, 12, "Int")

    ; Calculate border and title bar sizes
    BorderWidth := (Width - ClientWidth) // 2
    TitleBarHeight := Height - ClientHeight - BorderWidth

    ; Update the global vars
    DESTINY_X := X + BorderWidth
    DESTINY_Y := Y + TitleBarHeight
    DESTINY_WIDTH := ClientWidth
    DESTINY_HEIGHT := ClientHeight
    return
}

get_mouse_pos_relative_to_d2() ; gets the mouse coords in x, y form relative to destinys client area
{
    ; Get the current mouse position
    MouseGetPos, mouseX, mouseY

    ; Calculate the position relative to the Destiny 2 client area
    relativeX := mouseX - DESTINY_X
    relativeY := mouseY - DESTINY_Y

    Clipboard := relativeX ", " relativeY
    return {X: relativeX, Y: relativeY}
}

d2_click(x, y, press_button:=1) ; click somewhere on d2
{
    Click, % DESTINY_X + x " " DESTINY_Y + y " " press_button
    return
}

destiny_screenshot(file_location:="\destiny_screenshot.png") ; take screenshot of just destiny screen, helpful for devving or debugging
{
    ; Take a screenshot of the Destiny 2 client area
    pBitmap := %dGdip_BitmapFromScreen%(DESTINY_X "|" DESTINY_Y "|" DESTINY_WIDTH "|" DESTINY_HEIGHT)

    ; Save the screenshot to a file
    %dGdip_SaveBitmapToFile%(pBitmap, A_ScriptDir . file_location)

    ; Clean up
    %dGdip_DisposeImage%(pBitmap)
    return
}

PreciseSleep(s) ; awesome sleep function wow
{
    DllCall("QueryPerformanceFrequency", "Int64*", QPF)
    DllCall("QueryPerformanceCounter", "Int64*", QPCB)
    While (((QPCA - QPCB) / QPF * 1000) < s)
        DllCall("QueryPerformanceCounter", "Int64*", QPCA)
    return ((QPCA - QPCB) / QPF * 1000) 
}

format_timestamp(timestamp, show_hours, show_minutes, show_seconds, show_ms, round_ms:=2) ; just like, dont ask, its shit
{
    numSeconds := Floor(timestamp / 1000)
    numHours := Floor(numSeconds / 3600)
    numMinutes := Mod(Floor(numSeconds / 60), 60)
    numSeconds := Mod(numSeconds, 60)
    numMS := Mod(timestamp, 1000)

    highestUnit := show_hours ? 1 : (show_minutes ? 2 : (show_seconds ? 3 : 4))
    lowestUnit := show_ms ? 4 : (show_seconds ? 3 : (show_minutes ? 2 : 1))

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

get_d2_keybinds(k) ; very readable function that parses destiny 2 cvars file for keybinds
{
    FileRead, f, % A_AppData "\Bungie\DestinyPC\prefs\cvars.xml"
    if ErrorLevel 
        return False
    b := {}, t := {"shift": "LShift", "control": "LCtrl", "alt": "LAlt", "menu": "AppsKey", "insert": "Ins", "delete": "Del", "pageup": "PgUp", "pagedown": "PgDn", "keypad`/": "NumpadDiv", "keypad`*": "NumpadMult", "keypad`-": "NumpadSub", "keypad`+": "NumpadAdd", "keypadenter": "NumpadEnter", "leftmousebutton": "LButton", "middlemousebutton": "MButton", "rightmousebutton": "RButton", "extramousebutton1": "XButton1", "extramousebutton2": "XButton2", "mousewheelup": "WheelUp", "mousewheeldown": "WheelDown", "escape": "Esc"}
    for _, n in k 
        RegExMatch(f, "<cvar\s+name=""`" n `"""\s+value=""([^""]+)""", m) ? b[n] := t.HasKey(k2 := StrReplace((k1 := StrSplit(m1, "!")[1]) != "unused" ? k1 : k1[2], " ", "")) ? t[k2] : k2 : b[n] := "unused"
    return b
}

IsAdminProcess(pid)
{
    hProcess := DllCall("OpenProcess", "UInt", 0x1000, "Int", False, "UInt", pid, "Ptr")
    if (!hProcess)
        return False
    if !DllCall("Advapi32.dll\OpenProcessToken", "Ptr", hProcess, "UInt", 0x0008, "PtrP", hToken)
    {
        DllCall("CloseHandle", "Ptr", hProcess)
        return False
    }
    VarSetCapacity(TOKEN_ELEVATION, 4, 0)
    cbSize := 4
    if !DllCall("Advapi32.dll\GetTokenInformation", "Ptr", hToken, "UInt", 20, "Ptr", &TOKEN_ELEVATION, "UInt", cbSize, "UIntP", cbSize)
    {
        DllCall("CloseHandle", "Ptr", hToken)
        DllCall("CloseHandle", "Ptr", hProcess)
        return False
    }
    DllCall("CloseHandle", "Ptr", hToken)
    DllCall("CloseHandle", "Ptr", hProcess)
    return NumGet(TOKEN_ELEVATION, 0) != 0
}

commit_current_stats()
{
    for _, class_type in CLASSES {
        for _, class_stat in CLASS_STAT_TYPES {
            if InStr(class_stat, "current_") {
                total_stat := StrReplace(class_stat, "current_", "total_")
                PLAYER_DATA[class_type]["ClassStats"][total_stat] += PLAYER_DATA[class_type]["ClassStats"][class_stat]
                PLAYER_DATA[class_type]["ClassStats"][class_stat] := 0
            }
        }

        for _, chest_id in CHEST_IDS {
            for _, chest_stat in CHEST_STAT_TYPES {
                if InStr(chest_stat, "current_") {
                    total_stat := StrReplace(chest_stat, "current_", "total_")
                    PLAYER_DATA[class_type]["ChestStats"][chest_id][total_stat] += PLAYER_DATA[class_type]["ChestStats"][chest_id][chest_stat]
                    PLAYER_DATA[class_type]["ChestStats"][chest_id][chest_stat] := 0
                }
            }
        }
    }
}

read_ini() ; yuck, json would be so much nicer
{
    ; check if there is a file called `afk_chest_stats.ini` and if so, load the stats from it
    if (FileExist("afk_chest_stats.ini")) {

        IniRead, CURRENT_GUARDIAN, afk_chest_stats.ini, Stats, Last_Guardian, Hunter
        IniRead, TOTALS_DISPLAY, afk_chest_stats.ini, Stats, Totals_Display, All

        for _, class_type in CLASSES {

            IniRead, temp, afk_chest_stats.ini, % class_type, Slot, Top
            PLAYER_DATA[class_type]["Settings"]["Slot"] := temp
            IniRead, temp, afk_chest_stats.ini, % class_type, Aachen, Kinetic
            PLAYER_DATA[class_type]["Settings"]["Aachen"] := temp



            for _, class_stat_type in CLASS_STAT_TYPES {
                if (InStr(class_stat_type, "total")) {
                    IniRead, temp, afk_chest_stats.ini, % class_type, % class_stat_type, 0
                    PLAYER_DATA[class_type]["ClassStats"][class_stat_type] := temp
                }
            }

            for _, chest_id in CHEST_IDS {
                for _, chest_stat_type in CHEST_STAT_TYPES {
                    if (InStr(chest_stat_type, "total"))
                    {
                        for _, chest_id in CHEST_IDS {
                            IniRead, temp, afk_chest_stats.ini, % class_type, % chest_id "_" chest_stat_type, 0
                            PLAYER_DATA[class_type]["ChestStats"][chest_id][chest_stat_type] := temp
                        }
                    }
                }
            }
        }
    }
}

write_ini()
{
    if (STARTUP_SUCCESSFUL)
    {
        commit_current_stats()

        IniWrite, % CURRENT_GUARDIAN, afk_chest_stats.ini, Stats, Last_Guardian
        IniWrite, % TOTALS_DISPLAY, afk_chest_stats.ini, Stats, Totals_Display

        for _, class_type in CLASSES {

            IniWrite, % PLAYER_DATA[class_type]["Settings"]["Slot"], afk_chest_stats.ini, % class_type, Slot
            IniWrite, % PLAYER_DATA[class_type]["Settings"]["Aachen"], afk_chest_stats.ini, % class_type, Aachen

            for _, class_stat_type in CLASS_STAT_TYPES {
                if (InStr(class_stat_type, "total")) {
                    IniWrite, % PLAYER_DATA[class_type]["ClassStats"][class_stat_type], afk_chest_stats.ini, % class_type, % class_stat_type
                }
            }

            for _, chest_id in CHEST_IDS {
                for _, chest_stat_type in CHEST_STAT_TYPES {
                    if (InStr(chest_stat_type, "total"))
                    {
                        for _, chest_id in CHEST_IDS {
                            IniWrite, % PLAYER_DATA[class_type]["ChestStats"][chest_id][chest_stat_type], afk_chest_stats.ini, % class_type, % chest_id "_" chest_stat_type
                        }
                    }
                }
            }
        }
    }
}

draw_crosshair( x:=0, y:=0 )
{   
    CrosshairColor := 0x0000FF ; Red
    LineLength := 50

    ; Create a device context for the screen
    hdc := DllCall("GetDC", "Ptr", 0, "Ptr")
    
    ; Create a red pen with 1px width
    hPen := DllCall("CreatePen", "Int", 0, "Int", 1, "UInt", CrosshairColor, "Ptr")
    hOldPen := DllCall("SelectObject", "Ptr", hdc, "Ptr", hPen)
    
    ; Draw the vertical line
    DllCall("MoveToEx", "Ptr", hdc, "Int", x, "Int", y - LineLength, "Ptr", 0)
    DllCall("LineTo", "Ptr", hdc, "Int", x, "Int", y + LineLength)
    
    ; Draw the horizontal line
    DllCall("MoveToEx", "Ptr", hdc, "Int", x - LineLength, "Int", y, "Ptr", 0)
    DllCall("LineTo", "Ptr", hdc, "Int", x + LineLength, "Int", y)
    
    ; Restore the old pen and delete the created pen
    DllCall("SelectObject", "Ptr", hdc, "Ptr", hOldPen)
    DllCall("DeleteObject", "Ptr", hPen)
    
    ; Release the device context
    DllCall("ReleaseDC", "Ptr", 0, "Ptr", hdc)
    
    return
}

toggle_gui(visibility := "")
{
    if (visibility = "")
        visibility := (GUI_VISIBLE) ? "hide" : "show"

    for index, ui_element in overlay_elements
    {
        ui_element.toggle_visibility(visibility)
        if (ui_element.has_background)
            ui_element.toggle_background_visibility(visibility)
    }

    if (visibility = "show") {
        Gui, info_BG: Show, NA
        GUI_VISIBLE := true
    } else {
        Gui, info_BG: Hide
        GUI_VISIBLE := false
    }

    return
}

check_tabbed_out:
{
    destiny_active := false
    selection_ui_active := false
    IfWinActive, ahk_exe destiny2.exe
        destiny_active := true
    IfWinActive, ahk_id %user_input_hwnd%
        selection_ui_active := true
    if (destiny_active || selection_ui_active)
    {
        if (!GUI_VISIBLE)
            toggle_gui("show")
    }
    else
    {
        if (GUI_VISIBLE)
            toggle_gui("hide")
    }
}

release_d2_bindings()
{
    for key, value in key_binds 
        send, % "{" value " Up}"
    return
}

on_script_exit()
{
    if (CHEST_PID)
        Process, Close, %CHEST_PID%
    if (EXOTIC_PID)
        Process, Close, %EXOTIC_PID%

    release_d2_bindings()
    if (HEARTBEAT_ON)
    {
        send_heartbeat()
        HEARTBEAT_ON := false
    }
    write_ini()
}

; Function to send heartbeat to the server
send_heartbeat() {
    unrecorded_runtime := PLAYER_DATA[CURRENT_GUARDIAN]["ClassStats"]["current_time"] - RECORDED_RUNTIME
    unrecorded_loops := PLAYER_DATA[CURRENT_GUARDIAN]["ClassStats"]["current_runs"] - RECORDED_LOOPS
    unrecorded_chests := current_chest("pickups") - RECORDED_CHESTS
    unrecorded_exotics := PLAYER_DATA[CURRENT_GUARDIAN]["ClassStats"]["current_exotics"] - RECORDED_EXOTICS

    ; Construct the JSON payload with the delta values
    json := "{"
    json .= """version""" . ":" . """" . VERSION . """" . ","
    json .= """runtime""" . ":" . unrecorded_runtime . ","
    json .= """loops""" . ":" . unrecorded_loops . ","
    json .= """chests_opened""" . ":" . unrecorded_chests . ","
    json .= """exotic_drops""" . ":" . unrecorded_exotics
    json .= "}"

    try {
        HttpObj := ComObjCreate("MSXML2.XMLHTTP")
        	HttpObj.SetTimeouts(1000, 1000, 1000, 1000) ; Timeout settings: Resolve, Connect, Send, Receive
        	HttpObj.Open("POST", API_URL, false) ; true for async
        	HttpObj.SetRequestHeader("Content-Type", "application/json")
        	HttpObj.Send(json)
        	response := HttpObj.responseText

        ; MsgBox, "Sent: " . %json%

        if InStr(response, "received")
        {
            ; Add what was received to the recorded totals, which are subtracted from current session values
            ; so we can send the difference (unrecorded) in the next heartbeat.
            RECORDED_RUNTIME += unrecorded_runtime
            RECORDED_LOOPS += unrecorded_loops
            RECORDED_CHESTS += unrecorded_chests
            RECORDED_EXOTICS += unrecorded_exotics
        }
        Else
        {
            ; MsgBox, "Recording error: " . %response%
        }
    } catch e {
        ; Silence any errors and continue execution
        ; MsgBox, "HTTP error."
    }
}

; Popup Dialog Functions
; =================================== ;
    build_dropdown_string(options, selected) {
        dropdown := ""
        for index, option in options {
            if (option = selected)
                dropdown .= option "||"
            else
                dropdown .= option "|"
        }
        return dropdown
    }

    ; Handle ClassChoice change
    ClassChoiceChanged:
        Gui, user_input: Submit, NoHide
        CURRENT_GUARDIAN := ClassChoice
        current_class.update_content("Selected Class - " CURRENT_GUARDIAN)   
        label_total.update_content("Total AFK Stats (" . (TOTALS_DISPLAY = "All" ? "All" : CURRENT_GUARDIAN) . "):")
        slotDropdown := build_dropdown_string(CHARACTER_SLOTS, PLAYER_DATA[CURRENT_GUARDIAN]["Settings"]["Slot"])
        aachenDropdown := build_dropdown_string(AACHEN_CHOICES, PLAYER_DATA[CURRENT_GUARDIAN]["Settings"]["Aachen"])
        GuiControl,, SlotChoice, % "|" slotDropdown
        GuiControl,, AachenChoice, % "|" aachenDropdown
        total_time_afk_ui.update_content("Time AFK - " format_timestamp(compute_total_stat("time"), true, true, true, false))
        update_ui()
    return

    ; Handle OK button click
    user_input_OK:
        Gui, user_input: Submit
        CURRENT_GUARDIAN := ClassChoice
        PLAYER_DATA[CURRENT_GUARDIAN]["Settings"]["Slot"] := SlotChoice
        PLAYER_DATA[CURRENT_GUARDIAN]["Settings"]["Aachen"] := AachenChoice
        DEBUG := DebugChoice
        WinActivate, ahk_id %D2_WINDOW_HANDLE%
        Gui, user_input: Destroy
        INPUT_POPUP_HANDLED := true
        SetTimer, check_tabbed_out, 200
    return

    TotalModeChanged:
        Gui, user_input: Submit, NoHide
        if (TotalModeAll = 1) {
            TOTALS_DISPLAY := "All"
        } else if (TotalModeClass = 1) {
            TOTALS_DISPLAY := "Class"
        }
        label_total.update_content("Total AFK Stats (" . (TOTALS_DISPLAY = "All" ? "All" : CURRENT_GUARDIAN) . "):")
        total_time_afk_ui.update_content("Time AFK - " format_timestamp(compute_total_stat("time"), true, true, true, false))
        update_ui()
    return
    
    ; Exit script when GUI is closed
    GuiClose:
    Gui, user_input: Destroy
    return
; =================================== ;

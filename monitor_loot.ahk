#Requires AutoHotkey v1.1.27+
#Include %A_ScriptDir%/Gdip_ALL.ahk
#SingleInstance, Off
#Persistent
DetectHiddenWindows, On
; Register message handlers for start and stop commands
OnMessage(0x1001, "StartMonitoring")
OnMessage(0x1002, "StopMonitoring")

; Get the task from command line arguments
global main_pid := A_Args[1]
global task := A_Args[2]
;MsgBox, "mainpid: " . %main_pid% . " task: " . %task%

global DESTINY_X := 0
global DESTINY_Y := 0
global DESTINY_WIDTH := 0
global DESTINY_HEIGHT := 0
find_d2()

global monitoring := false

Gui, Show, Hide, ChildWindow
Return

StartMonitoring(wParam, lParam, msg, hwnd) {
    pToken := Gdip_Startup()
    monitoring := true
    if (task = "chest") {
        CheckChestOpen()
        SetTimer, CheckChestOpen, 50
    } else if (task = "exotic") {
        CheckExoticDrop()
        SetTimer, CheckExoticDrop, 50
    }
}

StopMonitoring(wParam, lParam, msg, hwnd) {
    monitoring := false
    if (task = "chest") {
        SetTimer, CheckChestOpen, Off
    } else if (task = "exotic") {
        SetTimer, CheckExoticDrop, Off
    }
}

CheckChestOpen()
{
    WinActivate, Destiny 2
    percent_white := exact_color_check("583|473|34|32", 34, 32, 0xCBE4FF) ; checks for the circle around the interact prompt
    if (percent_white > 0.07)
    {
        PostMessage, 0x1003, 0, 0, , % "ahk_pid " main_pid
        SetTimer, CheckChestOpen, Off
    }
    Return
}

CheckExoticDrop()
{
    WinActivate, Destiny 2
    percent_white_1 := exact_color_check("1258|198|20|80", 20, 80, 0xD8BD48) ; check for exotic color on side of screen
    percent_white_2 := exact_color_check("1258|278|20|80", 20, 80, 0xD8BD48)
    percent_white_3 := exact_color_check("1258|358|20|80", 20, 80, 0xD8BD48)
    percent_white_4 := exact_color_check("1258|438|20|80", 20, 80, 0xD8BD48)
    if (percent_white_1 > 0.02 || percent_white_2 > 0.02 || percent_white_3 > 0.02 || percent_white_4 > 0.02)
    {
        PostMessage, 0x1004, 0, 0, , % "ahk_pid " main_pid
        SetTimer, CheckExoticDrop, Off
    }
    Return
}

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

exact_color_check(coords, w, h, base_color) ; also bad function to check for specific color pixels in a given area
{
    ; convert the coords to be relative to destiny 
    coords := StrSplit(coords, "|")
    x := coords[1] + DESTINY_X
    y := coords[2] + DESTINY_Y
    coords := x "|" y "|" w "|" h
    pBitmap := Gdip_BitmapFromScreen(coords)
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
            color := (Gdip_GetPixel(pBitmap, x, y) & 0x00FFFFFF)
            if (color == base_color)
                white += 1
            total += 1
            x+= 1
        }
        x := 0
        y += 1
    }
    Gdip_DisposeImage(pBitmap)
    pWhite := white/total
    return pWhite

}
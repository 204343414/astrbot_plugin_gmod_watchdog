@echo off
chcp 65001
title GMod 看门狗

set SERVER_DIR=D:\gmod\Gmod\gmod
set SERVER_EXE=srcds.exe
set CHECK_INTERVAL=5
set MAX_FAILS=4
set FAIL_COUNT=0
set BOT_URL=http://你的astrBot的服务器IP:9876/gmod_event

:LOOP
echo [%date% %time%] 检查服务器状态...

tasklist /FI "IMAGENAME eq %SERVER_EXE%" 2>NUL | find /I "%SERVER_EXE%" >NUL

if %ERRORLEVEL% NEQ 0 (
    set /a FAIL_COUNT+=1
    echo [警告] 服务器未运行 (%FAIL_COUNT%/%MAX_FAILS%)

    if %FAIL_COUNT% GEQ %MAX_FAILS% (
        goto RESTART
    )
) else (
    set FAIL_COUNT=0
)

timeout /t %CHECK_INTERVAL% /nobreak >NUL
goto LOOP

:RESTART
echo [%date% %time%] 服务器崩溃！执行重启...

REM 通知 AstrBot
curl -s -X POST %BOT_URL% -d "payload={\"event\":\"crash\",\"time\":\"%date% %time%\",\"secret\":\"在这里填同样的密码\",\"data\":{\"message\":\"服务器崩溃已自动重启\"}}" >NUL 2>NUL

REM 强制清理
taskkill /F /IM %SERVER_EXE% 2>NUL
timeout /t 5 /nobreak >NUL

REM 重启
cd /d %SERVER_DIR%
start "" %SERVER_EXE% -console -game garrysmod +maxplayers 16 +map gm_construct +gamemode sandbox +sv_lan 1

echo [%date% %time%] 服务器已重启
set FAIL_COUNT=0
timeout /t 30 /nobreak >NUL

goto LOOP


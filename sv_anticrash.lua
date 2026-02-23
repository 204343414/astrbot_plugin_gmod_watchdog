print("[反炸服] ====== 反炸服看门狗 V2.0 已加载 ======")

-- ============================================
-- 配置区域
-- ============================================
local CONFIG = {
    LagThreshold    = 1.0,
    LagDuration     = 5,
    ScanTime        = 15,
    MaxWarnings     = 3,
    BanFile         = "anticrash_bans.json",
    WebhookURL      = "http://你的美国服务器IP:9876",
    Secret          = "在这里填一串你自己编的随机密码",
    SafeMode        = false
}

-- ============================================
-- 变量初始化
-- ============================================
local recentActions = {}
local warningData   = {}
local lagStartTime  = nil

-- ============================================
-- 警告数据 读写
-- ============================================
local function LoadWarnings()
    if file.Exists(CONFIG.BanFile, "DATA") then
        local json = file.Read(CONFIG.BanFile, "DATA")
        warningData = util.JSONToTable(json) or {}
    end
end

local function SaveWarnings()
    file.Write(CONFIG.BanFile, util.TableToJSON(warningData, true))
end

LoadWarnings()

-- ============================================
-- 核心：发送数据到美国服务器
-- ============================================
local function SendToBot(eventType, data)
    local payload = util.TableToJSON({
        event    = eventType,
        time     = os.date("%Y-%m-%d %H:%M:%S"),
        server   = GetHostName() or "未知",
        data     = data
    })

    http.Post(
        CONFIG.WebhookURL .. "/gmod_event",
        { payload = payload },
        function(body) end,  -- 成功回调（不需要处理）
        function(err)
            print("[反炸服] 发送到Bot失败: " .. tostring(err))
        end
    )
end

-- ============================================
-- 核心：记录玩家操作
-- ============================================
local function LogAction(ply, actionType, detail)
    if not IsValid(ply) then return end

    local entry = {
        time    = os.time(),
        sid     = ply:SteamID(),
        name    = ply:Nick(),
        action  = actionType,
        detail  = detail or "N/A"
    }

    table.insert(recentActions, entry)
    print(string.format("[监控] %s Used %s (%s)", ply:Nick(), actionType, detail or ""))

    -- 清理30秒前的记录
    local cutoff = os.time() - 30
    for i = #recentActions, 1, -1 do
        if recentActions[i].time < cutoff then
            table.remove(recentActions, i)
        end
    end
end

-- ============================================
-- 监听工具枪
-- ============================================
hook.Add("CanTool", "AntiCrash_ToolMonitor", function(ply, tr, toolmode)
    if toolmode == "wire_expression2" then
        LogAction(ply, "E2_TOOL", "使用E2工具枪")
    elseif toolmode == "duplicator" or toolmode == "advdupe2" then
        LogAction(ply, "DUPLICATOR", toolmode)
    end
end)

-- ============================================
-- 监听实体生成
-- ============================================
hook.Add("PlayerSpawnedSENT", "AntiCrash_EntMonitor", function(ply, ent)
    LogAction(ply, "SPAWN_ENT", ent:GetClass())
end)

-- ============================================
-- 拦截 E2 代码上传 → 发送给 AstrBot
-- ============================================
hook.Add("InitPostEntity", "AntiCrash_E2Hook", function()
    timer.Simple(5, function()
        local E2Ent = scripted_ents.GetStored("gmod_wire_expression2")
        if not E2Ent or not E2Ent.t then
            print("[反炸服] 未找到 E2 实体类，Wiremod 可能未安装")
            return
        end

        local OriginalSetup = E2Ent.t.Setup

        E2Ent.t.Setup = function(self, code, ...)
            local ply = self:GetPlayer() or self.player

            if code and #code > 0 and IsValid(ply) then
                print(string.format("[E2记录] %s 上传了 E2 代码 (%d字符)", ply:Nick(), #code))

                -- 发送给美国服务器的 AstrBot
                SendToBot("e2_upload", {
                    player_name = ply:Nick(),
                    player_sid  = ply:SteamID(),
                    code_length = #code,
                    code        = string.sub(code, 1, 2000)  -- 最多发2000字符
                })

                -- 同时记录到操作日志
                LogAction(ply, "E2_UPLOAD", string.format("%d字符", #code))
            end

            return OriginalSetup(self, code, ...)
        end

        print("[反炸服] E2 代码监控已启动")
    end)
end)

-- ============================================
-- 惩罚逻辑（三振出局）
-- ============================================
local function PunishPlayer(sid, name)
    if not warningData[sid] then warningData[sid] = 0 end
    warningData[sid] = warningData[sid] + 1
    SaveWarnings()

    local strikes = warningData[sid]

    if strikes < CONFIG.MaxWarnings then
        local ply = player.GetBySteamID(sid)
        if IsValid(ply) then
            ply:Kick(string.format(
                "[自动防御] 检测到卡服操作 警告 %d/%d",
                strikes, CONFIG.MaxWarnings
            ))
        end

        PrintMessage(HUD_PRINTTALK, string.format(
            "[反炸服] %s 因卡服被踢 (警告 %d/%d)", name, strikes, CONFIG.MaxWarnings
        ))

        SendToBot("warning", {
            player_name = name,
            player_sid  = sid,
            strikes     = strikes,
            max         = CONFIG.MaxWarnings
        })
    else
        local ply = player.GetBySteamID(sid)
        if IsValid(ply) then
            ply:Ban(0, true)
            ply:Kick("[自动防御] 多次卡服已被永封 联系服主解封")
        else
            RunConsoleCommand("banid", "0", sid)
            RunConsoleCommand("writeid")
        end

        PrintMessage(HUD_PRINTTALK, string.format("[反炸服] %s 已被永久封禁", name))

        SendToBot("ban", {
            player_name = name,
            player_sid  = sid,
            reason      = "三振出局自动封禁"
        })
    end
end

-- ============================================
-- 性能监控与熔断
-- ============================================
hook.Add("Think", "AntiCrash_PerformanceDog", function()
    local ft = FrameTime()

    if ft > CONFIG.LagThreshold then
        if not lagStartTime then
            lagStartTime = SysTime()
            print("[反炸服] 检测到卡顿...")
        elseif SysTime() - lagStartTime > CONFIG.LagDuration then
            print("[反炸服] 触发熔断！")

            if not CONFIG.SafeMode then
                local culprits = {}
                local now = os.time()

                for _, entry in ipairs(recentActions) do
                    if now - entry.time <= CONFIG.ScanTime then
                        if not culprits[entry.sid] then
                            culprits[entry.sid] = entry.name
                        end
                    end
                end

                for sid, name in pairs(culprits) do
                    PunishPlayer(sid, name)
                end

                SendToBot("meltdown", {
                    culprits = culprits,
                    lag_duration = CONFIG.LagDuration
                })

                RunConsoleCommand("gmod_admin_cleanup")
            end

            lagStartTime = nil
            recentActions = {}
        end
    else
        if lagStartTime then print("[反炸服] 卡顿恢复") end
        lagStartTime = nil
    end

end)

-- ─────────────────────────────────────────────────────────────
--  grand_core: shared/config.lua
--  Master Global Configuration for Grand RP FiveM Edition
-- ─────────────────────────────────────────────────────────────

Config = {}

Config.ServerName = "Grand RP FiveM Edition"
Config.ServerNumber = "EN #1"
Config.Locale = "en"
Config.CurrencySymbol = "$"
Config.GrandCoinsSymbol = "GC"

-- Starting Economy Settings
Config.StartingCash = 5000
Config.StartingBank = 25000
Config.StartingGrandCoins = 500
Config.StartingLevel = 1
Config.StartingExp = 0
Config.ExpPerLevelMultiplier = 1000

-- Paycheck Loop Interval (Every 60 minutes)
Config.SalaryInterval = 60 * 60 * 1000

-- Default Spawn Aerodrome Coordinates (Los Santos International)
Config.DefaultSpawn = vector4(-1037.74, -2737.98, 20.17, 330.0)

-- Core Framework Exports & Bridges
Config.UseOxLib = true
Config.UseOxInventory = true
Config.UseOxMysql = true
Config.UsePmaVoice = true

-- Job Salary Table (Hourly payouts to bank accounts)
Config.JobSalaries = {
    ["unemployed"] = 250,
    ["police"] = {
        [0] = 1200, -- Cadet
        [1] = 1800, -- Officer
        [2] = 2400, -- Senior Officer
        [3] = 3200, -- Sergeant
        [4] = 4200, -- Lieutenant
        [5] = 5500, -- Captain
        [6] = 7500  -- Chief of Police
    },
    ["ambulance"] = {
        [0] = 1100, -- Trainee
        [1] = 1700, -- Paramedic
        [2] = 2600, -- Doctor
        [3] = 3800, -- Surgeon
        [4] = 5000  -- Chief of Medicine
    },
    ["fib"] = {
        [0] = 2000, -- Special Agent
        [1] = 3500, -- Senior Agent
        [2] = 5000, -- Supervisor
        [3] = 7000  -- Director
    },
    ["mechanic"] = 1500,
    ["taxi"] = 1000
}

-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_families/server/bridge.lua
--  The outward-facing API. Two audiences:
--    1. grand_phone's family hub, which calls exactly
--       GetFamilyForCitizen / GetVaultBalance / GetRoster /
--       GetIncomeReadout (see grand_phone/config.lua -> FamilyHub.bridge)
--    2. grand_gangs (turf wars) and grand_admin.
--  Loads after server/database.lua, so DB.* is available.
-- ─────────────────────────────────────────────────────────────

Bridge = {}
Families = Families or {}
Families.Bridge = Bridge

local RESOURCE = GetCurrentResourceName()

Bridge.LEVELS = { debug = 3, info = 2, warn = 1, error = 0 }

function Bridge.Log(level, message)
    if (Bridge.LEVELS[level] or 2) < (Bridge.LEVELS[Config.LogLevel] or 2) then return end
    local colour = ({ error = '^1', warn = '^3', info = '^7', debug = '^8' })[level] or '^7'
    print(('%s[%s][bridge] %s^7'):format(colour, RESOURCE, tostring(message)))
end

-- ─── Shape helpers ────────────────────────────────────────────
--- Trims a DB family row down to what another resource legitimately
--- needs. Never hand out the whole row: it carries the vault.
local function PublicFamily(row)
    if not row then return nil end
    return {
        id       = tonumber(row.id),
        name     = row.name,
        tag      = row.tag,
        colour   = row.color or '#FFFFFF',
        leader   = row.leader_citizenid,
        rank     = tonumber(row.member_rank) or 0,
        rankTitle = Util.RankTitle(row.member_rank or 0),
        vault    = math.floor(tonumber(row.balance) or 0),
        members  = tonumber(row.active_members) or 0,
        turfs    = tonumber(row.total_turfs) or 0,
        level    = tonumber(row.level) or 1,
        points   = tonumber(row.points) or 0,
        rating   = tonumber(row.rating) or 0,
    }
end
Bridge.PublicFamily = PublicFamily

-- ─── Phone hub contract ───────────────────────────────────────
function Bridge.GetFamilyForCitizen(citizenid)
    citizenid = Util.Clean(citizenid, 16)
    if citizenid == '' then return nil end
    return PublicFamily(DB.FamilyForCitizen(citizenid))
end

-- Alias kept for grand_gangs (it asks for this name first).
Bridge.GetFamilyByCitizenId = Bridge.GetFamilyForCitizen

--- Grand_gangs calls this to count a family's online fighters.
function Bridge.GetFamilyMembers(familyId)
    return Bridge.GetRoster(tonumber(familyId))
end

function Bridge.GetVaultBalance(familyId)
    local id = tonumber(familyId)
    if not id then
        -- callers may only know the citizenid
        local cid = Util.Clean(familyId, 16)
        local row = cid ~= '' and DB.FamilyForCitizen(cid) or nil
        return row and math.floor(tonumber(row.balance) or 0) or 0
    end
    return DB.VaultBalance(id)
end

function Bridge.GetRoster(familyId)
    local rows = DB.Roster(tonumber(familyId))
    local out = {}
    for _, row in ipairs(rows) do
        out[#out + 1] = {
            citizenid  = row.citizenid,
            name       = ('%s %s'):format(row.firstname or '?', row.lastname or ''),
            rank       = tonumber(row.rank) or 1,
            rankTitle  = Util.RankTitle(row.rank or 1),
            job        = row.job,
            joinedAt   = Util.SqlToEpoch(row.joined_at),
            deposits   = math.floor(tonumber(row.total_deposits) or 0),
            withdrawals= math.floor(tonumber(row.total_withdrawals) or 0),
            kills      = tonumber(row.kills_in_turf) or 0,
            captures   = tonumber(row.captures_assisted) or 0,
        }
    end
    return out
end

--- Hourly readout, tier-scaled so the phone meter fills the way
--- grand_phone Config.FamilyHub.meterScale expects.
function Bridge.GetIncomeReadout(familyId)
    local empty = { hourly = 0, daily = 0, vault = 0, solarPanels = 0,
                    oilWells = 0, turfs = 0, properties = 0 }

    local id = tonumber(familyId)
    if not id then
        local cid = Util.Clean(familyId, 16)
        local row = cid ~= '' and DB.FamilyForCitizen(cid) or nil
        if not row then return empty end
        id = tonumber(row.id)
    end

    local family = DB.Family(id)
    if not family then return empty end

    local turfRows = DB.TurfRows(id)
    local turfIncome = 0
    for _, turf in ipairs(turfRows) do
        local tier = math.floor(tonumber(turf.tier) or 1)
        local mult = Config.TurfWar.tierMultiplier[tier] or 1.0
        turfIncome = turfIncome + math.floor(Config.TurfWar.hourlyBase * mult)
    end

    local solar = math.floor(tonumber(family.solar_panels) or 0)
    local oil = math.floor(tonumber(family.oil_wells) or 0)
    local solarIncome = solar * (Config.Income.solarYield or 1500)
    local oilIncome = oil * (Config.Income.oilYield or 5000)

    local hourly = turfIncome + solarIncome + oilIncome

    return {
        hourly      = hourly,
        daily       = hourly * 24,
        vault       = math.floor(tonumber(family.balance) or 0),
        solarPanels = solar,
        oilWells    = oil,
        turfs       = #turfRows,
        properties  = math.floor(tonumber(family.total_properties) or 0),
        taxRate     = tonumber(family.tax_rate) or 0,
    }
end

-- ─── Vault movement (used by grand_gangs for turf payouts) ────
function Bridge.AddVault(familyId, amount, reason)
    local id = tonumber(familyId)
    local delta = math.floor(tonumber(amount) or 0)
    if not id or delta <= 0 then return false end
    if delta > Config.Income.capPerFamily then
        delta = Config.Income.capPerFamily
    end

    local after = DB.MoveVault(id, delta, 'income', 'system', tostring(reason or 'family income'))
    if not after then return false end

    Bridge.Broadcast(id, 'grand_families:client:VaultChanged', after)
    return true
end

function Bridge.WithdrawVault(familyId, amount, reason, citizenid)
    local id = tonumber(familyId)
    local delta = math.floor(tonumber(amount) or 0)
    if not id or delta <= 0 then return false end

    local after = DB.MoveVault(id, -delta, 'withdrawal', citizenid, tostring(reason or 'vault withdrawal'))
    if not after then return false end

    Bridge.Broadcast(id, 'grand_families:client:VaultChanged', after)
    return true
end

--- Sends an event to every online member of a family.
function Bridge.Broadcast(familyId, eventName, ...)
    local id = tonumber(familyId)
    if not id or not eventName then return 0 end

    local sent = 0
    local args = table.pack(...)
    for _, row in ipairs(DB.FamilyCitizenIds(id)) do
        local src = Util.TryExport('grand_core', 'GetSourceByCitizenId', row.citizenid)
        if src and tonumber(src) and src > 0 then
            TriggerClientEvent(eventName, src, table.unpack(args, 1, args.n))
            sent = sent + 1
        end
    end
    return sent
end

-- ─── Gang / turf integration ──────────────────────────────────
function Bridge.GetFamilyTurfPayload(familyId)
    local out = {}
    for _, turf in ipairs(DB.TurfRows(tonumber(familyId))) do
        out[#out + 1] = {
            id     = turf.turf_name,
            name   = turf.turf_name,
            tier   = tonumber(turf.tier) or 1,
            radius = tonumber(turf.radius) or 150.0,
            coords = { x = turf.coords_x, y = turf.coords_y, z = turf.coords_z },
        }
    end
    return out
end

function Bridge.IsFamilyMember(familyId, citizenid)
    local id = tonumber(familyId)
    local cid = Util.Clean(citizenid, 16)
    if not id or cid == '' then return false end
    return DB.Membership(id, cid) ~= nil
end

function Bridge.FamilyExists(familyId)
    local row = DB.Family(tonumber(familyId))
    return row ~= nil
end

--- Rank of a citizen inside a family, 0 when they are not a member.
function Bridge.GetMemberRank(familyId, citizenid)
    local member = DB.Membership(tonumber(familyId), Util.Clean(citizenid, 16))
    return member and (tonumber(member.rank) or 0) or 0
end

function Bridge.TransferTurf(turfName, fromFamilyId, toFamilyId)
    turfName = Util.Clean(turfName, 40)
    local spec = Config.TurfWar.TurfLocations[turfName]
    if not spec then return false, 'Unknown turf' end

    local to = tonumber(toFamilyId)
    if not to then return false, 'Invalid owner' end

    DB.LoseTurf(turfName, tonumber(fromFamilyId))
    local id = DB.ClaimTurf(to, turfName, spec.coords, spec.radius, spec.tier or 1)
    if not id then return false, 'Claim failed' end

    Bridge.Broadcast(to, 'grand_families:client:TurfGained', turfName)
    if fromFamilyId then
        Bridge.Broadcast(tonumber(fromFamilyId), 'grand_families:client:TurfLost', turfName)
    end

    DB.Activity(to, nil, 'capture', ('Captured turf "%s"'):format(turfName))
    return true, id
end

function Bridge.OwnsTurf(familyId, turfName)
    return DB.OwnsTurf(tonumber(familyId), Util.Clean(turfName, 40))
end

function Bridge.FamilyStats(familyId)
    local id = tonumber(familyId)
    local family = id and DB.Family(id) or nil
    if not family then
        return { turfs = 0, hourly = 0, wins = 0, losses = 0, vault = 0, members = 0 }
    end

    local readout = Bridge.GetIncomeReadout(id)
    local wins = tonumber(DB.Scalar(
        'SELECT COUNT(*) FROM grand_turf_wars WHERE winner_family_id = ? AND completed = 1', { id })) or 0
    local losses = tonumber(DB.Scalar([[
        SELECT COUNT(*) FROM grand_turf_wars
         WHERE defending_family_id = ? AND completed = 1
           AND (outcome = 'captured' OR (winner_family_id IS NOT NULL AND winner_family_id <> ?))
    ]], { id, id })) or 0

    return {
        turfs   = readout.turfs,
        hourly  = readout.hourly,
        wins    = wins,
        losses  = losses,
        vault   = readout.vault,
        members = tonumber(family.active_members) or 0,
        points  = tonumber(family.points) or 0,
        rating  = tonumber(family.rating) or 0,
    }
end

-- ─── Registration ─────────────────────────────────────────────
local EXPORTS = {
    -- phone hub
    'GetFamilyForCitizen', 'GetVaultBalance', 'GetRoster', 'GetIncomeReadout',
    -- vault
    'AddVault', 'WithdrawVault',
    -- membership + turf
    'IsFamilyMember', 'FamilyExists', 'GetMemberRank', 'GetFamilyTurfPayload',
    'TransferTurf', 'OwnsTurf', 'FamilyStats',
}

function Bridge.Register()
    for _, name in ipairs(EXPORTS) do
        local fn = Bridge[name]
        if fn then
            exports(name, fn)
        else
            Bridge.Log('error', ('export %s is missing from Bridge'):format(name))
        end
    end
    Bridge.Log('info', ('%d exports registered'):format(#EXPORTS))
end

return Bridge

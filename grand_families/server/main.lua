-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_families/server/main.lua
--  Commands, net events, boot. Loads last, so DB / Util / Bridge /
--  Income are already global.
--
--  ZERO qb-core. ZERO `exports.oxmysql:fetch(...)` style calls (that
--  API does not exist) - everything is MySQL.*.await through DB.*.
--  Money moves only through guarded grand_core exports, with a
--  characters.money JSON fallback.
-- ─────────────────────────────────────────────────────────────

local RESOURCE = GetCurrentResourceName()

-- ─── Logging ──────────────────────────────────────────────────
local LEVELS = { debug = 3, info = 2, warn = 1, error = 0 }

function Families.Log(level, message)
    if (LEVELS[level] or 2) < (LEVELS[Config.LogLevel] or 2) then return end
    local colour = ({ error = '^1', warn = '^3', info = '^7', debug = '^8' })[level] or '^7'
    print(('%s[%s] %s^7'):format(colour, RESOURCE, tostring(message)))
end

-- ─── Bridge to grand_core ─────────────────────────────────────
local Core = 'grand_core'

local function CitizenId(source)
    local cid = Util.TryExport(Core, 'GetCitizenId', source)
    if cid and #tostring(cid) >= 6 then return tostring(cid) end

    -- fallback: read the session table straight from the DB
    local identifier = GetPlayerIdentifierByType(source, 'license')
    if not identifier then return nil end
    local row = DB.Single([[
        SELECT citizenid FROM characters WHERE identifier = ?
         ORDER BY id DESC LIMIT 1
    ]], { identifier })
    return row and row.citizenid or nil
end

local function Notify(source, message, kind)
    if Util.TryExport(Core, 'Notify', source, tostring(message), kind or 'info') == nil then
        local rgb = ({ error = { 244, 67, 54 }, success = { 76, 175, 80 },
                       warning = { 255, 193, 7 } })[kind] or { 255, 255, 255 }
        TriggerClientEvent('chat:addMessage', source, {
            color = rgb, multiline = true,
            args = { 'Families', tostring(message) },
        })
    end
end

--- Reads the wallet: grand_core first, characters.money JSON second.
local function Wallet(source, citizenid)
    local money = Util.TryExport(Core, 'GetMoney', source)
    if type(money) == 'table' then
        return {
            cash   = math.floor(tonumber(money.cash) or 0),
            bank   = math.floor(tonumber(money.bank) or 0),
            crypto = math.floor(tonumber(money.crypto) or 0),
        }
    end
    local row = DB.Character(citizenid)
    local decoded = row and Util.Decode(row.money, nil) or nil
    return {
        cash   = decoded and math.floor(tonumber(decoded.cash) or 0) or 0,
        bank   = decoded and math.floor(tonumber(decoded.bank) or 0) or 0,
        crypto = decoded and math.floor(tonumber(decoded.crypto) or 0) or 0,
    }
end

local function WriteWallet(citizenid, money)
    return DB.Execute('UPDATE characters SET money = ? WHERE citizenid = ?',
        { Util.Encode(money), citizenid })
end

--- Debit a personal wallet. Returns true on success.
local function Debit(source, citizenid, kind, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end

    if Util.TryExport(Core, 'RemoveMoney', source, kind, amount, reason) ~= nil then
        return true
    end

    local money = Wallet(source, citizenid)
    if (money[kind] or 0) < amount then return false end
    money[kind] = money[kind] - amount
    return WriteWallet(citizenid, money) > 0
end

--- Credit a personal wallet. Returns true on success.
local function Credit(source, citizenid, kind, amount, reason)
    amount = math.floor(tonumber(amount) or 0)
    if amount <= 0 then return false end

    if Util.TryExport(Core, 'AddMoney', source, kind, amount, reason) ~= nil then
        return true
    end

    local money = Wallet(source, citizenid)
    local cap = (kind == 'cash') and 50000 or 2500000
    money[kind] = math.min((money[kind] or 0) + amount, cap)
    return WriteWallet(citizenid, money) > 0
end

local function CharacterName(source)
    local cid = CitizenId(source)
    if not cid then return 'Unknown' end
    return DB.CharacterName(cid)
end

--- Members of a family who are online right now.
local function OnlineMembers(familyId)
    local out = {}
    for _, row in ipairs(DB.FamilyCitizenIds(familyId)) do
        local src = Util.TryExport(Core, 'GetSourceByCitizenId', row.citizenid)
        if src and tonumber(src) and tonumber(src) > 0 then
            out[#out + 1] = { source = tonumber(src), citizenid = row.citizenid }
        end
    end
    return out
end

--- Authorisation for every handler: who is speaking, which family do
--- they really belong to, and what rank does the DB say they hold.
local function Authorise(source, permission, minAmount)
    local citizenid = CitizenId(source)
    if not citizenid then return nil, 'Not identified' end

    local family = DB.FamilyForCitizen(citizenid)
    if not family then return nil, 'You are not in a family' end

    local rank = tonumber(family.member_rank) or 0
    if permission and not Util.Can(rank, permission) then
        return nil, ('Rank %s cannot do that'):format(Util.RankTitle(rank))
    end

    if minAmount then
        amount = math.floor(tonumber(minAmount) or 0)
        if amount <= 0 then return nil, 'Invalid amount' end
        if amount > 250000 then return nil, 'Amount exceeds the transaction limit' end
    end

    return {
        citizenid = citizenid,
        family = family,
        familyId = tonumber(family.id),
        rank = rank,
    }
end

-- ─── /createfamily <TAG> <name...> ────────────────────────────
RegisterCommand(Config.Commands.CreateFamily, function(source, args)
    if source == 0 then
        Notify(source, 'Console cannot own a family', 'error')
        return
    end
    if not Util.Throttle(('create:%d'):format(source), 1, 60) then
        Notify(source, 'Slow down', 'warning')
        return
    end

    if #args < 2 then
        Notify(source, 'Usage: /createfamily <TAG> <name>', 'info')
        return
    end

    local citizenid = CitizenId(source)
    if not citizenid then
        Notify(source, 'Could not identify you', 'error')
        return
    end

    if DB.FamilyForCitizen(citizenid) then
        Notify(source, 'You are already in a family', 'error')
        return
    end

    local okTag, tag = Util.ValidTag(args[1])
    if not okTag then
        Notify(source, tag, 'error')
        return
    end

    local name = Util.Clean(table.concat(args, ' ', 2), Config.Families.MaxNameLength)
    local okName, nameErr = Util.ValidFamilyName(name)
    if not okName then
        Notify(source, nameErr, 'error')
        return
    end

    if DB.FamilyByName(name) then
        Notify(source, 'That family name is taken', 'error')
        return
    end

    local cost = Config.Families.CreationCost
    local money = Wallet(source, citizenid)
    if money.cash < cost then
        Notify(source, ('You need %s cash'):format(Util.Money(cost)), 'error')
        return
    end

    if not Debit(source, citizenid, 'cash', cost, 'family creation') then
        Notify(source, 'Payment failed', 'error')
        return
    end

    local colour = Config.Families.DefaultColour or '#FFFFFF'
    local job = Util.TryExport(Core, 'GetJob', source)
    if job and job.name then
        colour = GangColourOf(job.name) or colour
    end

    local familyId = DB.CreateFamily(name, citizenid, tag, colour, cost)
    if not familyId then
        Credit(source, citizenid, 'cash', cost, 'family creation refund')
        Notify(source, 'Failed to create the family', 'error')
        return
    end

    DB.AddMember(familyId, citizenid, Config.Families.MaxRank)
    DB.SetCharacterFamily(citizenid, familyId, Config.Families.MaxRank)
    DB.RecountMembers(familyId)
    DB.Execute('UPDATE grand_families SET vault_cap = ? WHERE id = ? AND vault_cap = 0',
        { Config.Families.DefaultVaultCap, familyId })
    DB.Activity(familyId, citizenid, 'create', ('Created "%s" [%s]'):format(name, tag))

    Notify(source, ('Family "%s" founded. You are the %s.'):format(
        name, Util.RankTitle(Config.Families.MaxRank)), 'success')
    Families.Log('info', ('%s founded family %s (id %d)'):format(
        CharacterName(source), name, familyId))
    PushFamily(source, familyId)
end, false)

-- Gang colours kept in sync with grand_gangs / grand_core.
function GangColourOf(jobName)
    local map = {
        ballas = '#8E24AA', vagos = '#1E88E5', lostmc = '#FDD835',
        marabunta = '#FB8C00', hood = '#43A047', cartel = '#D81B60',
    }
    return map[tostring(jobName):lower()]
end

--- Pushes the caller's family state to their client.
function PushFamily(source, familyId)
    local citizenid = CitizenId(source)
    if not citizenid then return end

    local family = DB.FamilyForCitizen(citizenid)
    if family and tonumber(family.id) == tonumber(familyId or family.id) then
        TriggerClientEvent('grand_families:client:FamilyUpdated', source,
            Bridge.PublicFamily(family))
    elseif not familyId then
        TriggerClientEvent('grand_families:client:FamilyUpdated', source, nil)
    end
end

-- ─── /family <subcommand> ─────────────────────────────────────
RegisterCommand(Config.Commands.Family, function(source, args)
    if source == 0 then return end
    if not Util.Throttle(('fam:%d'):format(source), 8, 10) then return end

    local actor, err = Authorise(source, nil)
    if not actor then
        Notify(source, err or 'You are not in a family', 'info')
        return
    end

    local sub = args[1] and tostring(args[1]):lower() or 'info'
    local fam = actor.family
    local id = actor.familyId

    if sub == 'info' then
        local readout = Bridge.GetIncomeReadout(id)
        Notify(source, ('%s [%s] - %s members, %d turfs, vault %s, income %s/hr'):format(
            fam.name, fam.tag or '----', fam.active_members or 0, readout.turfs,
            Util.Money(readout.vault), Util.Money(readout.hourly)), 'info')

    elseif sub == 'vault' then
        if not Util.Can(actor.rank, 'canSeeVault') then
            Notify(source, 'Only made men can see the vault', 'error')
            return
        end
        local readout = Bridge.GetIncomeReadout(id)
        Notify(source, ('Vault %s (cap %s). Turfs %d, solar %d, oil %d'):format(
            Util.Money(readout.vault), Util.Money(readout.cap or 0), readout.turfs,
            readout.solarPanels, readout.oilWells), 'info')

    elseif sub == 'members' then
        local roster = Bridge.GetRoster(id)
        Notify(source, ('%s has %d members:'):format(fam.name, #roster), 'info')
        for i, member in ipairs(roster) do
            if i <= 12 then
                TriggerClientEvent('chat:addMessage', source, {
                    color = { 255, 255, 255 }, multiline = false,
                    args = { '', ('%s - %s (%s)'):format(
                        member.name, member.rankTitle, member.citizenid) },
                })
            elseif i == 13 then
                Notify(source, ('... and %d more'):format(#roster - 12), 'info')
                break
            end
        end

    elseif sub == 'turfs' then
        local turfs = Bridge.GetFamilyTurfPayload(id)
        if #turfs == 0 then
            Notify(source, 'Your family holds no turf', 'info')
            return
        end
        Notify(source, ('Holding %d turf(s):'):format(#turfs), 'info')
        for _, turf in ipairs(turfs) do
            TriggerClientEvent('chat:addMessage', source, {
                color = { 255, 255, 255 }, multiline = false,
                args = { '', ('%s (tier %d, %dm radius)'):format(
                    turf.name, turf.tier, math.floor(turf.radius)) },
            })
        end

    elseif sub == 'invite' then
        if not Util.Can(actor.rank, 'canInvite') then
            Notify(source, 'You cannot invite', 'error')
            return
        end
        local target = tonumber(args[2])
        if not target or target < 1 or target > 64000 then
            Notify(source, 'Usage: /family invite [server id]', 'info')
            return
        end
        if not Util.Throttle(('invite:%d'):format(source), 4, 30) then
            Notify(source, 'Too many invites', 'warning')
            return
        end

        local targetCid = CitizenId(target)
        if not targetCid then
            Notify(source, 'That player is not identified', 'error')
            return
        end
        if DB.FamilyForCitizen(targetCid) then
            Notify(source, 'They already have a family', 'error')
            return
        end
        local roster = DB.Roster(id)
        if #roster >= Config.Families.MaxMembers then
            Notify(source, 'The family is full', 'error')
            return
        end

        DB.AddInvite(id, targetCid, actor.citizenid)
        TriggerClientEvent('grand_families:client:InvitationReceived', target,
            id, fam.name, fam.tag or '----', CharacterName(source))
        Notify(source, ('Invited %s'):format(CharacterName(target)), 'success')
        Notify(target, ('%s invited you to join %s. Run /acceptinvite %d'):format(
            CharacterName(source), fam.name, id), 'success')
        DB.Activity(id, actor.citizenid, 'invite', ('Invited %s'):format(targetCid))

    elseif sub == 'kick' then
        if not Util.Can(actor.rank, 'canKick') then
            Notify(source, 'You cannot kick', 'error')
            return
        end
        local targetCid = Util.Clean(args[2], 16)
        if targetCid == '' or targetCid == actor.citizenid then
            Notify(source, 'Usage: /family kick [citizenid]', 'info')
            return
        end

        local target = DB.Membership(id, targetCid)
        if not target then
            Notify(source, 'Not a member of your family', 'error')
            return
        end
        if (tonumber(target.rank) or 1) >= actor.rank then
            Notify(source, 'You cannot kick an equal or a superior', 'error')
            return
        end

        DB.LeaveMember(id, targetCid)
        DB.SetCharacterFamily(targetCid, nil, 0)
        DB.RecountMembers(id)
        DB.Activity(id, actor.citizenid, 'kick', ('Kicked %s'):format(targetCid))

        local targetSrc = Util.TryExport(Core, 'GetSourceByCitizenId', targetCid)
        if targetSrc and tonumber(targetSrc) then
            Notify(tonumber(targetSrc), ('You were removed from %s'):format(fam.name), 'error')
            TriggerClientEvent('grand_families:client:FamilyUpdated', tonumber(targetSrc), nil)
        end
        Notify(source, ('Kicked %s'):format(targetCid), 'success')

    elseif sub == 'setrank' then
        local targetCid = Util.Clean(args[2], 16)
        local newRank = tonumber(args[3])
        if targetCid == '' or not newRank then
            Notify(source, ('Usage: /family setrank [citizenid] [1-%d]'):format(
                Config.Families.MaxRank), 'info')
            return
        end

        newRank = Util.Rank(newRank)
        local target = DB.Membership(id, targetCid)
        if not target then
            Notify(source, 'Not a member of your family', 'error')
            return
        end
        if targetCid == fam.leader_citizenid then
            Notify(source, 'The leader rank cannot be changed', 'error')
            return
        end

        local isLeader = actor.citizenid == fam.leader_citizenid
        local allowed, why = Util.CanManageRank(actor.rank, tonumber(target.rank) or 1, isLeader)
        if not allowed then
            Notify(source, why, 'error')
            return
        end
        if newRank >= actor.rank and not isLeader then
            Notify(source, 'You cannot grant a rank at or above your own', 'error')
            return
        end

        DB.SetRank(id, targetCid, newRank)
        DB.SetCharacterFamily(targetCid, id, newRank)
        DB.Activity(id, actor.citizenid, 'setrank',
            ('%s: %d -> %d'):format(targetCid, tonumber(target.rank) or 1, newRank))

        Notify(source, ('%s is now %s'):format(targetCid, Util.RankTitle(newRank)), 'success')
        local targetSrc = Util.TryExport(Core, 'GetSourceByCitizenId', targetCid)
        if targetSrc and tonumber(targetSrc) then
            Notify(tonumber(targetSrc), ('Your rank is now %s'):format(Util.RankTitle(newRank)), 'success')
            PushFamily(tonumber(targetSrc), id)
        end

    elseif sub == 'leave' then
        if actor.citizenid == fam.leader_citizenid then
            Notify(source, ('The leader must run /%s YES'):format(Config.Commands.Dissolve), 'error')
            return
        end
        DB.LeaveMember(id, actor.citizenid)
        DB.SetCharacterFamily(actor.citizenid, nil, 0)
        DB.RecountMembers(id)
        DB.Activity(id, actor.citizenid, 'leave', 'Left the family')
        Notify(source, ('You left %s'):format(fam.name), 'info')
        TriggerClientEvent('grand_families:client:FamilyUpdated', source, nil)

    elseif sub == 'history' then
        if not Util.Can(actor.rank, 'canSeeVault') then
            Notify(source, 'No vault access', 'error')
            return
        end
        local rows = DB.VaultHistory(id, 12)
        Notify(source, ('Last %d vault movements:'):format(#rows), 'info')
        for _, row in ipairs(rows) do
            local signed = row.transaction_type == 'withdrawal' and -1 or 1
            TriggerClientEvent('chat:addMessage', source, {
                color = { 200, 200, 200 }, multiline = false,
                args = { '', ('%s %s%s -> %s'):format(
                    tostring(row.timestamp):sub(1, 16), signed < 0 and '-' or '+',
                    Util.Money(row.amount):gsub('%$', ''), Util.Money(row.balance_after)) },
            })
        end

    else
        Notify(source, ('Try: info, vault, members, turfs, invite, kick, setrank, leave, history'), 'info')
    end
end, false)

-- ─── /acceptinvite <family id> ────────────────────────────────
RegisterCommand(Config.Commands.Accept, function(source, args)
    if source == 0 then return end

    local actor = CitizenId(source)
    if not actor then return end

    local familyId = tonumber(args[1])
    if not familyId then
        Notify(source, ('Usage: /%s <family id>'):format(Config.Commands.Accept), 'info')
        return
    end

    if DB.FamilyForCitizen(actor) then
        Notify(source, 'You are already in a family', 'error')
        return
    end

    local invite = DB.HasInvite(familyId, actor)
    if not invite then
        Notify(source, 'That invitation is not valid any more', 'error')
        return
    end

    local family = DB.Family(familyId)
    if not family then
        DB.ClearInvite(familyId, actor)
        Notify(source, 'That family no longer exists', 'error')
        return
    end

    local roster = DB.Roster(familyId)
    if #roster >= Config.Families.MaxMembers then
        Notify(source, 'That family is full', 'error')
        return
    end

    DB.ClearInvite(familyId, actor)
    DB.AddMember(familyId, actor, 1)
    DB.SetCharacterFamily(actor, familyId, 1)
    DB.RecountMembers(familyId)
    DB.Activity(familyId, actor, 'join', 'Accepted an invitation')

    Notify(source, ('You joined %s as %s'):format(family.name, Util.RankTitle(1)), 'success')
    TriggerClientEvent('grand_families:client:FamilyUpdated', source,
        Bridge.PublicFamily(DB.FamilyForCitizen(actor)))

    for _, member in ipairs(OnlineMembers(familyId)) do
        if member.citizenid ~= actor then
            Notify(member.source, ('%s joined the family'):format(CharacterName(source)), 'info')
        end
    end
end, false)

RegisterCommand(Config.Commands.Turfs, function(source)
    if source == 0 then return end
    TriggerClientEvent('grand_families:client:ShowTurfs', source)
end, false)

-- ─── /deposit <amount> ────────────────────────────────────────
RegisterCommand(Config.Commands.Deposit, function(source, args)
    if source == 0 then return end
    if not Util.Throttle(('dep:%d'):format(source), 6, 15) then return end

    local actor, err = Authorise(source, 'canDeposit', tonumber(args[1]))
    if not actor then
        Notify(source, err, 'error')
        return
    end

    local amount = math.floor(tonumber(args[1]) or 0)
    if amount < (Config.Families.MinVaultDeposit or 100) then
        Notify(source, ('Minimum deposit is %s'):format(
            Util.Money(Config.Families.MinVaultDeposit)), 'error')
        return
    end

    local money = Wallet(source, actor.citizenid)
    if money.cash < amount then
        Notify(source, ('You only carry %s cash'):format(Util.Money(money.cash)), 'error')
        return
    end

    if not Debit(source, actor.citizenid, 'cash', amount, 'family vault deposit') then
        Notify(source, 'Could not take your cash', 'error')
        return
    end

    local after = DB.MoveVault(actor.familyId, amount, 'deposit', actor.citizenid,
        ('Deposit by %s'):format(CharacterName(source)))
    if not after then
        Credit(source, actor.citizenid, 'cash', amount, 'vault deposit refund')
        Notify(source, 'The vault refused that deposit', 'error')
        return
    end

    DB.AddMemberWallet(actor.familyId, actor.citizenid, 'total_deposits', amount)
    DB.Activity(actor.familyId, actor.citizenid, 'deposit', Util.Money(amount))
    Notify(source, ('Deposited %s - the vault holds %s'):format(
        Util.Money(amount), Util.Money(after)), 'success')
    Bridge.Broadcast(actor.familyId, 'grand_families:client:VaultChanged', after)
end, false)

-- ─── /withdraw <amount> ───────────────────────────────────────
RegisterCommand(Config.Commands.Withdraw, function(source, args)
    if source == 0 then return end
    if not Util.Throttle(('wd:%d'):format(source), 6, 15) then return end

    local actor, err = Authorise(source, 'canWithdraw', tonumber(args[1]))
    if not actor then
        Notify(source, err, 'error')
        return
    end

    local amount = math.floor(tonumber(args[1]) or 0)
    local money = Wallet(source, actor.citizenid)
    if money.cash + amount > 50000 then
        Notify(source, 'That would overflow your cash on hand', 'error')
        return
    end

    local after = DB.MoveVault(actor.familyId, -amount, 'withdrawal', actor.citizenid,
        ('Withdrawal by %s'):format(CharacterName(source)))
    if not after then
        Notify(source, 'The vault does not hold that much', 'error')
        return
    end

    if not Credit(source, actor.citizenid, 'cash', amount, 'family vault withdrawal') then
        DB.MoveVault(actor.familyId, amount, 'refund', actor.citizenid, 'withdrawal rollback')
        Notify(source, 'Could not pay you, the vault was restored', 'error')
        return
    end

    DB.AddMemberWallet(actor.familyId, actor.citizenid, 'total_withdrawals', amount)
    DB.Activity(actor.familyId, actor.citizenid, 'withdraw', Util.Money(amount))
    Notify(source, ('Withdrew %s - the vault holds %s'):format(
        Util.Money(amount), Util.Money(after)), 'success')
    Bridge.Broadcast(actor.familyId, 'grand_families:client:VaultChanged', after)
end, false)

-- ─── /dissolve YES ────────────────────────────────────────────
RegisterCommand(Config.Commands.Dissolve, function(source, args)
    if source == 0 then return end

    local actor, err = Authorise(source, 'canDissolveFamily')
    if not actor then
        Notify(source, err, 'error')
        return
    end
    if tostring(args[1]):upper() ~= 'YES' then
        Notify(source, ('Type /%s YES to erase %s for good'):format(
            Config.Commands.Dissolve, actor.family.name), 'warning')
        return
    end

    local members = OnlineMembers(actor.familyId)
    local name = actor.family.name

    DB.Dissolve(actor.familyId)
    Families.Log('warn', ('%s dissolved family %s (id %d)'):format(
        CharacterName(source), name, actor.familyId))

    for _, member in ipairs(members) do
        Notify(member.source, ('%s has been dissolved'):format(name), 'error')
        TriggerClientEvent('grand_families:client:FamilyUpdated', member.source, nil)
    end
end, false)

-- ─── /familyadmin ─────────────────────────────────────────────
local function IsAdmin(source)
    return IsPlayerAceAllowed(source, 'grand.families.admin')
        or IsPlayerAceAllowed(source, 'group.admin')
end

RegisterCommand(Config.Commands.Admin, function(source, args)
    if not IsPlayerAceAllowed(source == 0 and 'console' or source, 'grand.families.admin')
        and source ~= 0 then
        if source ~= 0 then Notify(source, 'Not authorised', 'error') end
        return
    end

    local sub = args[1] and tostring(args[1]):lower() or 'help'

    if sub == 'list' then
        local rows = DB.ListFamilies(tonumber(args[2]) or 25)
        for _, row in ipairs(rows) do
            print(('[family %d] %s [%s] vault %s, %d members, %d turfs, leader %s'):format(
                row.id, row.name, row.tag or '----', Util.Money(row.balance),
                row.active_members or 0, row.total_turfs or 0, row.leader_citizenid))
        end

    elseif sub == 'grant' then
        local id = tonumber(args[2])
        local amount = tonumber(args[3])
        if not id or not amount then
            print('Usage: /familyadmin grant <family id> <amount>')
            return
        end
        if Bridge.AddVault(id, amount, 'admin grant') then
            print(('Granted %s to family %d'):format(Util.Money(amount), id))
        else
            print('Grant refused')
        end

    elseif sub == 'setleader' then
        local id = tonumber(args[2])
        local cid = Util.Clean(args[3], 16)
        if not id or cid == '' then
            print('Usage: /familyadmin setleader <family id> <citizenid>')
            return
        end
        DB.UpdateFamilyRow(id, 'leader_citizenid', cid)
        DB.SetRank(id, cid, Config.Families.MaxRank)
        DB.SetCharacterFamily(cid, id, Config.Families.MaxRank)
        print(('Family %d now led by %s'):format(id, cid))

    elseif sub == 'disband' then
        local id = tonumber(args[2])
        if not id then
            print('Usage: /familyadmin disband <family id>')
            return
        end
        DB.Dissolve(id)
        print(('Family %d disbanded'):format(id))

    elseif sub == 'warclear' then
        DB.AbandonOrphanWars()
        print('All open turf wars aborted')

    else
        print('Usage: /familyadmin list | grant | setleader | disband | warclear')
    end
end, false)

-- ─── Net events (source is the implicit global, never an arg) ─
RegisterNetEvent('grand_families:server:PlayerLoaded', function()
    local source = source
    local citizenid = CitizenId(source)
    if not citizenid then return end

    local family = DB.FamilyForCitizen(citizenid)
    if family then
        TriggerClientEvent('grand_families:client:FamilyUpdated', source,
            Bridge.PublicFamily(family))
        TriggerClientEvent('grand_families:client:TurfSnapshot', source,
            Bridge.GetFamilyTurfPayload(family.id))
    else
        -- self-heal a stale denormalised pointer
        if DB.Character(citizenid) then
            DB.SetCharacterFamily(citizenid, nil, 0)
        end
    end
end)

RegisterNetEvent('grand_families:server:Refresh', function()
    local source = source
    PushFamily(source)
end)

-- Turf presence reporting for the grand_gangs war engine: the gang
-- resource asks who of a family is standing in a zone right now.
RegisterNetEvent('grand_families:server:PresenceReport', function(familyId)
    local source = source
    local id = tonumber(familyId)
    if not id or not Util.Throttle(('presence:%d'):format(source), 4, 5) then return end

    local citizenid = CitizenId(source)
    if not citizenid or not DB.Membership(id, citizenid) then return end

    TriggerEvent('grand_gangs:server:Presence', id, citizenid,
        GetEntityCoords(GetPlayerPed(source)))
end)

-- ─── Exports ──────────────────────────────────────────────────
Bridge.Register()

exports('FamilyOf', function(citizenid)
    return DB.FamilyForCitizen(Util.Clean(citizenid, 16))
end)

exports('AllFamilies', function()
    return DB.ListFamilies(0)
end)

exports('FamilyName', function(familyId)
    local row = DB.Family(tonumber(familyId))
    return row and row.name or nil
end)

exports('MemberRankOf', function(citizenid)
    local row = DB.FamilyForCitizen(Util.Clean(citizenid, 16))
    return row and (tonumber(row.member_rank) or 0) or 0
end)

exports('NotifyFamily', function(familyId, message, kind)
    Bridge.Broadcast(tonumber(familyId), 'grand_families:client:FamilyMessage',
        tostring(message), kind or 'info')
end)

-- ─── Boot ─────────────────────────────────────────────────────
AddEventHandler('onResourceStart', function(resourceName)
    if resourceName ~= RESOURCE then return end

    CreateThread(function()
        Wait(500)

        if not DB.CreateSchema() then
            Families.Log('warn', 'Schema bootstrap skipped or failed - verify sql/schema.sql')
        end

        DB.AbandonOrphanWars()
        DB.PruneInvites()

        Income.StartLoops()

        Families.Log('info', ('Grand Families online - %d families on record'):format(
            #DB.ListFamilies(0)))
    end)
end)

AddEventHandler('onResourceStop', function(resourceName)
    if resourceName ~= RESOURCE then return end
    Income.Stop()
    Families.Log('info', 'Grand Families stopped')
end)

-- Keep the denormalised pointer honest when grand_core loads a char.
RegisterNetEvent('grand_core:server:PlayerLoaded', function()
    local src = source
    Wait(250)
    TriggerClientEvent('grand_families:server:PlayerLoaded', src)
    TriggerServerEvent('grand_families:server:PlayerLoaded')
end)

CreateThread(function()
    while true do
        Wait(Config.Invites.pruneSeconds * 1000)
        DB.PruneInvites()
    end
end)

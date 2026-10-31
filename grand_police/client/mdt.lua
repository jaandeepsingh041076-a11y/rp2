-- ─────────────────────────────────────────────────────────────
--  resources/[grand_systems]/grand_police/client/mdt.lua
--  Renders MDT responses as formatted chat blocks. All queries
--  are server-side; this file only displays structured results.
-- ─────────────────────────────────────────────────────────────

PoliceClient = PoliceClient or {}
local C = PoliceClient
C.Mdt = C.Mdt or {}

local function header(title, colour)
    TriggerEvent('chat:addMessage', {
        color = colour or { 120, 180, 255 },
        multiline = true,
        args = { 'MDT', ('=== %s ==='):format(tostring(title)) },
    })
end

local function line(text, colour)
    TriggerEvent('chat:addMessage', {
        color = colour or { 220, 225, 240 },
        args = { '', tostring(text) },
    })
end

local function block(title, lines, colour)
    header(title, colour)
    local shown = 0
    for _, text in ipairs(lines or {}) do
        line(text)
        shown = shown + 1
        if shown >= 20 then
            line('... output truncated')
            break
        end
    end
end

-- ─── Profile ─────────────────────────────────────────────────
RegisterNetEvent('grand_police:client:MdtProfile', function(profile)
    if not profile then return end

    local lines = {
        ('Name: %s'):format(tostring(profile.name)),
        ('Citizen: %s'):format(tostring(profile.citizenid)),
        ('Status: %s, wanted %d*'):format(profile.online and 'ONLINE' or 'offline', tonumber(profile.wanted) or 0),
        ('Job: %s (grade %d)'):format(tostring(profile.job), tonumber(profile.jobGrade) or 0),
        ('Unpaid fines: %s'):format(PoliceUtil.Money(profile.unpaid or 0)),
        ('Warrants: %d | Sentences: %d | Licences: %d | Evidence: %d'):format(
            #(profile.warrants or {}), #(profile.sentences or {}),
            #(profile.licences or {}), #(profile.evidence or {})),
    }

    if profile.record and profile.record.charges and profile.record.charges ~= '' then
        lines[#lines + 1] = ('Charges: %s'):format(tostring(profile.record.charges):sub(1, 180))
    end

    for _, warrant in ipairs(profile.warrants or {}) do
        lines[#lines + 1] = ('WARRANT #%s: %s (%s)'):format(
            tostring(warrant.id), tostring(warrant.reason), tostring(warrant.offence or 'general'))
    end

    for _, fine in ipairs(profile.fines or {}) do
        if not fine.paid or tonumber(fine.paid) == 0 then
            lines[#lines + 1] = ('FINE #%s: %s - %s'):format(
                tostring(fine.id), PoliceUtil.Money(fine.amount), tostring(fine.reason or fine.offence))
        end
    end

    block(('PROFILE: %s'):format(tostring(profile.name)), lines)
end)

-- ─── Search ──────────────────────────────────────────────────
RegisterNetEvent('grand_police:client:MdtSearch', function(query, results)
    if not results or #results == 0 then
        PoliceUtil.Notify(('No records for "%s"'):format(tostring(query)), 'info')
        return
    end

    local lines = {}
    for _, row in ipairs(results) do
        lines[#lines + 1] = ('%s | %s | wanted %d* | %s'):format(
            tostring(row.citizenid), tostring(row.name or 'unknown'),
            tonumber(row.wanted) or 0, tostring(row.updated or ''))
    end
    block(('SEARCH: %s (%d)'):format(tostring(query), #results), lines)
end)

-- ─── Warrants ────────────────────────────────────────────────
RegisterNetEvent('grand_police:client:MdtWarrants', function(rows)
    if not rows or #rows == 0 then
        PoliceUtil.Notify('No active warrants', 'info')
        return
    end

    local lines = {}
    for _, row in ipairs(rows) do
        lines[#lines + 1] = ('#%s %s (%s) - %s | by %s'):format(
            tostring(row.id), tostring(row.name or 'unknown'), tostring(row.citizenid),
            tostring(row.reason), tostring(row.officer_name or '?'))
    end
    block(('ACTIVE WARRANTS (%d)'):format(#rows), lines, { 255, 170, 120 })
end)

-- ─── BOLO ────────────────────────────────────────────────────
RegisterNetEvent('grand_police:client:MdtBolos', function(rows)
    if not rows or #rows == 0 then
        PoliceUtil.Notify('No active BOLOs', 'info')
        return
    end

    local lines = {}
    for _, row in ipairs(rows) do
        lines[#lines + 1] = ('#%s %s %s - %s'):format(
            tostring(row.id), tostring(row.name or row.plate or 'unknown'),
            tostring(row.citizenid or ''), tostring(row.reason))
    end
    block(('ACTIVE BOLOS (%d)'):format(#rows), lines, { 255, 200, 120 })
end)

-- ─── Recent records ──────────────────────────────────────────
RegisterNetEvent('grand_police:client:MdtRecent', function(rows)
    if not rows or #rows == 0 then
        PoliceUtil.Notify('No recent records', 'info')
        return
    end

    local lines = {}
    for _, row in ipairs(rows) do
        lines[#lines + 1] = ('%s | %s | wanted %d*'):format(
            tostring(row.citizenid), tostring(row.name or 'unknown'),
            tonumber(row.wanted_level) or 0)
    end
    block('RECENT RECORDS', lines)
end)

-- ─── Stats ───────────────────────────────────────────────────
RegisterNetEvent('grand_police:client:MdtStats', function(stats)
    if not stats then return end

    local lines = {
        ('Active warrants: %d'):format(tonumber(stats.warrants) or 0),
        ('Unpaid fines: %d (%s)'):format(
            tonumber(stats.unpaid_fines) or 0, PoliceUtil.Money(stats.unpaid_value or 0)),
        ('Inmates: %d | Open calls: %d'):format(
            tonumber(stats.inmates) or 0, tonumber(stats.calls) or 0),
        ('On duty: %d police, %d EMS'):format(
            tonumber(stats.onDuty) or 0, tonumber(stats.emsOnDuty) or 0),
    }

    for _, row in ipairs(stats.roster or {}) do
        lines[#lines + 1] = ('%s | %s | grade %d | %s'):format(
            tostring(row.name or row.citizenid), tostring(row.job),
            tonumber(row.grade) or 0, tostring(row.station or '?'))
    end

    block('DEPARTMENT STATS', lines)
end)

-- ─── Wanted board ────────────────────────────────────────────
RegisterNetEvent('grand_police:client:MdtWanted', function(board)
    if not board or #board == 0 then
        PoliceUtil.Notify('Nobody is wanted right now', 'info')
        return
    end

    local lines = {}
    for _, entry in ipairs(board) do
        lines[#lines + 1] = ('%d* %s (%s) - %s'):format(
            tonumber(entry.stars) or 0, tostring(entry.name or 'unknown'),
            tostring(entry.citizenid), tostring(entry.reason or 'no reason'))
    end
    block(('WANTED BOARD (%d)'):format(#board), lines, { 255, 120, 120 })
end)

-- ─── Traffic stops ───────────────────────────────────────────
RegisterNetEvent('grand_police:client:MdtStops', function(rows)
    if not rows or #rows == 0 then
        PoliceUtil.Notify('No active traffic stops', 'info')
        return
    end

    local lines = {}
    for _, row in ipairs(rows) do
        lines[#lines + 1] = ('#%s %s | %s | %s'):format(
            tostring(row.id), tostring(row.driver_name or row.driver_citizenid),
            tostring(row.plate or 'no plate'), tostring(row.reason or 'stop'))
    end
    block(('ACTIVE STOPS (%d)'):format(#rows), lines, { 180, 255, 180 })
end)

-- ─── Notices / stop / breathalyzer ──────────────────────────
RegisterNetEvent('grand_police:client:MdtNotice', function(message, kind)
    PoliceUtil.Notify(message, kind or 'info')
end)

RegisterNetEvent('grand_police:client:StopLogged', function(id, targetSrc, plate)
    PoliceUtil.Notify(('Stop #%s logged%s. /trafficstop to close.'):format(
        tostring(id), plate and (' (' .. plate .. ')') or ''), 'success')
end)

RegisterNetEvent('grand_police:client:Breathalyzer', function(targetSrc, bac, over)
    TriggerEvent('chat:addMessage', {
        color = over and { 255, 90, 90 } or { 120, 230, 140 },
        multiline = true,
        args = { 'BREATHALYZER', ('Player %s: %.3f BAC - %s'):format(
            tostring(targetSrc), tonumber(bac) or 0, over and 'OVER THE LIMIT' or 'within limits') },
    })
end)

-- ─── MDT help fallback (server owns /mdt) ────────────────────
RegisterCommand('mdthelp', function()
    TriggerEvent('chat:addMessage', {
        color = { 120, 180, 255 }, multiline = true,
        args = { 'MDT', table.concat({
            '/mdt search <name|cid>',
            '/mdt profile <id|cid>',
            '/mdt recent',
            '/mdt stats',
            '/mdt warrants',
            '/mdt bolos',
            '/mdt wanted',
            '/mdt stops',
        }, '\n') },
    })
end, false)

return C.Mdt

-- ─────────────────────────────────────────────────────────────
--  grand_items: data/items.lua
--  Grand RP Complete Items & Consumables Catalog
-- ─────────────────────────────────────────────────────────────

GrandItems = {
    -- FOOD & DRINK ITEMS (Exact Grand RP Consumables)
    ["burger_shot_bleeder"] = {
        name = "burger_shot_bleeder",
        label = "Bleeder Burger",
        weight = 250,
        type = "item",
        image = "https://raw.githubusercontent.com/overextended/ox_inventory/main/web/images/burger.png",
        unique = false,
        useable = true,
        shouldClose = true,
        hunger = 35,
        thirst = 0,
        description = "Classic Burger Shot beef burger with cheese and special sauce."
    },
    ["burger_shot_moneyshot"] = {
        name = "burger_shot_moneyshot",
        label = "Money Shot Burger",
        weight = 350,
        type = "item",
        image = "https://raw.githubusercontent.com/overextended/ox_inventory/main/web/images/burger.png",
        unique = false,
        useable = true,
        shouldClose = true,
        hunger = 60,
        thirst = -5,
        description = "Triple patty monster burger for true street hustlers."
    },
    ["fries"] = {
        name = "fries",
        label = "French Fries",
        weight = 150,
        type = "item",
        image = "https://raw.githubusercontent.com/overextended/ox_inventory/main/web/images/burger.png",
        unique = false,
        useable = true,
        shouldClose = true,
        hunger = 20,
        thirst = -5,
        description = "Crispy golden salted fries."
    },
    ["water_bottle"] = {
        name = "water_bottle",
        label = "Mineral Water",
        weight = 500,
        type = "item",
        image = "https://raw.githubusercontent.com/overextended/ox_inventory/main/web/images/water.png",
        unique = false,
        useable = true,
        shouldClose = true,
        hunger = 0,
        thirst = 40,
        description = "Chilled pure natural mountain spring water."
    },
    ["ecola"] = {
        name = "ecola",
        label = "eCola Can",
        weight = 350,
        type = "item",
        image = "https://raw.githubusercontent.com/overextended/ox_inventory/main/web/images/cola.png",
        unique = false,
        useable = true,
        shouldClose = true,
        hunger = 5,
        thirst = 35,
        description = "Deliciously infectious caffeinated soda."
    },
    ["sprunk"] = {
        name = "sprunk",
        label = "Sprunk Can",
        weight = 350,
        type = "item",
        image = "https://raw.githubusercontent.com/overextended/ox_inventory/main/web/images/sprunk.png",
        unique = false,
        useable = true,
        shouldClose = true,
        hunger = 5,
        thirst = 35,
        description = "The essence of life. Lemon lime carbonate."
    },
    ["coffee"] = {
        name = "coffee",
        label = "Hot Espresso",
        weight = 200,
        type = "item",
        image = "https://raw.githubusercontent.com/overextended/ox_inventory/main/web/images/coffee.png",
        unique = false,
        useable = true,
        shouldClose = true,
        hunger = 0,
        thirst = 25,
        stamina_buff = 60, -- 60 seconds sprint buff
        description = "Freshly brewed dark roast espresso giving quick sprint energy."
    },

    -- GRAND RP FAMILY & PASSIVE INFRASTRUCTURE ITEMS
    ["solar_panel"] = {
        name = "solar_panel",
        label = "Industrial Solar Panel",
        weight = 15000,
        type = "item",
        image = "https://cdn-icons-png.flaticon.com/512/3104/3104879.png",
        unique = true,
        useable = true,
        shouldClose = true,
        description = "High-efficiency photovoltaic solar panel for family mansion roofs ($1,500/hr)."
    },
    ["oil_drill_bit"] = {
        name = "oil_drill_bit",
        label = "Diamond Oil Drill Bit",
        weight = 25000,
        type = "item",
        image = "https://cdn-icons-png.flaticon.com/512/2933/2933830.png",
        unique = true,
        useable = true,
        description = "Reinforced titanium bit required to install and maintain Family Oil Wells."
    },
    ["solar_battery_pack"] = {
        name = "solar_battery_pack",
        label = "Tesla Powerwall Cell",
        weight = 10000,
        type = "item",
        image = "https://cdn-icons-png.flaticon.com/512/657/657076.png",
        unique = false,
        useable = true,
        description = "Stores surplus solar energy for continuous night payouts."
    },
    ["crude_oil_barrel"] = {
        name = "crude_oil_barrel",
        label = "Crude Oil Barrel",
        weight = 50000,
        type = "item",
        image = "https://cdn-icons-png.flaticon.com/512/824/824239.png",
        unique = false,
        useable = false,
        description = "42-gallon steel drum of refined Texas sweet crude oil."
    },

    -- TOOLS & CRIME ITEMS
    ["repair_kit"] = {
        name = "repair_kit",
        label = "Advanced Repair Kit",
        weight = 2500,
        type = "item",
        image = "https://raw.githubusercontent.com/overextended/ox_inventory/main/web/images/repairkit.png",
        unique = false,
        useable = true,
        shouldClose = true,
        description = "Fixes flat tires and brings engine health back to 100%."
    },
    ["lockpick"] = {
        name = "lockpick",
        label = "Bobby Pin Lockpick",
        weight = 100,
        type = "item",
        image = "https://raw.githubusercontent.com/overextended/ox_inventory/main/web/images/lockpick.png",
        unique = false,
        useable = true,
        shouldClose = true,
        description = "Used to pick vehicle door locks or crack store registers."
    },
    ["handcuffs"] = {
        name = "handcuffs",
        label = "Steel Handcuffs",
        weight = 500,
        type = "item",
        image = "https://raw.githubusercontent.com/overextended/ox_inventory/main/web/images/handcuffs.png",
        unique = false,
        useable = true,
        shouldClose = true,
        description = "Law enforcement issue double-locking steel wrist restraints."
    },
    ["cuff_keys"] = {
        name = "cuff_keys",
        label = "Universal Cuff Key",
        weight = 50,
        type = "item",
        image = "https://raw.githubusercontent.com/overextended/ox_inventory/main/web/images/keys.png",
        unique = false,
        useable = true,
        shouldClose = true,
        description = "Standard key used to unlock police and civilian handcuffs."
    }
}

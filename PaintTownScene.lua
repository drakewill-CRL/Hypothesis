--Paint The Town  Mode
--Simplified area control mode: walk into a Cell10, claim it for your team.
--(Teams get assigned by the server randomly)
--auto-resets on a scheduled basis, can have multiple scoreboards/instances going.
local composer = require("composer")
local scene = composer.newScene()

require("UIParts")
require("database")
require("localNetwork")
require("dataTracker") -- replaced localNetwork for this scene

-- -----------------------------------------------------------------------------------
-- Code outside of the scene event functions below will only be executed ONCE unless
-- the scene is removed entirely (not recycled) via "composer.removeScene()"
-- -----------------------------------------------------------------------------------

local bigGrid = true

local cellCollection = {} -- show cell area data/image tiles
local CellTapSensors = {} -- Not detecting taps in this mode. This is the highlight layer.
local ctsGroup = display.newGroup()
ctsGroup.x = -8
ctsGroup.y = 10
-- color codes

local unvisitedCell = {0, 0} -- completely transparent
local visitedCell = {.529, .807, .921, .4} -- sky blue, 50% transparent
local selectedCell = {.8, .2, .2, .4} -- red, 50% transparent

local TeamColors = {}
TeamColors[1] = {1, 0, 0, .6}
TeamColors[2] = {0, 1, 0, .6}
TeamColors[3] = {.1, .605, .822, .6} --sky blue for team 3.

local timerResults = nil
local timerResultsScoreboard = nil
local PaintTownMapUpdateCountdown = 8 --wait this many loops over the main update before doing a network call. 
local firstRun = true

local locationText = ""
local scoreText = ""
local directionArrow = ""
local debugText = {}
local locationName = ""

local zoom = ""
local swapInstance = ""

local instanceID = 1 --1 is weekly, 2 is permanent
local arrowPainted = false

local function GetScoreboard()
    --local instanceID = "1"
    local url = serverURL .. "PaintTown/Scoreboard/" .. instanceID
    network.request(url, "GET", GetScoreboardListener)
    if (debug) then print("scoreboard request sent to " .. url) end
end

function GetScoreboardListener(event) --these listeners can't be local.
    if (debug) then  print("scoreboard listener fired") end
    if event.status == 200 then
        if (debug) then 
            print("got Scoreboard")
            print(event.response)
        end
        local results = Split(event.response, "|")
        local setText = ""
        --line 1 is instanceName#time.
        --every other line is teamName=Score, need to iterate those.
        setText = Split(results[1], "#")[1] .. "\n"
        for i = 2, #results do
            setText = setText .. results[i] .. "\n"
        end
        scoreText.text = setText
    end
    if (debug) then print("scoreboard text done") end
end

local function testDrift()
    if (os.time() % 2 == 0) then
        currentPlusCode = shiftCell(currentPlusCode, 1, 9) -- move north
    else
        currentPlusCode = shiftCell(currentPlusCode, 1, 10) -- move west
    end
end

local function ToggleZoom()
    bigGrid = not bigGrid
    local sceneGroup = scene.view
    timer.pause(timerResults)

    for i = 1, #cellCollection do cellCollection[i]:removeSelf() end
    for i = 1, #CellTapSensors do CellTapSensors[i]:removeSelf() end

    cellCollection = {}
    CellTapSensors = {}

    if (bigGrid) then
        CreateRectangleGrid(3, 320, 400, sceneGroup, cellCollection) -- rectangular Cell11 grid with map tiles
        CreateRectangleGrid(61, 16, 20, ctsGroup, CellTapSensors, "painttown") -- rectangular Cell11 grid with a color fill
        ctsGroup.x = -8
        ctsGroup.y = 10
    else
        CreateRectangleGrid(3, 160, 200, sceneGroup, cellCollection) -- rectangular Cell11 grid with map tiles
        CreateRectangleGrid(60, 8, 10, ctsGroup, CellTapSensors, "painttown") -- rectangular Cell11 grid  with a color fill
        ctsGroup.x = -4
        ctsGroup.y = 5
    end
    --Move these to the back first, so that the map tiles will be behind them.
    for square = 1, #CellTapSensors do
        -- check each spot based on current cell, modified by gridX and gridY
        CellTapSensors[square]:toBack()
    end

    for square = 1, #cellCollection do
        -- check each spot based on current cell, modified by gridX and gridY
        cellCollection[square]:toBack()
    end

    reorderUI()
    forceRedraw = true
    timer.resume(timerResults)
end

local function switchMode()
    if (instanceID == 1) then
        instanceID = 2
    else
        instanceID =1
    end
    scoreText.text = "Loading...."
    forceRedraw = true
    requestedPaintTownCells = {} --clears out the display cache
end

local function tintArrow(teamID)
    if (teamID == 1) then
        directionArrow:setFillColor(1, 0, 0, .5)
    elseif (teamID == 2) then
        directionArrow:setFillColor(0, 1, 0, .5)
    elseif (teamID == 3) then
        directionArrow:setFillColor(0, 0, 1, .5) 
    end
    arrowPainted = true
end

local function GoToSceneSelect()
    local options = {effect = "flip", time = 125}
    composer.gotoScene("SceneSelect", options)
end

local function UpdateLocalOptimized()
    -- This now needs to be 2 loops, because the cell tables are different sizes.
    -- First loop for map tiles
    -- Then loop for touch event rectangles.
    if (debugLocal) then print("start UpdateLocalOptimized") end
    if (currentPlusCode == "") then
        if timerResults == nil then
            timerResults = timer.performWithDelay(150, UpdateLocalOptimized, -1)
        end
        if (debugLocal) then print("skipping, no location.") end
        return
    end

    if (debug) then debugText.text = dump(lastLocationEvent) end

    local plusCodeNoPlus = removePlus(currentPlusCode)
    if (timerResults ~= nil) then timer.pause(timerResults) end
    local innerForceRedraw = forceRedraw or firstRun or (currentPlusCode:sub(1,8) ~= previousPlusCode:sub(1,8))
    firstRun = false
    forceRedraw = false
    if currentPlusCode ~= previousPlusCode then
        ClaimPaintTownCell(plusCodeNoPlus, tonumber(composer.getVariable("faction")))
    end
    previousPlusCode = currentPlusCode

    -- draw this place's name on screen, or an empty string if its not a place.
    local terrainInfo = LoadTerrainData(plusCodeNoPlus) -- terrainInfo is a whole row from the DB.
    locationName.text = terrainInfo[3]; --name
    if locationName.text == "" then
        locationName.text = typeNames[terrainInfo[4]] --area type name
    end

    PaintTownMapUpdateCountdown = PaintTownMapUpdateCountdown -1
    -- Step 1: set background MAC map tiles for the Cell8. Should be much simpler than old loop.
    if (innerForceRedraw == false) then -- none of this needs to get processed if we haven't moved and there's no new maptiles to refresh.
    for square = 1, #cellCollection do
        -- check each spot based on current cell, modified by gridX and gridY
        
        local thisSquaresPluscode = currentPlusCode
        thisSquaresPluscode = shiftCell(thisSquaresPluscode, cellCollection[square].gridX, 8)
        thisSquaresPluscode = shiftCell(thisSquaresPluscode, cellCollection[square].gridY, 7)
        cellCollection[square].pluscode = thisSquaresPluscode
        local plusCodeNoPlus = removePlus(thisSquaresPluscode):sub(1, 8)
        if (PaintTownMapUpdateCountdown == 0) then
            GetPaintTownMapData8(plusCodeNoPlus, instanceID)
            if (arrowPainted == false) then
                local teamID = factionID --tonumber(composer.getVariable("faction"))
                if (teamID == 0) then
                    GetTeamAssignment()
                else            
                    tintArrow(teamID)
                end
            end
        end
            GetMapData8(plusCodeNoPlus)
            local imageRequested = requestedMapTileCells[plusCodeNoPlus] -- read from DataTracker because we want to know if we can paint the cell or not.
            local imageExists = doesFileExist(plusCodeNoPlus .. "-11.png", system.CachesDirectory)
            if (imageRequested == nil) then -- or imageExists == 0 --if I check for 0, this is always nil? if I check for nil, this is true when images are present?
                imageExists = doesFileExist(plusCodeNoPlus .. "-11.png", system.CachesDirectory)
            end
            if (imageExists == false or imageExists == nil) then -- not sure why this is true when file is found and 0 when its not? -- or imageExists == 0
                 cellCollection[square].fill = {0, 0} -- required to make Solar2d actually update the texture.
                 GetMapTile8(plusCodeNoPlus)
            else
                cellCollection[square].fill = {0, 0} -- required to make Solar2d actually update the texture.
                local paint = {
                    type = "image",
                    filename = plusCodeNoPlus .. "-11.png",
                    baseDir = system.CachesDirectory
                }
                cellCollection[square].fill = paint
            end
        end
    end

    if (debug) then  print("done with map cells") end
    -- Step 2: set up event listener grid. These need Cell10s
    local baselinePlusCode = currentPlusCode:sub(1,8) .. "+FF"
    if (innerForceRedraw) then --Also no need to do all of this unless we shifted our Cell8 location.
    for square = 1, #CellTapSensors do
            CellTapSensors[square].fill = {0, 0}
            local thisSquaresPluscode = baselinePlusCode
            local shiftChar7 = math.floor(CellTapSensors[square].gridY / 20)
            local shiftChar8 = math.floor(CellTapSensors[square].gridX / 20)
            local shiftChar9 = math.floor(CellTapSensors[square].gridY % 20)
            local shiftChar10 = math.floor(CellTapSensors[square].gridX % 20)
            thisSquaresPluscode = shiftCell(thisSquaresPluscode, shiftChar7, 7)
            thisSquaresPluscode = shiftCell(thisSquaresPluscode, shiftChar8, 8)
            thisSquaresPluscode = shiftCell(thisSquaresPluscode, shiftChar9, 9)
            thisSquaresPluscode = shiftCell(thisSquaresPluscode, shiftChar10, 10)
            local idCheck = removePlus(thisSquaresPluscode)

            CellTapSensors[square].pluscode = thisSquaresPluscode
            if (requestedPaintTownCells[idCheck] ~= nil) then
                local teamIDThisSpace = requestedPaintTownCells[idCheck]
                CellTapSensors[square].fill = TeamColors[tonumber(teamIDThisSpace)]
            end
        end
    end

    if PaintTownMapUpdateCountdown == 0 then
        PaintTownMapUpdateCountdown = 8
    end

    if (timerResults ~= nil) then timer.resume(timerResults) end
    if (debugLocal) then print("grid done or skipped") end
    locationText.text = "Current location:" .. currentPlusCode
    timeText.text = "Current time:" .. os.date("%X")
    directionArrow.rotation = currentHeading

    local shift = CODE_ALPHABET_:find(currentPlusCode:sub(11, 11)) - 11
    local shift2 = CODE_ALPHABET_:find(currentPlusCode:sub(10, 10)) - 10
    if (bigGrid) then
        directionArrow.x = display.contentCenterX + (shift * 16)
        directionArrow.y = display.contentCenterY - (shift2 * 20)
    else
        directionArrow.x = display.contentCenterX + (shift * 4)
        directionArrow.y = display.contentCenterY - (shift2 * 5)
    end

    locationText:toFront()
    scoreText:toFront()
    timeText:toFront()
    directionArrow:toFront()
    locationName:toFront()
    swapInstance:toFront()

    if timerResults == nil then
        if (debugLocal) then print("setting timer") end
        timerResults = timer.performWithDelay(150, UpdateLocalOptimized, -1)
    end

    if (debugLocal) then print("end updateLocalOptimized") end
end

-- -----------------------------------------------------------------------------------
-- Scene event functions
-- -----------------------------------------------------------------------------------

function scene:create(event)

    if (debug) then print("creating painttown scene") end
    local sceneGroup = self.view
    -- Code here runs when the scene is first created but has not yet appeared on screen

    sceneGroup:insert(ctsGroup)

    locationText = display.newText(sceneGroup, "Current location:" .. currentPlusCode, display.contentCenterX, 200, native.systemFont, 20)
    timeText = display.newText(sceneGroup, "Current time:" .. os.date("%X"), display.contentCenterX, 220, native.systemFont, 20)
    scoreText = display.newText(sceneGroup, "Leaderboards: ?", display.contentCenterX, 260, native.systemFont, 20)
    scoreText.anchorY = 0
    locationName = display.newText(sceneGroup, "", display.contentCenterX, 240, native.systemFont, 20)

    if (bigGrid) then
        CreateRectangleGrid(3, 320, 400, sceneGroup, cellCollection) -- rectangular Cell11 grid with map tiles
        CreateRectangleGrid(60, 16, 20, ctsGroup, CellTapSensors, "painttown") -- rectangular Cell11 grid  with color fill
    else
        -- original values, but too small to interact with.
        CreateRectangleGrid(3, 160, 200, sceneGroup, cellCollection) -- rectangular Cell11 grid with map tiles
        CreateRectangleGrid(60, 5, 4, ctsGroup, CellTapSensors, "painttown") -- rectangular Cell11 grid  with color fill
    end  

    directionArrow = display.newImageRect(sceneGroup, "themables/arrow1.png", 16, 20)
    directionArrow.x = display.contentCenterX
    directionArrow.y = display.contentCenterY
    directionArrow.anchorX = 0
    directionArrow.anchorY = 0
    directionArrow:toFront()

    header = display.newImageRect(sceneGroup, "themables/PaintTown.png",300, 100)
    header.x = display.contentCenterX
    header.y = 100
    header:addEventListener("tap", GoToSceneSelect)
    header:toFront()

    zoom = display.newImageRect(sceneGroup, "themables/ToggleZoom.png", 100, 100)
    zoom.anchorX = 0
    zoom.x = 50
    zoom.y = 100
    zoom:addEventListener("tap", ToggleZoom)
    zoom:toFront()

    swapInstance = display.newImageRect(sceneGroup, "themables/SwitchMode.png", 100, 100)
    swapInstance.anchorX = 0
    swapInstance.x = 550
    swapInstance.y = 100
    swapInstance:addEventListener("tap", switchMode)
    swapInstance:toFront()

    if (debug) then
        debugText = display.newText(sceneGroup, "location data", display.contentCenterX, 1180, 600, 0, native.systemFont, 22)
        debugText:toFront()
    end

    if (debug) then print("created PaintTown scene") end
end

function reorderUI()
    ctsGroup:toFront()
    header:toFront()
    zoom:toFront()
    directionArrow:toFront()
end

function scene:show(event)
    if (debug) then print("showing painttown scene") end
    local sceneGroup = self.view
    local phase = event.phase

    if (phase == "will") then
        -- Code here runs when the scene is still off screen (but is about to come on screen)
        firstRun = true
    elseif (phase == "did") then
        -- Code here runs when the scene is entirely on screen 
        timer.performWithDelay(50, UpdateLocalOptimized, 1)
        timerResultsScoreboard = timer.performWithDelay(2500, GetScoreboard, -1)
        if (debugGPS) then timer.performWithDelay(3000, testDrift, -1) end
        reorderUI()
        GetTeamAssignment()
    end
    if (debug) then print("showed painttown scene") end
end

function scene:hide(event)
    if (debug) then print("hiding painttown scene") end
    local sceneGroup = self.view
    local phase = event.phase

    if (phase == "will") then
        timer.cancel(timerResults)
        timerResults = nil
        timer.cancel(timerResultsScoreboard)
        timerResultsScoreboard = nil
    elseif (phase == "did") then
        -- Code here runs immediately after the scene goes entirely off screen
    end
end

function scene:destroy(event)
    if (debug) then print("destroying painttown scene") end

    local sceneGroup = self.view
    -- Code here runs prior to the removal of scene's view
end

-- -----------------------------------------------------------------------------------
-- Scene event function listeners
-- -----------------------------------------------------------------------------------
scene:addEventListener("create", scene)
scene:addEventListener("show", scene)
scene:addEventListener("hide", scene)
scene:addEventListener("destroy", scene)
-- -----------------------------------------------------------------------------------

return scene
local settingsFile = "settings.txt"
local settings = {}
local VERSION = "1.0.0" -- Add version number here

-- This needs to stay on top --
local function promptForSettings()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.lightGray)
    write("Enter OAuth Token: ")
    term.setTextColor(colors.white)
    settings.oauth_token = read("*")

    term.setTextColor(colors.lightGray)
    write("Enter Bot Username: ")
    term.setTextColor(colors.white)
    settings.bot_username = read()

    term.setTextColor(colors.lightGray)
    write("Enter Twitch Channel: ")
    term.setTextColor(colors.white)
    settings.twitch_channel = read()
end

local function saveSettings()
    local file = fs.open(settingsFile, "w")
    file.write(textutils.serialize(settings))
    file.close()
end

local function loadSettings()
    if fs.exists(settingsFile) then
        local file = fs.open(settingsFile, "r")
        local content = file.readAll()
        settings = textutils.unserialize(content)
        file.close()
    else
        promptForSettings()
        saveSettings()
    end

    -- Validate settings
    if not settings.oauth_token or settings.oauth_token == "" or
       not settings.bot_username or settings.bot_username == "" or
       not settings.twitch_channel or settings.twitch_channel == "" then
        print("Invalid settings detected. Please re-enter your settings.")
        promptForSettings()
        saveSettings()
    end
end

local function connectToTwitch()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    write("Connecting to Twitch...")

    local socket = http.websocket("wss://irc-ws.chat.twitch.tv:443")
    if not socket then
        term.setCursorPos(1, 2)
        term.setTextColor(colors.red)
        write("Failed to connect to Twitch IRC.")
        term.setCursorPos(1, 4)
        term.setTextColor(colors.white)
        write("Type !reauth to reset your settings")
        return nil
    end

    -- Use bot credentials instead of anonymous
    socket.send("PASS oauth:" .. settings.oauth_token)
    socket.send("NICK " .. settings.bot_username)
    socket.send("JOIN #" .. settings.twitch_channel)

    -- Wait for any response to ensure connection is active
    local response = socket.receive(5) -- 5 second timeout
    if not response then
        term.setCursorPos(1, 2)
        term.setTextColor(colors.red)
        write("Connection timed out.")
        term.setCursorPos(1, 4)
        term.setTextColor(colors.white)
        write("Type !reauth to reset your settings")
        socket.close()
        return nil
    end

    -- Additional receive to check for potential error messages
    local secondResponse = socket.receive(1) -- Quick check for additional messages
    
    -- Simple check if we joined the channel successfully
    if not response:find("JOIN") and not secondResponse or not secondResponse:find("JOIN") then
        term.setCursorPos(1, 2)
        term.setTextColor(colors.red)
        write("Login failed. Please check your credentials.")
        term.setCursorPos(1, 4)
        term.setTextColor(colors.white)
        write("Type !reauth to reset your settings")
        socket.close()
        return nil
    end

    term.clear()
    return socket
end

-- Add chat history management
local chatHistory = {}
local maxHistory = 20
local inputBuffer = ""

local function addToHistory(user, msg)
    table.insert(chatHistory, {user = user, message = msg})
    if #chatHistory > maxHistory then
        table.remove(chatHistory, 1)
    end
end

local function colorUsername(username)
    local colors = {
        colors.red,
        colors.green,
        colors.yellow,
        colors.blue,
        colors.magenta,
        colors.cyan,
    }
    local color = colors[(username:byte(1) % #colors) + 1]
    return color
end

local function showHelp()
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.yellow)
    print("== TChat the Twitch Chat Client v" .. VERSION .. " ==")
    term.setTextColor(colors.white)
    print("")
    print("Setup:")
    term.setTextColor(colors.lightGray)
    print(" - You need an OAuth token from https://twitchapps.com/tmi/")
    print(" - Enter your bot username and the channel to join")
    print("")
    term.setTextColor(colors.white)
    print("Commands:")
    term.setTextColor(colors.lightGray)
    print(" !help    - Show this help information")
    print(" !reauth  - Reset your authentication settings")
    print(" !quit    - Exit the application")
    print("")
    term.setTextColor(colors.white)
    print("Usage:")
    term.setTextColor(colors.lightGray)
    print(" - Type messages and press Enter to send")
    print(" - Messages from the channel appear above")
    print(" - Your bot will appear with its username")
    print("")
    term.setTextColor(colors.yellow)
    print("Press any key to continue...")
    os.pullEvent("key")
end

local function drawChat()
    term.clear()
    local width, height = term.getSize()
    
    -- Draw chat history
    for i = 1, #chatHistory do
        term.setCursorPos(1, i)
        local entry = chatHistory[i]
        term.setTextColor(colorUsername(entry.user))
        write(entry.user)
        term.setTextColor(colors.white)
        write(": " .. entry.message)
    end
    
    -- Draw input field
    term.setCursorPos(1, height)
    term.clearLine()
    term.setTextColor(colors.lightGray)
    write("> ")
    term.setTextColor(colors.white)
    write(inputBuffer)
end

local function sendMessage(socket, message)
    if message:len() > 0 then
        socket.send("PRIVMSG #" .. settings.twitch_channel .. " :" .. message)
        addToHistory(settings.bot_username, message)
        drawChat()
    end
end

local function handleCommand(command, socket)
    if command == "!help" or command == "/help" then
        showHelp()
        drawChat() -- Redraw chat after showing help
        return false
    elseif command == "!reauth" or command == "/reauth" then
        print("Restarting settings...")
        if socket then socket.close() end
        promptForSettings()
        saveSettings()
        os.reboot()
        return true
    elseif command == "!quit" or command == "/quit" then
        term.clear()
        term.setCursorPos(1, 1)
        print("Terminating...")
        if socket then socket.close() end
        return true
    end
    return false
end

local function handleInput(socket)
    while true do
        local event, key = os.pullEvent()
        if event == "char" then
            inputBuffer = inputBuffer .. key
            drawChat()
        elseif event == "key" then
            if key == keys.backspace and #inputBuffer > 0 then
                inputBuffer = inputBuffer:sub(1, -2)
                drawChat()
            elseif key == keys.enter then
                local message = inputBuffer
                inputBuffer = ""
                if message:sub(1, 1) == "!" or message:sub(1, 1) == "/" then
                    local shouldExit = handleCommand(message, socket)
                    if shouldExit then
                        return -- Exit the function instead of continuing
                    end
                elseif socket then
                    sendMessage(socket, message)
                end
                drawChat() -- Ensure the chat is redrawn after sending the message
            end
        end
    end
end

local function parseMessage(message)
    local user, msg = message:match("^:([^!]+)!.- PRIVMSG #[^ ]+ :(.+)$")
    return user, msg
end

local function listenForMessages(socket)
    while true do
        local message = socket.receive()
        if message then
            local user, msg = parseMessage(message)
            if user and msg and user ~= settings.bot_username then  -- Ignore messages from our own bot
                addToHistory(user, msg)
                drawChat()
            end
        end
    end
end

local function main(...)
    local args = {...}
    
    -- Check if help was requested as command-line argument
    if args[1] == "help" then
        showHelp()
        return
    end
    
    loadSettings()
    local socket = connectToTwitch()
    
    if socket then
        term.clear()
        term.setCursorPos(1,1)
        addToHistory("System" , "Twitch Chat v" .. VERSION .. " connected")
        drawChat()
        parallel.waitForAny(
            function() listenForMessages(socket) end,
            function() handleInput(socket) end
        )
        -- Close socket if we get here (one of the functions returned)
        if socket then socket.close() end
    else
        -- If connection failed, still allow input for commands
        term.setCursorPos(1, 6)
        term.setTextColor(colors.lightGray)
        write("> ")
        term.setTextColor(colors.white)
        
        while true do
            local input = read()
            if input == "!reauth" or input == "/reauth" then
                promptForSettings()
                saveSettings()
                os.reboot()
                break
            elseif input == "!help" or input == "/help" then
                showHelp()
                -- Redraw the prompt
                term.setCursorPos(1, 6)
                term.clearLine()
                term.setTextColor(colors.lightGray)
                write("> ")
                term.setTextColor(colors.white)
            elseif input == "!quit" or input == "/quit" then
                term.clear()
                term.setCursorPos(1, 1)
                print("Terminating...")
                break
            else
                term.setCursorPos(1, 6)
                term.clearLine()
                term.setTextColor(colors.lightGray)
                write("> ")
                term.setTextColor(colors.white)
            end
        end
    end
end

-- Call main with the command-line arguments
main(...)
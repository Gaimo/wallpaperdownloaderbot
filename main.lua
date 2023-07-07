local discordia = require('discordia')
local sql = require ('sqlite3')

local client = discordia.Client()
local conn = sql.open("files/database.db")

-- Importando a biblioteca de string
discordia.extensions.string()
discordia.extensions.table()

local function print_table(node)
    local cache, stack, output = {},{},{}
    local depth = 1
    local output_str = "{\n"

    while true do
        local size = 0
        for k,v in pairs(node) do
            size = size + 1
        end

        local cur_index = 1
        for k,v in pairs(node) do
            if (cache[node] == nil) or (cur_index >= cache[node]) then

                if (string.find(output_str,"}",output_str:len())) then
                    output_str = output_str .. ",\n"
                elseif not (string.find(output_str,"\n",output_str:len())) then
                    output_str = output_str .. "\n"
                end

                -- This is necessary for working with HUGE tables otherwise we run out of memory using concat on huge strings
                table.insert(output,output_str)
                output_str = ""

                local key
                if (type(k) == "number" or type(k) == "boolean") then
                    key = "["..tostring(k).."]"
                else
                    key = "['"..tostring(k).."']"
                end

                if (type(v) == "number" or type(v) == "boolean") then
                    output_str = output_str .. string.rep('\t',depth) .. key .. " = "..tostring(v)
                elseif (type(v) == "table") then
                    output_str = output_str .. string.rep('\t',depth) .. key .. " = {\n"
                    table.insert(stack,node)
                    table.insert(stack,v)
                    cache[node] = cur_index+1
                    break
                else
                    output_str = output_str .. string.rep('\t',depth) .. key .. " = '"..tostring(v).."'"
                end

                if (cur_index == size) then
                    output_str = output_str .. "\n" .. string.rep('\t',depth-1) .. "}"
                else
                    output_str = output_str .. ","
                end
            else
                -- close the table
                if (cur_index == size) then
                    output_str = output_str .. "\n" .. string.rep('\t',depth-1) .. "}"
                end
            end

            cur_index = cur_index + 1
        end

        if (size == 0) then
            output_str = output_str .. "\n" .. string.rep('\t',depth-1) .. "}"
        end

        if (#stack > 0) then
            node = stack[#stack]
            stack[#stack] = nil
            depth = cache[node] == nil and depth + 1 or depth - 1
        else
            break
        end
    end

    -- This is necessary for working with HUGE tables otherwise we run out of memory using concat on huge strings
    table.insert(output,output_str)
    output_str = table.concat(output)

    print(output_str)
end

-- Função para ler o token do arquivo
local function readTokenFromFile()
    local file = io.open('token.txt', 'r')
    if file then
        local token = file:read('*all')
        file:close()
        return token
    end
    return nil
end

-- Função para verificar se a url é válida.
local function isValidURL(url)
    return url:startswith("https://steamcommunity.com/sharedfiles/filedetails/?id=", true)
end

-- Função para limpar os argumentos da url.
local function clearURLSearchText(url)
    return url:split("&")[1]
end

local function setupDB()
    local createTableRequestsQuery = [[
        CREATE TABLE IF NOT EXISTS requests (
            wallpaperID INTEGER PRIMARY KEY,
            wallpaperURL TEXT
        )
    ]]

    local createTableWallpapersQuery = [[
        CREATE TABLE IF NOT EXISTS wallpapers (
            wallpaperID INTEGET PRIMARY KEY,
            wallpaperURL TEXT
        )
    ]]

    conn:exec(createTableRequestsQuery)
    conn:exec(createTableWallpapersQuery)
end

local function checkWallpaperExists(wallpaperID, table)
    local query = string.format("SELECT wallpaperURL FROM %s WHERE wallpaperID = %d", table, wallpaperID)
    return conn:exec(query)
end

local function wallpaperDownloadURLExists(wallpaperID)   
    local result = checkWallpaperExists(wallpaperID, "wallpapers")
 
    if result and result.wallpaperURL then 
        return result.wallpaperURL[1]
    else
        return false
    end    
end

local function wallpaperRequestExists(wallpaperID)
    local result = checkWallpaperExists(wallpaperID, "requests")

    if result and result.wallpaperURL then 
        return true
    else
        return false
    end    
end

local function getWallpaperIDFromURL(url)
    return url:split("=")[2]
end

local function addWallpaperInRequests(wallpaperID, wallpaperURL)
    local query = string.format("INSERT INTO requests(wallpaperID, wallpaperURL) VALUES(%d, '%s')", wallpaperID, wallpaperURL)
    print(query)
    conn:exec(query)
end

client:on('ready', function()
    print('Logged in as '.. client.user.username)
    setupDB()
end)

client:on('messageCreate', function(message)
    -- Armazena em uma tabela de forma separada o comando e a url
    local messageContentTable = string.split(message.content, " ")
    -- Armazena o comando
    local command = messageContentTable[1]

    if command == "!download" then
        -- Armazena a url limpa
        local wallpaperURL = clearURLSearchText(messageContentTable[2])

        if not isValidURL(wallpaperURL) then 
            return message:reply("A url enviada não é valida!")
        end

        local wallpaperID = getWallpaperIDFromURL(wallpaperURL)
        local wallpaperDownloadURL = wallpaperDownloadURLExists(wallpaperID)

        if wallpaperDownloadURL then
            message:reply(string.format("Aqui está o download do wallpaper solicitado: %s", wallpaperDownloadURL))
            -- message:delete()
            return
        end

        if wallpaperRequestExists(wallpaperID) then
            message:reply("Este wallpaper já foi solicitado, aguarde 24 horas e tente novamente.")
            -- message:delete()
            return
        end

        addWallpaperInRequests(wallpaperID, wallpaperURL)
        message:reply("Seu wallpaper foi adicionado aos pedidos, em breve será baixado, tente novamente em 24 horas.")
        -- message:delete()
    end
end)

-- Lê o token do arquivo
local token = readTokenFromFile()

if token then
    client:run('Bot '..token)
else
    print('Erro: Não foi possível ler o token do arquivo.')
end

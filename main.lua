local discordia = require('discordia') -- Importing discordia
local sql = require ('sqlite3') -- Importing sqlite3

local client = discordia.Client()
local conn = sql.open("files/database.db")

-- Importing some extensions
discordia.extensions.string()
discordia.extensions.table()

local function print_table(node)
    -- Função responsavel por imprimir uma tabela
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

local function readTokenFromFile()
    -- Função para ler o token do arquivo token.txt
    local file = io.open('token.txt', 'r')
    if file then
        local token = file:read('*all')
        file:close()
        return token
    end
    return nil
end

local function isValidURL(url)
    -- Função para verificar se a url é válida.
    return url:startswith("https://steamcommunity.com/sharedfiles/filedetails/?id=", true)
end

local function clearURLSearchText(url)
    -- Função para limpar os argumentos da url.
    if not url then return false end
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
    conn:exec(query)
end

local function getWallpapersFromRequestsTable()
    local query = "SELECT wallpaperURL FROM requests LIMIT 10"
    local result = conn:exec(query)

    if result then
        return result
    else
        return {} -- Retorna uma tabela vazia se nenhum resultado for encontrado
    end
end


local function getWallpapersCommand(message)
    local wallpapers = getWallpapersFromRequestsTable().wallpaperURL
    -- print_table(wallpapers)

    if wallpapers and #wallpapers > 0 then
        local response = "Os 10 wallpapers mais recentes solicitados são:\n\n"

        for i, wallpaper in ipairs(wallpapers) do
            local wallpaperID = string.split(wallpaper, "=")[2]
            response = response .. string.format("Wallpaper %d:\nID: %s\nURL: %s\n\n", i, wallpaperID, wallpaper)
        end

        message:reply(response)
    else
        message:reply("Não foram encontrados wallpapers solicitados.")
    end
end

local function addWallpaperCommand(message)
    -- Verifica se o usuário tem permissão para executar o comando
    if not message.member:hasPermission(discordia.enums.permission.administrator) then
        return message:reply("Você não tem permissão para executar esse comando.")
    end

    -- Obtém os argumentos do comando
    local args = string.split(message.content, " ")
    local wallpaperID = tonumber(args[2])
    local wallpaperURL = args[3]

    -- Verifica se os argumentos são válidos
    if not wallpaperID or not wallpaperURL then
        return message:reply("Argumentos inválidos. Utilize o comando da seguinte forma: !addwallpaper <wallpaperID> <wallpaperURL>")
    end

    -- Remove o registro da tabela "requests" com o mesmo wallpaperID
    local deleteQuery = string.format("DELETE FROM requests WHERE wallpaperID = %d", wallpaperID)
    conn:exec(deleteQuery)

    -- Insere o registro na tabela "wallpapers"
    local insertQuery = string.format("INSERT INTO wallpapers (wallpaperID, wallpaperURL) VALUES (%d, '%s')", wallpaperID, wallpaperURL)
    conn:exec(insertQuery)

    return message:reply("Wallpaper adicionado com sucesso na tabela 'wallpapers'.")
end

local function downloadWallpaperCommand(message)
    -- Armazena em uma tabela de forma separada o comando e a url
    local args = string.split(message.content, " ")

    -- Armazena a url limpa
    local wallpaperURL = clearURLSearchText(args[2])

    if not wallpaperURL or not isValidURL(wallpaperURL) then 
        return message:reply("A url enviada não é valida!")
    end

    local wallpaperID = getWallpaperIDFromURL(wallpaperURL)
    local wallpaperDownloadURL = wallpaperDownloadURLExists(wallpaperID)

    if wallpaperDownloadURL then
        message:reply(string.format("Aqui está o download do wallpaper solicitado: %s", wallpaperDownloadURL))
        message:delete()
        return
    end

    if wallpaperRequestExists(wallpaperID) then
        message:reply("Este wallpaper já foi solicitado, aguarde 24 horas e tente novamente.")
        message:delete()
        return
    end

    addWallpaperInRequests(wallpaperID, wallpaperURL)
    message:reply("Seu wallpaper foi adicionado aos pedidos, em breve será baixado, tente novamente em 24 horas.")
    message:delete()
end

client:on('ready', function()
    print('Logged in as '.. client.user.username)
    setupDB()
end)

client:on('messageCreate', function(message)
    local content = message.content

    if content:startswith("!requests") then
        getWallpapersCommand(message)
    elseif content:startswith("!add") then
        addWallpaperCommand(message)
    elseif content:startswith("!get") then
        downloadWallpaperCommand(message)
    end
end)

-- Lê o token do arquivo
local token = readTokenFromFile()

if token then
    client:run('Bot '..token)
else
    print('Erro: Não foi possível ler o token do arquivo.')
end

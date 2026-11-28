-- 任务锁单元测试：lua5.1 tests/lua/test_tasks.lua
package.path = "src/luci-app-adguardhome-lite/luasrc/?.lua;" .. package.path
local tasks = require "model.adguardhome_lite.tasks"

local failed = 0
local total = 0

local function check(name, actual, expected)
    total = total + 1
    if actual ~= expected then
        failed = failed + 1
        io.stderr:write(string.format("FAIL %s: got %s, want %s\n",
            name, tostring(actual), tostring(expected)))
    end
end

-- 内存文件系统：只实现任务锁用到的 access / readfile / writefile / stat / remove
local function new_fs()
    local files = {}
    local fs = {}
    function fs.access(path)
        return files[path] ~= nil
    end
    function fs.readfile(path)
        return files[path] and files[path].data or nil
    end
    function fs.writefile(path, data)
        files[path] = { data = data, mtime = os.time() }
    end
    function fs.stat(path, what)
        local f = files[path]
        if not f then
            return nil
        end
        if what == "mtime" then
            return f.mtime
        end
        return { type = "reg", size = #f.data }
    end
    function fs.remove(path)
        files[path] = nil
    end
    function fs.set_mtime(path, t)
        if files[path] then
            files[path].mtime = t
        end
    end
    return fs, files
end

-- pid 存活由测试控制，避免依赖真实进程
local function new_sys(alive)
    return {
        call = function()
            return alive and 0 or 1
        end
    }
end

local RUN = "/var/run/agh"
local ACTIONS = { apply = "x", restart = "y", set_password = "z" }

-- 1. 内核更新锁
local fs = new_fs()
check("update: no lock", tasks.update_running(fs, RUN, new_sys(true)), false)

fs.writefile(RUN .. "_update.lock", "")
fs.writefile(RUN .. "_update.pid", "123\n")
check("update: live pid", tasks.update_running(fs, RUN, new_sys(true)), true)

local dead = new_fs()
dead.writefile(RUN .. "_update.lock", "")
dead.writefile(RUN .. "_update.pid", "123")
check("update: dead pid cleared", tasks.update_running(dead, RUN, new_sys(false)), false)
check("update: dead lock removed", dead.access(RUN .. "_update.lock"), false)

local grace = new_fs()
grace.writefile(RUN .. "_update.lock", "")
check("update: pid missing within grace", tasks.update_running(grace, RUN, new_sys(true)), true)
grace.set_mtime(RUN .. "_update.lock", os.time() - 600)
check("update: stale lock expired", tasks.update_running(grace, RUN, new_sys(true)), false)

-- 2. 插件更新标记
local pf = new_fs()
check("plugin: no marker", tasks.plugin_running(pf, RUN), false)
pf.writefile(RUN .. "_plugin_update.running", "")
check("plugin: fresh marker", tasks.plugin_running(pf, RUN), true)
pf.set_mtime(RUN .. "_plugin_update.running", os.time() - 7200)
check("plugin: expired marker", tasks.plugin_running(pf, RUN), false)
check("plugin: expired marker removed", pf.access(RUN .. "_plugin_update.running"), false)

-- 3. 动作锁
local af = new_fs()
check("action: no name", tasks.action_running(af, RUN, new_sys(true), ACTIONS), false)

af.writefile(RUN .. "_action.name", "apply\n")
check("action: name but no running flag",
    tasks.action_running(af, RUN, new_sys(true), ACTIONS), false)

af.writefile(RUN .. "_action_apply.running", "")
af.writefile(RUN .. "_action_apply.pid", "999")
check("action: live pid", tasks.action_running(af, RUN, new_sys(true), ACTIONS), true)
check("action: dead pid", tasks.action_running(af, RUN, new_sys(false), ACTIONS), false)

-- 白名单外的动作名不应被视为运行中
af.writefile(RUN .. "_action.name", "rm -rf /")
af.writefile(RUN .. "_action_rm -rf /.running", "")
check("action: unknown name ignored",
    tasks.action_running(af, RUN, new_sys(true), ACTIONS), false)

-- 4. busy 优先级：内核更新 > 插件更新 > 动作
local bf = new_fs()
bf.writefile(RUN .. "_update.lock", "")
bf.writefile(RUN .. "_update.pid", "1")
bf.writefile(RUN .. "_plugin_update.running", "")
bf.writefile(RUN .. "_action.name", "apply")
bf.writefile(RUN .. "_action_apply.running", "")
bf.writefile(RUN .. "_action_apply.pid", "1")
check("busy: update first", tasks.busy(bf, RUN, new_sys(true), ACTIONS), "update_busy")

bf.remove(RUN .. "_update.lock")
check("busy: plugin second", tasks.busy(bf, RUN, new_sys(true), ACTIONS), "plugin_update_busy")

bf.remove(RUN .. "_plugin_update.running")
check("busy: action third", tasks.busy(bf, RUN, new_sys(true), ACTIONS), "action_busy")

bf.remove(RUN .. "_action_apply.running")
check("busy: idle", tasks.busy(bf, RUN, new_sys(true), ACTIONS), nil)

-- 5. 动作文件路径
local log, code, pid, running = tasks.action_files(RUN, "apply")
check("files log", log, RUN .. "_action_apply.log")
check("files code", code, RUN .. "_action_apply.code")
check("files pid", pid, RUN .. "_action_apply.pid")
check("files running", running, RUN .. "_action_apply.running")

if failed > 0 then
    io.stderr:write(string.format("%d/%d checks failed\n", failed, total))
    os.exit(1)
end

print(string.format("%d checks passed", total))

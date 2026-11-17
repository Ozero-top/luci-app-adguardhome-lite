-- 统一错误码与日志级别
-- Lua 侧返回给前端的 reason 与 Shell 侧 log_event 的原因使用同一套名称。
local M = {}

M.codes = {
    invalid_param = "warn",
    permission_denied = "warn",
    update_busy = "warn",
    core_not_installed = "error",
    core_download_failed = "error",
    core_arch_mismatch = "error",
    core_integrity_failed = "error",
    core_version_mismatch = "error",
    core_start_failed = "error",
    config_check_failed = "error",
    config_restore_failed = "error",
    service_start_failed = "error",
    agh_api_unreachable = "warn",
    agh_api_bad_response = "warn",
    dns_apply_failed = "error",
    dns_revert_failed = "error",
    dns_hijack_conflict = "warn",
    legacy_clean_failed = "error",
    password_reset_failed = "error",
    request_failed = "error"
}

function M.level(code)
    return M.codes[code] or "error"
end

function M.known(code)
    return M.codes[code] ~= nil
end

return M

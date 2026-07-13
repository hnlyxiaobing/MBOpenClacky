///| Backend internationalization (i18n) for MBOpenClacky.
///
/// A lightweight key→string dictionary keyed by locale ("en"/"zh").
/// Keys follow the same dotted convention as the frontend i18n package
/// (e.g. "error.invalid_json", "channel.received"), so translations can
/// be kept in sync across the two layers. Error responses, IM channel
/// messages and Web API error payloads are the priority paths covered.

///|
/// Default fallback locale when a requested locale is unset or unsupported.
pub let default_locale : String = "en"

///|
/// Locales supported by the backend dictionary.
pub let supported_locales : Array[String] = ["en", "zh"]

///|
/// English dictionary (default locale).
let en_dict : Map[String, String] = {
  "error.invalid_json": "Invalid JSON body",
  "error.unauthorized": "Unauthorized",
  "error.forbidden": "Forbidden",
  "error.not_found": "Not found",
  "error.internal": "Internal server error",
  "error.invalid_param": "Invalid parameter: {{param}}",
  "error.file_not_found": "File not found: {{path}}",
  "error.permission_denied": "Permission denied: {{path}}",
  "error.rate_limited": "Rate limited, please retry later",
  "channel.received": "Received message from {{user}}",
  "channel.sending": "Sending message to {{user}}",
  "session.created": "Session created: {{id}}",
  "session.not_found": "Session not found: {{id}}",
  "session.deleted": "Session deleted: {{id}}",
  "web.health.ok": "ok",
  "agent.thinking": "Thinking...",
  "agent.done": "Done",
  "memory.saved": "Memory saved",
  "memory.not_found": "Memory not found: {{id}}",
  "todo.added": "Task added: {{title}}",
  "tool.denied": "Tool execution denied: {{name}}",
  "config.saved": "Configuration saved",
  "brand.invalid_license": "Invalid or expired license",
}

///|
/// Chinese (Simplified) dictionary.
let zh_dict : Map[String, String] = {
  "error.invalid_json": "无效的 JSON 请求体",
  "error.unauthorized": "未授权",
  "error.forbidden": "禁止访问",
  "error.not_found": "未找到资源",
  "error.internal": "服务器内部错误",
  "error.invalid_param": "参数无效：{{param}}",
  "error.file_not_found": "文件未找到：{{path}}",
  "error.permission_denied": "权限被拒绝：{{path}}",
  "error.rate_limited": "请求过于频繁，请稍后重试",
  "channel.received": "收到来自 {{user}} 的消息",
  "channel.sending": "正在向 {{user}} 发送消息",
  "session.created": "会话已创建：{{id}}",
  "session.not_found": "未找到会话：{{id}}",
  "session.deleted": "会话已删除：{{id}}",
  "web.health.ok": "正常",
  "agent.thinking": "思考中……",
  "agent.done": "完成",
  "memory.saved": "记忆已保存",
  "memory.not_found": "未找到记忆：{{id}}",
  "todo.added": "任务已添加：{{title}}",
  "tool.denied": "工具执行被拒绝：{{name}}",
  "config.saved": "配置已保存",
  "brand.invalid_license": "许可证无效或已过期",
}

///|
/// Locale → dictionary table.
let dicts : Map[String, Map[String, String]] = { "en": en_dict, "zh": zh_dict }

///|
/// True when `locale` is a supported backend locale.
pub fn is_supported(locale : String) -> Bool {
  let lower = locale.to_lower()
  for l in supported_locales {
    if l == lower {
      return true
    }
  }
  false
}

///|
/// Resolve the effective locale from a priority chain:
/// channel config > session settings > global default.
pub fn resolve_locale(
  channel_locale : String?,
  session_locale : String?,
) -> String {
  match channel_locale {
    Some(l) if is_supported(l) => l.to_lower()
    _ =>
      match session_locale {
        Some(l) if is_supported(l) => l.to_lower()
        _ => default_locale
      }
  }
}

///|
/// Translate `key` for `locale`, falling back to the default locale and
/// finally to the raw key if still missing.
pub fn t(locale : String, key : String) -> String {
  t_with_params(locale, key, {})
}

///|
/// Translate `key` with `{{name}}` parameter substitution.
pub fn t_with_params(
  locale : String,
  key : String,
  params : Map[String, String],
) -> String {
  let loc = if is_supported(locale) {
    locale.to_lower()
  } else {
    default_locale
  }
  match lookup(loc, key) {
    Some(s) => substitute(s, params)
    None =>
      match lookup(default_locale, key) {
        Some(s) => substitute(s, params)
        None => key
      }
  }
}

///|
/// True when `key` exists in the default locale dictionary.
pub fn has(key : String) -> Bool {
  match lookup(default_locale, key) {
    Some(_) => true
    None => false
  }
}

///|
/// Look up a key within a single locale dictionary.
fn lookup(locale : String, key : String) -> String? {
  match dicts.get(locale) {
    Some(dict) => dict.get(key)
    None => None
  }
}

///|
/// Substitute {{name}} placeholders from `params` into `template`.
fn substitute(template : String, params : Map[String, String]) -> String {
  if params.length() == 0 {
    return template
  }
  let mut result = template
  for k, v in params {
    result = result.replace(old="{{" + k + "}}", new=v)
  }
  result
}

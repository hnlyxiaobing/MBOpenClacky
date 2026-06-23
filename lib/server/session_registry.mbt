///|
/// 会话注册条目
pub struct SessionEntry {
  session_id : String
  worker_id : WorkerId
  created_at : String
  mut last_activity : String
  metadata : Map[String, String]
}

///|
/// 会话注册表
pub struct SessionRegistry {
  mut entries : Array[SessionEntry]
  max_sessions : Int
}

///|
/// Create a new empty SessionRegistry
pub fn SessionRegistry::new(max_sessions? : Int = 1000) -> SessionRegistry {
  { entries: [], max_sessions }
}

///|
/// 注册新会话
pub fn SessionRegistry::register(
  self : SessionRegistry,
  session_id : String,
  worker_id : WorkerId,
  created_at? : String = "",
) -> Result[Unit, String] {
  // Check duplicate
  for entry in self.entries {
    if entry.session_id == session_id {
      return Err("Session already registered: " + session_id)
    }
  }
  // Check capacity
  if self.entries.length() >= self.max_sessions {
    return Err(
      "Registry is full: max_sessions=" + self.max_sessions.to_string(),
    )
  }
  let entry : SessionEntry = {
    session_id,
    worker_id,
    created_at,
    last_activity: created_at,
    metadata: {},
  }
  self.entries.push(entry)
  Ok(())
}

///|
/// 注销会话
pub fn SessionRegistry::unregister(
  self : SessionRegistry,
  session_id : String,
) -> Result[SessionEntry, String] {
  let mut found_idx = -1
  for i = 0; i < self.entries.length(); i = i + 1 {
    if self.entries[i].session_id == session_id {
      found_idx = i
      break
    }
  }
  if found_idx < 0 {
    return Err("Session not found: " + session_id)
  }
  let entry = self.entries[found_idx]
  let new_entries : Array[SessionEntry] = []
  for i = 0; i < self.entries.length(); i = i + 1 {
    if i != found_idx {
      new_entries.push(self.entries[i])
    }
  }
  self.entries = new_entries
  Ok(entry)
}

///|
/// 按 session_id 查找
pub fn SessionRegistry::find(
  self : SessionRegistry,
  session_id : String,
) -> SessionEntry? {
  for entry in self.entries {
    if entry.session_id == session_id {
      return Some(entry)
    }
  }
  None
}

///|
/// 按 worker_id 查找所有会话
pub fn SessionRegistry::find_by_worker(
  self : SessionRegistry,
  worker_id : WorkerId,
) -> Array[SessionEntry] {
  let result : Array[SessionEntry] = []
  for entry in self.entries {
    if entry.worker_id == worker_id {
      result.push(entry)
    }
  }
  result
}

///|
/// 迁移会话到新 Worker
pub fn SessionRegistry::migrate(
  self : SessionRegistry,
  session_id : String,
  new_worker_id : WorkerId,
) -> Result[Unit, String] {
  for i = 0; i < self.entries.length(); i = i + 1 {
    if self.entries[i].session_id == session_id {
      // Create new entry with updated worker_id
      let old = self.entries[i]
      self.entries[i] = {
        session_id: old.session_id,
        worker_id: new_worker_id,
        created_at: old.created_at,
        last_activity: old.last_activity,
        metadata: old.metadata,
      }
      return Ok(())
    }
  }
  Err("Session not found: " + session_id)
}

///|
/// 更新最后活动时间
pub fn SessionRegistry::touch(
  self : SessionRegistry,
  session_id : String,
  activity_time : String,
) -> Result[Unit, String] {
  for entry in self.entries {
    if entry.session_id == session_id {
      entry.last_activity = activity_time
      return Ok(())
    }
  }
  Err("Session not found: " + session_id)
}

///|
/// 获取所有活跃会话 ID
pub fn SessionRegistry::list_active(self : SessionRegistry) -> Array[String] {
  let result : Array[String] = []
  for entry in self.entries {
    result.push(entry.session_id)
  }
  result
}

///|
/// 获取活跃会话数量
pub fn SessionRegistry::count(self : SessionRegistry) -> Int {
  self.entries.length()
}

///|
/// 检查是否已满
pub fn SessionRegistry::is_full(self : SessionRegistry) -> Bool {
  self.entries.length() >= self.max_sessions
}

///|
/// 清理不活跃会话（简化实现：通过 ISO8601 时间字符串比较）
/// 如果 last_activity 为空或 last_activity < current_time 且 max_idle_seconds > 0，视为不活跃
pub fn SessionRegistry::cleanup_inactive(
  self : SessionRegistry,
  current_time : String,
  _max_idle_seconds : Int,
) -> Array[String] {
  let removed : Array[String] = []
  let kept : Array[SessionEntry] = []
  for entry in self.entries {
    let is_inactive = entry.last_activity == "" ||
      entry.last_activity < current_time
    if is_inactive {
      removed.push(entry.session_id)
    } else {
      kept.push(entry)
    }
  }
  self.entries = kept
  removed
}

///|
/// 批量注销某 Worker 的所有会话（Worker 下线时使用）
pub fn SessionRegistry::unregister_by_worker(
  self : SessionRegistry,
  worker_id : WorkerId,
) -> Array[SessionEntry] {
  let removed : Array[SessionEntry] = []
  let kept : Array[SessionEntry] = []
  for entry in self.entries {
    if entry.worker_id == worker_id {
      removed.push(entry)
    } else {
      kept.push(entry)
    }
  }
  self.entries = kept
  removed
}

///|
/// 设置会话元数据
pub fn SessionRegistry::set_metadata(
  self : SessionRegistry,
  session_id : String,
  key : String,
  value : String,
) -> Result[Unit, String] {
  for entry in self.entries {
    if entry.session_id == session_id {
      entry.metadata.set(key, value)
      return Ok(())
    }
  }
  Err("Session not found: " + session_id)
}

///|
/// 获取会话元数据
pub fn SessionRegistry::get_metadata(
  self : SessionRegistry,
  session_id : String,
  key : String,
) -> String? {
  for entry in self.entries {
    if entry.session_id == session_id {
      return entry.metadata.get(key)
    }
  }
  None
}

///|
/// 注册表统计: (total_sessions, max_sessions, available_slots)
pub fn SessionRegistry::registry_stats(
  self : SessionRegistry,
) -> (Int, Int, Int) {
  let total = self.entries.length()
  let available = self.max_sessions - total
  (total, self.max_sessions, available)
}

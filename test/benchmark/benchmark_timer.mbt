///|
/// BenchmarkTimer - 毫秒级计时器
pub struct BenchmarkTimer {
  start_ms : Int64
  end_ms : Int64
}

///|
/// 创建新的计时器并开始计时
pub fn BenchmarkTimer::new() -> BenchmarkTimer {
  { start_ms: @env.now().reinterpret_as_int64(), end_ms: 0L }
}

///|
/// 开始计时
pub fn BenchmarkTimer::start(self : BenchmarkTimer) -> BenchmarkTimer {
  { ..self, start_ms: @env.now().reinterpret_as_int64() }
}

///|
/// 停止计时
pub fn BenchmarkTimer::stop(self : BenchmarkTimer) -> BenchmarkTimer {
  { ..self, end_ms: @env.now().reinterpret_as_int64() }
}

///|
/// 获取经过的时间（毫秒）
pub fn BenchmarkTimer::elapsed_ms(self : BenchmarkTimer) -> Int64 {
  if self.end_ms == 0L {
    @env.now().reinterpret_as_int64() - self.start_ms
  } else {
    self.end_ms - self.start_ms
  }
}

///|
/// 重置计时器
pub fn BenchmarkTimer::reset(_self : BenchmarkTimer) -> BenchmarkTimer {
  { start_ms: @env.now().reinterpret_as_int64(), end_ms: 0L }
}
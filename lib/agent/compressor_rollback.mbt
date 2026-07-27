///| Compression rollback and level-fallback mechanism.
///|
///| Wraps the Insert-then-Compress flow with safety guarantees:
///| 1. Backs up conversation history before compression
///| 2. If parsing or rebuild fails, restores the backup (rollback)
///| 3. If compression at the current level fails, retries with a less
///|    aggressive level (more recent messages kept) before giving up
///|
///| Reference: openclacky/lib/clacky/agent/message_compressor.rb (compress_with_rollback)

// ── Compression Result ───────────────────────────────────────────────────────

///|
/// Outcome of a single compression attempt.
pub enum CompressionResult {
  /// Compression succeeded; carries savings stats.
  Success(CompressionStats)
  /// Compression failed; carries error message. History is restored to backup.
  Failed(String)
}
 derive(Eq, Debug)

// ── Clone Helpers ────────────────────────────────────────────────────────────

///|
/// Deep-copy an array of messages (for rollback backup).
fn clone_messages(
  messages : Array[@message.Message],
) -> Array[@message.Message] {
  let copy : Array[@message.Message] = []
  for msg in messages {
    copy.push(msg)
  }
  copy
}

///|
/// Replace the entire contents of `target` with `source`.
fn replace_history(
  target : Array[@message.Message],
  source : Array[@message.Message],
) -> Unit {
  target.clear()
  for msg in source {
    target.push(msg)
  }
}

// ── Core: compress_with_rollback ─────────────────────────────────────────────

///|
/// Attempt a single compression pass with rollback safety.
///|
/// **Preconditions**: The caller has already inserted the compression
/// instruction message and obtained the LLM's text response.
/// The compression instruction message and the LLM response should be
/// removed from `history` before calling this function; this function
/// works on the *original* (pre-instruction) history.
///|
/// **Steps**:
/// 1. Back up current history
/// 2. Parse the LLM compression response
/// 3. Rebuild history with the compressed summary + recent messages
/// 4. Validate: the rebuilt history must be shorter than the original
/// 5. On any failure, restore the backup history
///|
/// Returns `Success(stats)` on success, `Failed(msg)` on failure.
pub fn compress_with_rollback(
  history : Array[@message.Message],
  llm_response : String,
  ctx : CompressionContext,
) -> CompressionResult {
  // 1. Backup current history
  let backup = clone_messages(history)
  let before_tokens = ctx.original_token_count
  let before_count = history.length()

  // 2. Parse the LLM compression response
  match parse_compression_response(llm_response) {
    Err(e) =>
      // Parse failure – rollback not needed (history untouched)
      Failed(e)
    Ok(parsed) => {
      // 3. Rebuild history with compression
      let new_history = rebuild_history_with_compression(
        history,
        parsed.summary,
        parsed.topics,
        ctx.recent_message_count,
      )
      // 4. Validate: rebuilt history must be shorter than original
      let after_count = new_history.length()
      let after_tokens = estimate_history_tokens(new_history)
      if after_count >= before_count {
        // Compression did not reduce message count – rollback
        replace_history(history, backup)
        return Failed(
          "Compression did not reduce history size (before: \{before_count}, after: \{after_count})",
        )
      }
      if after_tokens >= before_tokens && before_tokens > 0 {
        // Compression did not reduce tokens – rollback
        replace_history(history, backup)
        return Failed(
          "Compression did not reduce token count (before: \{before_tokens}, after: \{after_tokens})",
        )
      }
      // 5. Success – apply the new history
      replace_history(history, new_history)
      let stats = calculate_compression_savings(
        before_tokens,
        after_tokens,
        before_count,
        after_count,
      )
      Success(stats)
    }
  }
}

// ── Level Fallback ────────────────────────────────────────────────────────────

///|
/// Fallback recent-message counts tried when the initial level fails.
///|
/// Each entry is a `recent_count` that increases (less aggressive
/// compression). The first successful pass wins.
let fallback_recent_counts : Array[Int] = [25, 30, 40, 50]

///|
/// Attempt compression with automatic level fallback.
///|
/// Tries `compress_with_rollback` with the initial `recent_count` from
/// the context. If that fails, retries with progressively larger
/// `recent_count` values (less aggressive compression) until one succeeds
/// or all fallback levels are exhausted.
///|
/// On success, `history` is updated and `Success(stats)` is returned.
/// On total failure, `history` is restored to its original state and
/// `Failed(last_error)` is returned.
pub fn compress_with_level_fallback(
  history : Array[@message.Message],
  llm_response : String,
  ctx : CompressionContext,
) -> CompressionResult {
  // First attempt: use the context's original recent_count
  match compress_with_rollback(history, llm_response, ctx) {
    Success(stats) => return Success(stats)
    Failed(first_err) => {
      // Try fallback levels with increasing recent_count
      let mut last_err = first_err
      for fb_count in fallback_recent_counts {
        if fb_count <= ctx.recent_message_count {
          // Skip fallbacks that are not more generous
          continue
        }
        let fb_ctx = { ..ctx, recent_message_count: fb_count }
        match compress_with_rollback(history, llm_response, fb_ctx) {
          Success(stats) => return Success(stats)
          Failed(e) => last_err = e
        }
      }
      Failed(last_err)
    }
  }
}

// ── Agent-level Convenience ──────────────────────────────────────────────────

///|
/// Agent-level wrapper that orchestrates the full compression flow.
///|
/// 1. Checks if compression is needed
/// 2. Backs up current history
/// 3. Calls `compress_with_level_fallback` with the LLM response
/// 4. On success, saves the archived chunk to disk and increments level
/// 5. On failure, restores the backup (already done by rollback)
///|
/// Returns `Some(stats)` on success, `None` if compression was skipped
/// or failed (history is preserved).
pub fn Agent::compress_with_safety(
  self : Agent,
  llm_response : String,
) -> CompressionResult {
  let ctx_opt = self.compress_messages_if_needed(false)
  match ctx_opt {
    None => Failed("Compression not needed")
    Some(ctx) => {
      let result = compress_with_level_fallback(
        self.history,
        llm_response,
        ctx,
      )
      match result {
        Success(_) => {
          // Save archived chunk to disk for future recall
          let to_archive = clone_messages(self.history)
          match save_compressed_chunk(
            to_archive,
            self.session_id,
            self.compression_level,
          ) {
            Ok(_) => ()
            Err(_) => () // chunk save failure is non-fatal
          }
          self.compression_level = self.compression_level + 1
          result
        }
        Failed(_) => result
      }
    }
  }
}

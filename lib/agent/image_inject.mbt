///| Public image-injection helper for WS/CLI message paths.
/// 
/// The observe() phase in react.mbt injects tool-result images into the
/// conversation as a follow-up `role:"user"` message with
/// `ContentBlock::Image`. This module exposes the same construction logic
/// as a standalone function so the WS message handler (and the CLI `-i`
/// path when it lands) can inject user-supplied images before a run
/// starts, without duplicating the data-URL / vision-support logic.
/// 
/// Spec 2026-08-18_17 risk A closure: the previous spec 17 implementation
/// only parsed attachment metadata into the user message text; this
/// completes the injection half by constructing real Image content
/// blocks, mirroring the observe() tool-result path.

///|
/// Inject an image into the agent's conversation history as a
/// `role:"user"` message with `ContentBlock::Image`. The image is
/// encoded as a `data:` URL so it is self-contained (no external fetch
/// needed by the API provider). When the provider does not support
/// vision, a text placeholder is emitted instead so the model still
/// knows an image was provided.
/// 
/// # Parameters
/// - `agent`: the target agent (its `client.vision_supported` flag is
///   consulted).
/// - `base64_data`: raw base64 payload (no data-URL prefix).
/// - `mime_type`: e.g. `image/png`.
/// - `path`: optional source path used for the `[Image: <label>]`
///   placeholder text.
pub fn Agent::inject_user_image(
  self : Agent,
  base64_data : String,
  mime_type : String,
  path? : String? = None,
) -> Unit {
  let data_url = "data:\{mime_type};base64,\{base64_data}"
  let label = match path {
    Some(p) => {
      let segs = p.split("/").collect()
      if segs.length() > 0 {
        segs[segs.length() - 1]
      } else {
        "image"
      }
    }
    None => "image"
  }
  let blocks : Array[@message.ContentBlock] = if self.client.vision_supported {
    [
      @message.ContentBlock::Text({ text: "[Image: \{label}]" }),
      @message.ContentBlock::Image({ url: data_url, detail: None }),
    ]
  } else {
    let suffix = match path {
      Some(p) => " (saved at \{p})"
      None => ""
    }
    [@message.ContentBlock::Text({ text: "[Image: \{label}]\{suffix}" })]
  }
  let msg = @message.Message::user_blocks(blocks)
  // Stamp created_at so the message has a stable ordering key (used
  // by edit_message's message_id lookup and history pagination).
  self.history.append({ ..msg, created_at: Some(current_time_ms().to_string()) })
  self.hook_manager.emit(MessageAdded)
}

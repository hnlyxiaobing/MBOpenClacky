///| Media panel - rabbita replacement for `web/js/media.js`.
///
/// Four tabs: Image generation, Video generation, Text-to-Speech, Audio transcription.
/// API endpoints:
///   - `POST /api/media/image` - generate image
///   - `POST /api/media/video` - generate video
///   - `POST /api/media/audio/speech` - text-to-speech
///   - `POST /api/media/audio/transcriptions` - transcribe audio

///|
priv enum MediaTab {
  ImageTab
  VideoTab
  SpeechTab
  TranscribeTab
} derive(Eq)

///|
priv enum MediaMsg {
  Init
  SwitchTab(MediaTab)
  // Image form
  ImagePromptChanged(String)
  ImageSizeChanged(String)
  ImageQualityChanged(String)
  ClickGenerateImage
  ImageDone(Result[Json, String])
  // Video form
  VideoPromptChanged(String)
  VideoDurationChanged(String)
  ClickGenerateVideo
  VideoDone(Result[Json, String])
  // Speech form
  SpeechTextChanged(String)
  SpeechVoiceChanged(String)
  ClickGenerateSpeech
  SpeechDone(Result[Json, String])
  // Transcribe
  ClickTranscribe
  LocaleChanged
}

///|
priv struct MediaModel {
  active_tab : MediaTab
  generating : Bool
  locale : String
  // Image form
  image_prompt : String
  image_size : String
  image_quality : String
  image_result : Json
  // Video form
  video_prompt : String
  video_duration : String
  video_result : Json
  // Speech form
  speech_text : String
  speech_voice : String
  speech_result : Json
}

///|
fn initial_media_model() -> MediaModel {
  {
    active_tab: ImageTab,
    generating: false,
    locale: "",
    image_prompt: "",
    image_size: "1024x1024",
    image_quality: "standard",
    image_result: Json::null(),
    video_prompt: "",
    video_duration: "5",
    video_result: Json::null(),
    speech_text: "",
    speech_voice: "alloy",
    speech_result: Json::null(),
  }
}

///|
fn media_update(
  emit : @cmd.Emit[MediaMsg],
  msg : MediaMsg,
  model : MediaModel,
) -> (@cmd.Cmd, MediaModel) {
  match msg {
    Init => (locale_change_cmd(emit, LocaleChanged), { ..model, locale: i18n_get_locale() })
    SwitchTab(tab) => (@cmd.none, { ..model, active_tab: tab })
    ImagePromptChanged(v) => (@cmd.none, { ..model, image_prompt: v })
    ImageSizeChanged(v) => (@cmd.none, { ..model, image_size: v })
    ImageQualityChanged(v) => (@cmd.none, { ..model, image_quality: v })
    ClickGenerateImage => {
      if model.image_prompt.trim() == "" {
        app_notify(t("media.prompt_required"), "warning")
        (@cmd.none, model)
      } else {
        let body = Json::object(
          Map::of([
            ("prompt", Json::string(model.image_prompt.trim().to_owned())),
            ("size", Json::string(model.image_size)),
            ("quality", Json::string(model.image_quality)),
          ]),
        )
        let cmd = @cmd.perform(r => emit(ImageDone(r)), async fn() noraise {
          safe_post("/api/media/image", body)
        })
        (cmd, { ..model, generating: true })
      }
    }
    ImageDone(Ok(json)) => {
      app_notify(t("media.result"), "info")
      (@cmd.none, { ..model, generating: false, image_result: json })
    }
    ImageDone(Err(e)) => {
      app_notify(e, "error")
      (@cmd.none, { ..model, generating: false })
    }
    VideoPromptChanged(v) => (@cmd.none, { ..model, video_prompt: v })
    VideoDurationChanged(v) => (@cmd.none, { ..model, video_duration: v })
    ClickGenerateVideo => {
      if model.video_prompt.trim() == "" {
        app_notify(t("media.prompt_required"), "warning")
        (@cmd.none, model)
      } else {
        let dur = match (try? @strconv.parse_int(model.video_duration)) {
          Ok(n) => if n >= 1 && n <= 60 { n } else { 5 }
          Err(_) => 5
        }
        let body = Json::object(
          Map::of([
            ("prompt", Json::string(model.video_prompt.trim().to_owned())),
            ("duration", Json::number(dur.to_double())),
          ]),
        )
        let cmd = @cmd.perform(r => emit(VideoDone(r)), async fn() noraise {
          safe_post("/api/media/video", body)
        })
        (cmd, { ..model, generating: true })
      }
    }
    VideoDone(Ok(json)) => {
      app_notify(t("media.result"), "info")
      (@cmd.none, { ..model, generating: false, video_result: json })
    }
    VideoDone(Err(e)) => {
      app_notify(e, "error")
      (@cmd.none, { ..model, generating: false })
    }
    SpeechTextChanged(v) => (@cmd.none, { ..model, speech_text: v })
    SpeechVoiceChanged(v) => (@cmd.none, { ..model, speech_voice: v })
    ClickGenerateSpeech => {
      if model.speech_text.trim() == "" {
        app_notify(t("media.text_required"), "warning")
        (@cmd.none, model)
      } else {
        let body = Json::object(
          Map::of([
            ("input", Json::string(model.speech_text.trim().to_owned())),
            ("voice", Json::string(model.speech_voice)),
          ]),
        )
        let cmd = @cmd.perform(r => emit(SpeechDone(r)), async fn() noraise {
          safe_post("/api/media/audio/speech", body)
        })
        (cmd, { ..model, generating: true })
      }
    }
    SpeechDone(Ok(json)) => {
      app_notify(t("media.result"), "info")
      (@cmd.none, { ..model, generating: false, speech_result: json })
    }
    SpeechDone(Err(e)) => {
      app_notify(e, "error")
      (@cmd.none, { ..model, generating: false })
    }
    ClickTranscribe => {
      app_notify(t("media.coming_soon"), "info")
      (@cmd.none, model)
    }
    LocaleChanged => (@cmd.none, { ..model, locale: i18n_get_locale() })
  }
}

///|
fn media_view(
  emit : @cmd.Emit[MediaMsg],
  model : MediaModel,
) -> @html.Html {
  // Tab bar
  let tab = fn(key : MediaTab, label : String, icon : String) -> @html.Html {
    let cls = if model.active_tab == key { "skills-tab active" } else { "skills-tab" }
    @html.button(class=cls, on_click=emit(SwitchTab(key)), icon + " " + label)
  }

  let tabs = @html.div(class="skills-tabs", style=["margin-bottom:16px"], [
    tab(ImageTab, t("media.tab_image"), "🎨"),
    tab(VideoTab, t("media.tab_video"), "🎬"),
    tab(SpeechTab, t("media.tab_speech"), "🔊"),
    tab(TranscribeTab, t("media.tab_transcribe"), "📝"),
  ])

  // Tab content
  let content = match model.active_tab {
    ImageTab => media_image_form(emit, model)
    VideoTab => media_video_form(emit, model)
    SpeechTab => media_speech_form(emit, model)
    TranscribeTab => media_transcribe_form(emit, model)
  }

  @html.div([tabs, content])
}

///| Image generation form.
fn media_image_form(emit : @cmd.Emit[MediaMsg], model : MediaModel) -> @html.Html {
  let size_options = [
    @html.option(value="1024x1024", selected=model.image_size == "1024x1024", "1024 x 1024"),
    @html.option(value="512x512", selected=model.image_size == "512x512", "512 x 512"),
    @html.option(value="1792x1024", selected=model.image_size == "1792x1024", "1792 x 1024"),
  ]
  let quality_options = [
    @html.option(value="standard", selected=model.image_quality == "standard", t("media.quality_standard")),
    @html.option(value="hd", selected=model.image_quality == "hd", t("media.quality_hd")),
  ]
  let children : Array[@html.Html] = [
    @html.div(class="settings-group", [
      @html.div(class="settings-group-title", t("media.image_title")),
      @html.div(class="settings-field", [
        @html.label(t("media.prompt")),
        @html.textarea(
          rows=3,
          placeholder=t("media.image_placeholder"),
          value=model.image_prompt,
          on_change=s => emit(ImagePromptChanged(s)),
          style=textarea_style(),
          "",
        ),
      ]),
      @html.div(style=["display:flex", "gap:8px", "align-items:center"], [
        @html.div(class="settings-field", style=["flex:1"], [
          @html.label(t("media.size")),
          @html.select(on_change=s => emit(ImageSizeChanged(s)), size_options),
        ]),
        @html.div(class="settings-field", style=["flex:1"], [
          @html.label(t("media.quality")),
          @html.select(on_change=s => emit(ImageQualityChanged(s)), quality_options),
        ]),
      ]),
      @html.button(
        class="btn btn-primary",
        on_click=emit(ClickGenerateImage),
        if model.generating { t("media.generating") } else { t("media.generate") },
      ),
    ]),
  ]
  // Result
  media_maybe_result(children, model.image_result)
  @html.div(children)
}

///| Video generation form.
fn media_video_form(emit : @cmd.Emit[MediaMsg], model : MediaModel) -> @html.Html {
  let children : Array[@html.Html] = [
    @html.div(class="settings-group", [
      @html.div(class="settings-group-title", t("media.video_title")),
      @html.div(class="settings-field", [
        @html.label(t("media.prompt")),
        @html.textarea(
          rows=3,
          placeholder=t("media.video_placeholder"),
          value=model.video_prompt,
          on_change=s => emit(VideoPromptChanged(s)),
          style=textarea_style(),
          "",
        ),
      ]),
      @html.div(class="settings-field", [
        @html.label(t("media.duration")),
        @html.input(
          input_type=@html.Text,
          value=model.video_duration,
          on_change=s => emit(VideoDurationChanged(s)),
          style=input_style(),
        ),
        @html.div(class="help-text", t("media.duration_help")),
      ]),
      @html.button(
        class="btn btn-primary",
        on_click=emit(ClickGenerateVideo),
        if model.generating { t("media.generating") } else { t("media.generate") },
      ),
    ]),
  ]
  media_maybe_result(children, model.video_result)
  @html.div(children)
}

///| Speech generation form.
fn media_speech_form(emit : @cmd.Emit[MediaMsg], model : MediaModel) -> @html.Html {
  let voice_options = [
    @html.option(value="alloy", selected=model.speech_voice == "alloy", "Alloy"),
    @html.option(value="echo", selected=model.speech_voice == "echo", "Echo"),
    @html.option(value="fable", selected=model.speech_voice == "fable", "Fable"),
    @html.option(value="onyx", selected=model.speech_voice == "onyx", "Onyx"),
    @html.option(value="nova", selected=model.speech_voice == "nova", "Nova"),
    @html.option(value="shimmer", selected=model.speech_voice == "shimmer", "Shimmer"),
  ]
  let children : Array[@html.Html] = [
    @html.div(class="settings-group", [
      @html.div(class="settings-group-title", t("media.speech_title")),
      @html.div(class="settings-field", [
        @html.label(t("media.speech_text")),
        @html.textarea(
          rows=4,
          placeholder=t("media.speech_placeholder"),
          value=model.speech_text,
          on_change=s => emit(SpeechTextChanged(s)),
          style=textarea_style(),
          "",
        ),
      ]),
      @html.div(class="settings-field", [
        @html.label(t("media.voice")),
        @html.select(on_change=s => emit(SpeechVoiceChanged(s)), voice_options),
      ]),
      @html.button(
        class="btn btn-primary",
        on_click=emit(ClickGenerateSpeech),
        if model.generating { t("media.generating") } else { t("media.generate_speech") },
      ),
    ]),
  ]
  media_maybe_result(children, model.speech_result)
  @html.div(children)
}

///| Transcription form (coming soon).
fn media_transcribe_form(emit : @cmd.Emit[MediaMsg], _model : MediaModel) -> @html.Html {
  @html.div(class="settings-group", [
    @html.div(class="settings-group-title", t("media.transcribe_title")),
    @html.div(class="settings-field", [
      @html.label(t("media.audio_file")),
      @html.input(
        input_type=@html.Text,
        placeholder=t("media.audio_file_help"),
        style=input_style(),
      ),
      @html.div(class="help-text", t("media.audio_file_help")),
    ]),
    @html.button(
      class="btn btn-primary",
      on_click=emit(ClickTranscribe),
      t("media.transcribe_btn"),
    ),
  ])
}

///| Append result section if available.
fn media_maybe_result(children : Array[@html.Html], result : Json) -> Unit {
  match result {
    Null => ()
    _ => {
      let is_error = json_bool(result, "ok", true) == false && json_str(result, "message", "") != ""
      if is_error {
        let msg = json_str(result, "message", t("media.coming_soon"))
        children.push(
          @html.div(class="settings-group", [
            @html.div(class="settings-group-title", t("media.result")),
            @html.div(style=["padding:16px", "text-align:center", "color:var(--text-muted)"], [
              @html.div(style=["font-size:24px", "margin-bottom:8px"], "🚫"),
              @html.p(msg),
            ]),
          ]),
        )
      } else {
        // Try to show image URL if available
        let url = json_str(result, "url", json_str(result, "data", ""))
        if url != "" && (url.contains(".png") || url.contains(".jpg") || url.contains(".jpeg") || url.contains(".gif") || url.contains(".webp")) {
          children.push(
            @html.div(class="settings-group", [
              @html.div(class="settings-group-title", t("media.result")),
              @html.img(src=url, style=["max-width:100%", "border-radius:var(--radius-sm)", "margin-top:8px"]),
            ]),
          )
        } else {
          // Show as JSON
          let json_str_val = json_to_pretty_string(result)
          children.push(
            @html.div(class="settings-group", [
              @html.div(class="settings-group-title", t("media.result")),
              @html.pre(
                style=["background:var(--bg-tertiary)", "padding:12px", "border-radius:var(--radius-sm)", "font-size:12px", "font-family:var(--font-mono)", "overflow-x:auto", "white-space:pre-wrap", "max-height:300px"],
                json_str_val,
              ),
            ]),
          )
        }
      }
    }
  }
}

///| Convert JSON to a pretty string for display.
fn json_to_pretty_string(json : Json) -> String {
  match json {
    String(s) => s
    Number(n, ..) => n.to_string()
    True => "true"
    False => "false"
    Null => "null"
    Array(arr) => {
      let parts : Array[String] = []
      arr.iter().each(fn(item) { parts.push(json_to_pretty_string(item)) })
      "[" + parts.join(", ") + "]"
    }
    Object(map) => {
      let parts : Array[String] = []
      map.each(fn(k, v) { parts.push(k + ": " + json_to_pretty_string(v)) })
      "{ " + parts.join(", ") + " }"
    }
  }
}

///|
fn build_media_cell() -> (@cmd.Emit[MediaMsg], @rabbita.Cell) {
  cell_with_emit(
    model=initial_media_model(),
    update=media_update,
    view=media_view,
  )
}

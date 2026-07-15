///| Notification overlay - rabbita replacement for `web/js/notifications.js`.

///|
priv struct Toast {
  id : Int
  message : String
  type_ : String
}

///|
priv enum NotificationMsg {
  Init
  Notify(String, String)
  Dismiss(Int)
}

///|
priv struct NotificationModel {
  toasts : Array[Toast]
  next_id : Int
}

///|
fn initial_notification_model() -> NotificationModel {
  { toasts: [], next_id: 1 }
}

///|
fn notif_update(
  emit : @cmd.Emit[NotificationMsg],
  msg : NotificationMsg,
  model : NotificationModel,
) -> (@cmd.Cmd, NotificationModel) {
  match msg {
    Init =>
      (
        @cmd.custom_cmd(scheduler => {
          on_app_notify((m, ty) => scheduler.add(emit(Notify(m, ty))))
        }),
        model,
      )
    Notify(message, type_) => {
      let id = model.next_id
      let toast : Toast = { id, message, type_ }
      let toasts = model.toasts.copy()
      toasts.push(toast)
      let cmd = if type_ == "success" || type_ == "info" {
        @cmd.custom_cmd(scheduler => {
          js_set_timeout(3000, () => scheduler.add(emit(Dismiss(id))))
        })
      } else {
        @cmd.none
      }
      (cmd, { toasts, next_id: id + 1 })
    }
    Dismiss(id) => {
      let toasts = model.toasts.copy().filter(t => t.id != id)
      (none, { ..model, toasts })
    }
  }
}

///|
fn toast_icon(type_ : String) -> String {
  match type_ {
    "success" => "✓"
    "error" => "✗"
    "warning" => "⚠"
    _ => "ℹ"
  }
}

///|
fn notif_view(
  emit : @cmd.Emit[NotificationMsg],
  model : NotificationModel,
) -> @html.Html {
  div(model.toasts.map(toast =>
    div(
      class="notification \{toast.type_}",
      [
        @html.span(class="notification-icon", toast_icon(toast.type_)),
        @html.span(class="notification-message", toast.message),
        @html.button(
          class="notification-close",
          on_click=emit(Dismiss(toast.id)),
          "✕",
        ),
      ],
    )
  ))
}

///|
fn build_notification_cell() -> (@cmd.Emit[NotificationMsg], @rabbita.Cell) {
  cell_with_emit(
    model=initial_notification_model(),
    update=notif_update,
    view=notif_view,
  )
}

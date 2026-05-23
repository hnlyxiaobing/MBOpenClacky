$messageFile = Join-Path $env:TEMP "mbopenclacky-commit-message.txt"
$msg = @"
Phase 8: Web server based on crescent (REST API / WebSocket / SSE)

- Add bobzhang/crescent 0.10.0 dependency and lib/web/ package skeleton
- Implement 20+ REST API endpoints: sessions CRUD, chat, config, stats, health
- Add WebSocket handler at /ws/sessions/:id for real-time bidirectional comm
- Add SSE streaming endpoint at POST /api/sessions/:id/chat/stream
- Implement X-API-Key authentication middleware and request logging middleware
- Integrate with Agent core, SessionStore, and Hook system
- Update CLI (cmd/main.mbt) with 'mbopenclacky server' subcommand
- Add CORS support via crescent/cors middleware
"@

[IO.File]::WriteAllText(
    $messageFile,
    $msg,
    (New-Object System.Text.UTF8Encoding($false))
)

& ".qoder/skills/mbopenclacky-commit-push/scripts/commit_and_push.ps1" -MessageFile $messageFile -NoPush

PikoPe Web (Phase 0 - local shell)
==================================
Same UI code as the Android app (../lib). One admin/API on the server.

First time:
  setup-local.ps1

Dev in Chrome:
  run-local.ps1

Release folder:
  build-local.ps1       ->  build\web
  deploy-hostinger.ps1  ->  build\web + dist\*.zip (production)

Deploy guide: DEPLOY.txt
Pre-release:   smoke-web.ps1 + SMOKE_CHECKLIST.txt
Tag:           RELEASE.txt (pikope-web-1.0.0+1)

Phases: see WEB_MASTER_PHASES.md

Phase 1: set server CORS_ORIGIN (comma-separated) then run-local.ps1.
  Example: http://localhost:7357,https://play.pikope.com
  Deploy backend/src/Cors.php + Api.php to Hostinger.

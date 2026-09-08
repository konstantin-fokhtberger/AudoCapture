# Changelog: I5 / B10

## 2026-09-08
- Added: .gitignore, Config/Info.plist, раздельные staging/debug/release bundle, проверки arm64/minOS/plist/signature, disabled/temp logger, тесты logger.
- Changed: deployment macOS 14; Run-путь debug; тесты startup используют barrier вместо performance threshold; временные результаты тестов очищаются.
- Fixed: byte allocation AudioBufferList, закрытие log FileHandle при ошибке, повторное создание formatter.
- Validation: 54 tests / 12 suites, 0 failures; debug/release bundle собраны и проверены, release ~0.97 MiB.
- Repository: по явному запросу пользователя создан закрытый konstantin-fokhtberger/AudoCapture; baseline `2d8605d` отправлен в main, локальный/удалённый SHA совпали; приватность проверена.
- Clean checkout: release пересобран из первого Git-коммита, проверки прошли. B10 закрыта.
- Open: аппаратные проверки B09/B11/B14 и дистрибуция B12/B13.

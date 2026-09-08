# I5, часть B10: сборка и исходный baseline

## Выполнено
- `.gitignore` исключает служебные данные, записи, логи и локальные настройки; shared Run action остаётся в составе исходников.
- Минимальная OS 14.0 согласована между Package.swift и Config/Info.plist. Версия 0.1.0/build 1 хранится в plist.
- Отдельные debug/release bundle arm64; staging и обязательные проверки структуры, plist, архитектуры, minOS, локальной ad-hoc signature. Run использует debug-путь.
- Тестовый logger не пишет в Application Support. Временные результаты RecordingManagerTests удаляются. Параллельность startup проверяется барьером вместо времени <0.85 s.
- Исправлена избыточная аллокация Core Audio AudioBufferList; formatter логов переиспользуется; file handle закрывается при ошибке.
- По запросу пользователя создан закрытый GitHub: https://github.com/konstantin-fokhtberger/AudoCapture . Приватность подтверждена API (`PRIVATE`, `isPrivate=true`). Исходный baseline готовится к отправке.

## Проверка
- 54 теста в 12 suites, 0 failures, 5.451 s; compiler warnings/errors отсутствуют. Журнал `/tmp/audocapture-b10-tests.log`.
- Debug и release собраны, plist/arm64/minOS/signature проверки прошли. Журналы `/tmp/audocapture-b10-debug.log`, `/tmp/audocapture-b10-release.log`.
- Debug bundle: 1 467 276 bytes (~1.40 MiB); release: 1 013 964 bytes (~0.97 MiB). Это сумма размеров файлов, не RAM и не загрузка CPU.
- Зависимости Mach-O указывают на системные frameworks и `/usr/lib`; дополнительных encoder/framework bundle нет.
- Версия обоих bundle: 0.1.0 (1), minimum macOS 14.0, architecture arm64.
- Shell syntax проверен. Правила ignore проверены для build/IDE/audio/.env. Предварительная проверка включаемых текстовых файлов не обнаружила private-key/API-key patterns или неожиданных бинарников.

## Осталось
- Зафиксировать/отправить исходный baseline и подтвердить remote HEAD; проверить сборку из чистого checkout.
- B09/B11/B14: живая запись, устройства/сон, 30 min/2 h, CPU/RAM, синхронизация и импорт в выбранный транскрибатор.
- B12/B13: Developer ID/notarization, скачанный дистрибутив и другой Mac/целевая матрица OS. Ad-hoc bundle не объявлен готовым к передаче коллегам.

# Итерация I4: интерфейс и прерывания

## Результат
- Компактное русскоязычное окно шириной 560 pt. Одна Start/Stop-кнопка, таймер HH:mm:ss, активные источники, микрофон, разрешения, сообщение о результате, Retry Saving и Finder.
- Автоматическое обновление окружения при активации/wake; микрофон заблокирован при starting/recording/processing. Нет постоянного polling списка устройств.
- Таймер считает от host-clock capture, обновляется только в recording и замораживается при Stop.
- Monitor обрабатывает сон, wake, дисплеи и Core Audio device/default route notifications; собственный microphone engine сообщает configuration change.
- Причина прерывания передаётся в metadata. Повторные события не запускают повторный Stop. Буферный writer после configuration interruption сохраняет возможность корректного finalize/export.
- Run в Codex связан с `script/build_and_run.sh`, который использует существующий `Scripts/build-app-bundle.sh`. Обычный Quit перед перезапуском сохраняет безопасное завершение I2.

## Проверка
- 52 теста в 11 suites, 0 failures, 5.507 s. Core и app компилируются. Compiler errors/warnings не обнаружены; системный AAC fixture выводит диагностическое сообщение о file interleaving, как и в I3.
- Новые проверки: timer от начала capture, freeze на Stop; повторные interruptions; interruption во время некооперативного startup; metadata partial с валидным экспортом; заморозка буферов с сохранением PCM; правильные notification centers и снятие observers.
- OS notifications в тесте синтетические; Core Audio listener registration отключена в тестовой конфигурации. Реальный app запускает регистрацию HAL listeners.
- `script/build_and_run.sh --verify`: debug bundle собран и процесс запущен. Проверены shell syntax и конфигурация Run.
- Визуально проверено реальное idle-окно через UI automation: 00:00:00, Start, выбранный встроенный микрофон, кнопки разрешений; элементы помещаются и читаются. Start и выдача privacy permissions не нажимались, аудио не записывалось.
- Журналы: `/tmp/audocapture-i4-tests.log`, `/tmp/audocapture-i4-launch.log`. Сравнение исходников: `/tmp/audocapture-i4-review.diff`.

## Границы результата
B08 закрыта по реализации, автоматическим проверкам состояний и визуальному idle-check. B09 остаётся in_progress: нужны реальные built-in/USB/Bluetooth, отключение/смена устройства и формата, дисплеи, сон/пробуждение. Не обещается завершение сохранения до принудительного сна; подробнее [ADR-006](../02-decisions/2026-09-08_adr-006_simple-ui-and-interruptions.md).

Следующий этап: B10 (Git/build hygiene, согласование версии/OS) и затем контролируемый pilot B09/B11/B14. Подпись/передача коллегам - B12-B13.

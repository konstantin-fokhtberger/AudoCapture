# Исправление запуска Bluetooth-микрофона

## Подтверждённая проблема
Выбор Sony перед Start приводил к остановке AVAudioEngine через несколько секунд: running=false, вход менялся с mono Float32 16000 Hz на 44100 Hz. Само переключение Bluetooth в двусторонний режим и изменение качества прослушивания ожидаемы; обрыв записи недопустим.

## Решение
MicrophoneCaptureService заменён на AVCaptureSession + AVCaptureDeviceInput + AVCaptureAudioDataOutput. Устройство выбирается по UID Core Audio, без изменения системного default. Один backend для всех микрофонов, без новой зависимости. PCM 48 kHz mono поступает в существующий CaptureBufferWriter. PTS переводится из session.synchronizationClock в host clock для общего таймлайна. Runtime error/disconnect сохраняют явное прерывание. Управление и callbacks сериализованы; закрытие writer поставлено после уже поступивших callbacks.

AVAudioEngine восстановление потребовало бы управления графом, форматом и повторными подключениями. Эксперименты с задержкой и отключением output не устранили сбой, в итоговую реализацию не входят.

## Проверки
55 тестов прошли. Первый live Sony: 51.607 s, session 79E72548-01EE-4B74-9E60-F1F664ED3131, один 08-09-2026 12-19.m4a, completed capture/export, пустые errors/warnings. Mic 2476715 frames, system 2476111 frames при 48 kHz. Полное декодирование afconvert прошло. Это короткая проверка обрыва, не измерение drift или качества речи; прослушивание пользователем ожидается. Контроль встроенного микрофона после Sony также завершён без errors.

После Stop Finder автоматически не открывается. Стабильная Apple Development подпись сохранила разрешения после пересборок. Долгая запись, disconnect и другие Mac остаются B09/B11/B13/B14.

Источник Bluetooth-ограничения: https://support.apple.com/en-us/102217

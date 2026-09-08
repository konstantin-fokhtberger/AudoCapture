# Итерация I2: безопасные Start/Stop, закрытие и ошибки

## Результат
- B02-B05 реализованы и прошли автоматические проверки. Аппаратная приёмка на macOS/гарнитурах не выполнялась.
- RecordingManager не допускает повторного Start при starting/recording/stopping и повторного Stop при stopping. Отмена во время permissions или startup закрывает запущенные источники и оставляет возможность новой записи.
- Папки имеют UUID; одинаковое время не приводит к общему каталогу. PCMFileWriter отклоняет prepare открытого файла и сбрасывает счётчик после корректного повторного открытия.
- CaptureBufferWriter сериализует конвертацию и закрытие, дренирует converter на Stop, закрывает файл даже при ошибке и игнорирует поздние append. Повторяющиеся ошибки источника дают одно уведомление.
- SystemAudioCaptureService после Stop отсоединяет output и дожидается очереди callbacks. Даже при ошибке ScreenCaptureKit выполняется финализация; manager не экспортирует источник с неуспешным Stop.
- Микрофон удаляет tap/останавливает engine до finish; общая синхронизация закрытия защищает converter/writer от одновременного append.
- Runtime failures проходят source -> manager -> ViewModel, инициируют Stop и попадают в metadata. Capture status отделён от export status; UI различает partial/completed/failed.
- Неизвестный frameCount больше не равен нулю. При отсутствии одной длительности sync delta отсутствует, а не равняется длине другой дорожки. Новые optional metadata fields сохраняют чтение старых JSON текущим приложением.
- Quit ожидает Task вместо пятисекундного polling; отвечает AppKit фактическим результатом готовности. Отменяется ожидание privacy response, поздний ответ не возобновляет отменённую запись.
- Кнопки настроек permissions доступны и при degraded startup; выбор микрофона блокируется во время активной операции.

## Проверка
- Полный Xcode, `swift test --scratch-path /tmp/audocapture-iteration2-build` с временными module cache.
- 38 тестов в 9 suites, 0 failures, 5.338 s тестового времени. Compiler warnings/errors в итоговом журнале не обнаружены.
- Smoke executable из scratch build: `Smoke checks passed.`
- Новые сценарии: конкурентный Start; Start/Stop во время Stop; отмена на permissions и capture startup; callback ошибки и metadata; skip encoder при stop failure; неизвестные метрики; Quit при обработке >5 s; auto-stop по ошибке; partial UI; две сессии в одну секунду; reset writer; реальная ошибка PCM writer; единичное уведомление; drain для 16/44.1/48/96 kHz; поздние буферы после закрытия; cancellation/late completion privacy callback.
- Регрессионный тест выявил и помог устранить выбор пустой default implementation обработчика: регистрация handler в manager теперь явно async, а default implementation RecordingControlling удалена.
- Итоговый лог: `/tmp/audocapture-i2-tests.log`. Локальное сравнение с началом итерации: `/tmp/audocapture-i2-review.diff` (вспомогательный артефакт).

## Ограничения
- Реальный микрофон, системный поток, OS privacy dialogs и гарнитуры в этой итерации не запускались. Автоматические тесты используют синтетические PCM и управляемые capture doubles.
- Внешний MP3 exporter пока сохраняется; его замена и единый датированный M4A - I3. При зависшем exporter Quit безопасно ждёт, а не обрывает файл.
- Ошибка metadata write сохраняет PCM на диске, но автоматический retry/result recovery относится к B07. Во время отменённого startup уже созданные материалы сохраняются, recovery после crash не заявляется.
- Реакция на физическое отключение устройств/сон и производительность синхронного writer требуют B09/B11. Изменение входного формата уже обнаруживается buffer writer и превращается в ошибку вместо неверной конвертации.

## Следующий шаг
I3: B14 -> B06 -> B07. Простое временное выравнивание и сведение двух источников, нативный AAC, один итоговый файл `dd-MM-yyyy HH-mm.m4a` по времени старта, верификация и удаление промежуточных файлов только после успеха.

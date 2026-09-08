# Отдельное ревью качества кода AudoCapture

- Дата: 2026-09-08.
- Scope: все 20 Swift-файлов Sources, все 5 Swift-файлов Tests, Package.swift, Scripts/build-app-bundle.sh. Всего 27 файлов.
- Метод: чтение исходников и контрактов, анализ веток ошибок/await/cleanup, анализ тестовых doubles, сборка и запуск тестов во временной копии, пять дополнительных characterization probes.
- Ограничения: без изменения рабочего кода, реального захвата, профилирования CPU/RAM, Thread Sanitizer и анализа внутренней реализации Apple frameworks. Это code quality review, не специализированный security audit и не повторная продуктовая оценка.
- Доказательства и SHA-256: [отдельный файл](2026-09-08_code-quality-evidence.md). Все проверенные рабочие файлы остались неизменными.

## 1. Итоговая оценка

Код читаемый, сравнительно небольшой и с разумной модульной структурой. Для прототипа это пригодная основа. Для надёжного аудиоприложения качество реализации жизненного цикла, потоковой обработки и восстановления недостаточно.

Проблема не в стиле Swift или числе строк. Типы и публичные контракты допускают состояния, которые приложение считает невозможными: два успешных запуска одновременно, завершение приложения при processing, запись нулевых буферов без ошибки и повторное использование уже занятой папки. Тесты полезны, но существенно сильнее проверяют оркестрацию happy path, чем целостность аудиотракта.

Вывод по code quality: нужны ограниченные исправления ядра и тестовых контрактов до развития функций; полная переработка архитектуры не обоснована.

| Аспект | Оценка по наблюдаемому коду | Основание |
|---|---|---|
| Читаемость и структура | Хорошая основа | Явные типы, небольшие файлы capture/persistence, простые зависимости |
| Разделение ответственности | В целом разумное, местами размыто | Core отделён от SwiftUI, но manager также открывает Finder/Settings и управляет экспортом |
| Конкурентность | Недостаточная | Reentrancy manager подтверждена; capture classes декларируют unchecked Sendable без явного контракта изоляции |
| Ресурсы и ошибки | Недостаточная | Cleanup не гарантирован во всех ветках, ошибки callback не входят в результат сессии |
| Realtime-путь | Требует переработки | Синхронный I/O, аллокации и отдельные Task при ошибках внутри обработки буферов |
| Модели состояния | Недостаточно выразительные | Capture integrity и export success смешиваются в итоговом UI; unknown представляется нулём |
| Тестируемость | Хорошая на уровне manager, слабее ниже | Protocol injection есть, но реальные converter/writer/process и error propagation почти не покрыты |
| Качество тестов | Частичное | 20 тестов проходят; пять дополнительных проб одновременно воспроизводят дефекты |
| Сопровождаемость | Приемлемая после исправлений | Зависимостей мало; необязательные абстракции и полный rewrite не требуются |

P1 ниже означает исправление до передачи приложения коллегам. P2 - ограничение качества/надёжности, которое следует закрывать вместе с соответствующим компонентом. Это не оценка security severity. Всего 12 основных замечаний: 7 P1 и 5 P2. Некоторые подтверждают прежний продуктовый аудит; они не представлены как 12 новых дефектов.

## 2. Основные замечания

### CQ-01 [P1]: нарушен контракт потокового converter

Источник: [AudioConversion.swift:29](/Users/konstantinfokhtberger/Codex/AudoCapture/Sources/AudoCaptureCore/Capture/AudioConversion.swift:29), особенно строка 35.

**Подтверждено исполнением реальной функции.** `makeCopy` сообщает `.endOfStream` после одной порции данных, хотя converter используется для последующих порций. Проба вызвала существующую функцию шесть раз с буферами по 2048 кадров: результат `[2229, 0, 0, 0, 0, 0]`, без thrown error. Вход Float32 mono 44.1 kHz, выход Int16 mono 48 kHz. В предыдущем аудите проверялся аналогичный фрагмент; теперь проверен именно код модуля через `@testable`.

Следствие: успешный вызов преобразования не означает, что входной звук сохранён. Контракт должен различать отсутствие данных сейчас, окончание потока, выход с нулём кадров и ошибку. Исправление: потоковый converter с `.noDataNow` между порциями и отдельным drain на Stop; тестировать последовательность, суммарное число кадров и tail, а не единичный buffer. Связь с предыдущим аудитом: A04.

### CQ-02 [P1]: actor не защищает инвариант одной сессии

Источник: [RecordingManager.swift:40](/Users/konstantinfokhtberger/Codex/AudoCapture/Sources/AudoCaptureCore/Recording/RecordingManager.swift:40), установка `session` на 98, сброс на 114.

**Подтверждено детерминированной пробой с барьером permissions.** Оба вызова Start проходят `session == nil` до первого await. Затем оба успешно стартуют источники; единственная переменная session сохраняет только последнее присваивание. Проба получила два успешных Start и один Stop на источник. Использовались fake sources, живые AVAudioEngine не запускались.

UI сейчас ограничивает повторные нажатия, поэтому это подтверждённый дефект публичного manager API, а не доказательство воспроизводимости двойным кликом в текущем окне. Но корректность ядра зависит от дисциплины внешнего вызова, что делает добавление hotkey/menu bar/нового UI рискованным. Сброс session до остановки открывает аналогичное окно для Start во время Stop.

Исправление: `idle / starting / recording / stopping` в manager, переход перед первым await, локальный session token для проверки принадлежности операции, rollback на ошибке/отмене. Не удерживать блокирующий lock через await. Actor сохраняет сериализацию участков, но состояние может меняться между точками suspension [S1]. Уточнение дополнительного замечания предыдущего аудита.

### CQ-03 [P1]: тип результата подготовки к выходу не выражает безопасность выхода

Источник: [RecordingViewModel.swift:103](/Users/konstantinfokhtberger/Codex/AudoCapture/Sources/AudoCaptureCore/Recording/RecordingViewModel.swift:103), [AppDelegate.swift:22](/Users/konstantinfokhtberger/Codex/AudoCapture/Sources/AudoCaptureApp/AppDelegate.swift:22).

**Подтверждено пробой.** При незавершённом Stop `prepareForTermination()` возвращается примерно через 5 секунд, оставляя `.processing`. AppDelegate интерпретирует возврат Void как готовность и безусловно отвечает `true`. Проба проверяла ViewModel; реальный выход процесса не выполнялся.

Исправление: возвращать явный `ready / stillBusy / failedButRecoverable`, разрешать выход только после безопасного результата, хранить handle выполняемой операции вместо polling состояния. Сам `Task.sleep` не делает завершение корректным. Связь: A02.

### CQ-04 [P1]: контракт capture не позволяет сообщить runtime failure

Источник: [RecordingDependencies.swift:24](/Users/konstantinfokhtberger/Codex/AudoCapture/Sources/AudoCaptureCore/Recording/RecordingDependencies.swift:24), [SystemAudioCaptureService.swift:80](/Users/konstantinfokhtberger/Codex/AudoCapture/Sources/AudoCaptureCore/Capture/SystemAudioCaptureService.swift:80), [MicrophoneCaptureService.swift:35](/Users/konstantinfokhtberger/Codex/AudoCapture/Sources/AudoCaptureCore/Capture/MicrophoneCaptureService.swift:35).

**Подтверждено статически.** Protocol предоставляет Start/Stop и description, но не events/error state. Callback ловит ошибку и только пишет журнал. Никакое улучшение текста ошибки в UI не исправит отсутствие транспортировки этой ошибки в manager.

Исправление: один типизированный канал событий с source ID, error kind и timestamp; явное агрегирование состояния дорожек. Логи должны описывать событие, а не быть единственным его потребителем. Тест: инъекция ошибки после успешного Start меняет состояние/metadata и прекращает либо маркирует повреждённую дорожку. Связь: A01.

### CQ-05 [P1]: каталог сессии не имеет уникальной идентичности и владения

Источник: [RecordingDirectoryManager.swift:36](/Users/konstantinfokhtberger/Codex/AudoCapture/Sources/AudoCaptureCore/Persistence/RecordingDirectoryManager.swift:36), удаление на 54; cleanup manager на 92.

**Подтверждено пробой с временным файлом.** Два вызова с одинаковым временем возвращают один каталог. Удаление каталога второго вызова удаляет артефакт первого. Формат даты ограничен секундой; он не является уникальным session ID. Это затрагивает не только параллельность, но и повторный запуск в одной секунде/совпадение локального времени.

Исправление: UUID + понятное имя, создание без принятия существующего каталога за новую сессию, ownership token для cleanup. В тестах проверять не только pathname, но и сохранность ранее созданного файла. Связь: A09.

### CQ-06 [P1]: отмена task group не гарантирует заявленный timeout

Источники: [MP3Encoding.swift:58](/Users/konstantinfokhtberger/Codex/AudoCapture/Sources/AudoCaptureCore/Encoding/MP3Encoding.swift:58), [PermissionsManager.swift:56](/Users/konstantinfokhtberger/Codex/AudoCapture/Sources/AudoCaptureCore/Permissions/PermissionsManager.swift:56).

**Статический вывод, подтверждённый контрактом Swift task group [S2].** В encoder одна child task блокируется на waitUntilExit, другая вызывает terminate и бросает timeout. Если процесс не завершается после SIGTERM, выход из группы всё равно ждёт блокирующую child task. Кроме того, stdout/stderr не дренируются до завершения: заполнение pipe способно задержать процесс. В permissions таймер на 3 секунды также не ограничивает время группы: child task ждёт detached CGRequestScreenCaptureAccess, который `cancelAll` не останавливает.

Это не утверждение, что системный запрос permissions всегда зависает, или что штатный ffmpeg всегда игнорирует SIGTERM. Дефект - отсутствие гарантии конечного времени у реализации, выглядящей как bounded timeout. Исправление: реальные completion/cancellation boundaries, неблокирующее ожидание процесса, чтение pipes по мере поступления; для permissions отделить системный запрос от ожидания UI. Если MP3 удаляется в пользу нативного exporter, не тратить работу на отдельный framework subprocess. Связь: A08 плюс новое применение к permissions.

### CQ-07 [P1]: cleanup и metadata зависят от happy path

Источники: [SystemAudioCaptureService.swift:54](/Users/konstantinfokhtberger/Codex/AudoCapture/Sources/AudoCaptureCore/Capture/SystemAudioCaptureService.swift:54), [RecordingManager.swift:110](/Users/konstantinfokhtberger/Codex/AudoCapture/Sources/AudoCaptureCore/Recording/RecordingManager.swift:110), запись metadata на 205, cleanup на 304.

**Подтверждено статически.** Ошибка stopCapture пропускает сброс stream и finalize writer. Manager уже обнулил session и продолжает экспорт существующего pathname, хотя финализация не подтверждена. При ошибке записи metadata ссылка на сессию также уже потеряна. Cleanup поглощает ошибки удаления, после чего предупреждение сообщает об очистке как о состоявшемся действии.

Исправление: явное владение ресурсами до достижения закрытого состояния, гарантированное закрытие writer после прекращения/дренирования callback, структурированный StopResult с independent capture/finalization/export outcomes. Не ограничиваться механическим `defer` вокруг закрытия файла: callbacks должны перестать писать до finalize. Сохранять возможность повторить только экспорт/metadata. Связь: A10.

### CQ-08 [P2]: блокирующий и неограниченный error path в обработке аудио

Источники: [MicrophoneCaptureService.swift:30](/Users/konstantinfokhtberger/Codex/AudoCapture/Sources/AudoCaptureCore/Capture/MicrophoneCaptureService.swift:30), [PCMFileWriter.swift:22](/Users/konstantinfokhtberger/Codex/AudoCapture/Sources/AudoCaptureCore/Persistence/PCMFileWriter.swift:22), [AppLogger.swift:28](/Users/konstantinfokhtberger/Codex/AudoCapture/Sources/AudoCaptureCore/Logging/AppLogger.swift:28).

**Механизм подтверждён; потеря кадров под нагрузкой не измерялась.** Callback выполняет converter/аллокации и синхронный file.write через queue.sync. При постоянной ошибке создаётся Task на каждый буфер, а logger открывает файл и создаёт formatter на каждый message. Нет ограничения очереди ошибок и rate limiting.

Исправление: bounded buffer handoff, один writer consumer, счётчик dropped/failed frames и агрегированное уведомление. Политика overflow обязательна; асинхронная неограниченная очередь просто превратит задержку диска в рост памяти. Связь: A05/A14.

### CQ-09 [P2]: writer допускает повторный prepare, но не сбрасывает метрики

Источник: [PCMFileWriter.swift:16](/Users/konstantinfokhtberger/Codex/AudoCapture/Sources/AudoCaptureCore/Persistence/PCMFileWriter.swift:16).

**Подтверждено пробой реального writer.** Первый цикл записывает 16 кадров и finalize возвращает 16; после повторного prepare файл содержит 16 новых кадров, а finalize возвращает 32. В текущей factory writer создаётся на сессию заново, поэтому обычный Start/Stop приложения этим тестом не признан повреждённым. Нарушен публичный контракт повторного использования - существенный риск при добавлении restart/recovery.

Исправление: либо явно single-use writer с отказом повторного prepare, либо корректный reset всех счётчиков/состояния и тест повторного открытия. Новое замечание отдельного ревью.

### CQ-10 [P2]: модель результата теряет различие между unknown, нулём и partial

Источники: [RecordingManager.swift:118](/Users/konstantinfokhtberger/Codex/AudoCapture/Sources/AudoCaptureCore/Recording/RecordingManager.swift:118), `makeSyncDiagnostics` на 257; [RecordingViewModel.swift:145](/Users/konstantinfokhtberger/Codex/AudoCapture/Sources/AudoCaptureCore/Recording/RecordingViewModel.swift:145).

**Подтверждено статически.** Неизвестный frameCount после ошибки Stop остаётся 0; отсутствующая дорожка в syncDiagnostics тоже становится нулевой длительностью. Поэтому длительность единственной корректной дорожки оказывается «рассинхронизацией». Partial export отображается `.completed`. `postProcessingStatus` сам по себе корректно описывает экспорт, но используется как итоговая оценка всей записи.

Исправление: optional/enum для unavailable metrics, sync status `.notApplicable` при одной дорожке; отдельные состояния capture integrity и export. Ошибки хранить структурированно, локализованный текст формировать на границе UI. Связь: A11; уточнение семантики диагностики.

### CQ-11 [P2]: тестовая изоляция нарушается concrete logger

Источники: [AppLogger.swift:10](/Users/konstantinfokhtberger/Codex/AudoCapture/Sources/AudoCaptureCore/Logging/AppLogger.swift:10), [RecordingManagerTests.swift:23](/Users/konstantinfokhtberger/Codex/AudoCapture/Tests/AudoCaptureCoreTests/RecordingManagerTests.swift:23).

**Подтверждено кодом.** Тесты подменяют capture/encoder/Finder, но создают реальные AppLogger. Он всегда выбирает пользовательский Application Support и общий app.log. Разные actor instances пишут один файл без общей сериализации: изоляция каждого actor не сериализует другие экземпляры. Многие manager-тесты также не удаляют собственные временные корни.

Исправление: injectable log sink либо URL, no-op/in-memory logger в unit tests, централизованная fixture с defer cleanup. Не нужен универсальный DI container. Тесты не должны писать в рабочий лог приложения. Новое самостоятельное замечание; связано с A14 только тематически.

### CQ-12 [P2]: тест конкурентности зависит от скорости машины

Источник: [RecordingManagerTests.swift:299](/Users/konstantinfokhtberger/Codex/AudoCapture/Tests/AudoCaptureCoreTests/RecordingManagerTests.swift:299).

**Подтверждено кодом, flaky failure в текущем запуске не наблюдался.** Тест использует два sleep по 500 ms и требует wall-clock <850 ms. Нагрузка, scheduler и смена системного времени могут сломать корректную реализацию. При этом проверяется параллельность двух источников одного Start, а не запрет двух Start.

Исправление: барьеры/continuations для наблюдения «оба start вошли до освобождения любого», внешний deadline только как защита теста от зависания. Отдельно проверять manager reentrancy и cancellation. Новое замечание.

## 3. Прочий технический долг без отдельного release-blocker

- `@unchecked Sendable` у capture classes не доказывает потокобезопасность. Задать ownership/isolation для engine, converter, stream, sourceDescription и lifecycle; не считать все эти аннотации ошибкой автоматически. У PCMFileWriter serial queue действительно защищает его поля. Data race на живом AVAudioEngine в этом ревью не воспроизводилась.
- В [MicrophoneDeviceCatalog.swift:86](/Users/konstantinfokhtberger/Codex/AudoCapture/Sources/AudoCaptureCore/Capture/MicrophoneDeviceCatalog.swift:86) размер в байтах используется как число элементов AudioBufferList при allocate. Это избыточная аллокация, не доказанный buffer overflow; память освобождается через defer. Использовать byteCount/alignment или корректный flexible-array helper.
- `AudioSyncCoordinator` по факту factory форматов, а не синхронизатор; `AVAudioSessionDeviceResolver` используется на macOS и не работает через AVAudioSession. Имена скрывают фактическую ответственность; переименование после определения нового контракта улучшит понимание.
- В ViewModel публичные setters errorMessage/noticeMessage/permissionSummary позволяют UI формировать внутреннее состояние произвольно. Ограничить set там, где нет binding; выбранный микрофон оставить изменяемым по намерению пользователя.
- `RecordingSessionResult` и несколько public structs имеют только internal memberwise initializer. Внешний модуль может читать их, но не создавать для своей реализации public protocol; `@testable` скрывает это ограничение. Для внутреннего app это не текущий сбой. Либо уменьшить public surface, либо сделать намеренно поддерживаемые initializers public.
- `RecordingManager.stopRecording` объединяет остановку, экспорт, metadata и открытие Finder. Размер 100 строк сам по себе не дефект; разделение оправдано для независимого retry экспорта и тестирования failures, а не ради формального лимита длины функции.
- Package.swift и bundle script дублируют minimum OS; bitrate=192 повторяется в manager и ViewModel; logger и bundle используют разные идентификаторы subsystem/product. Вынести только действительно общие настройки в один небольшой typed configuration, без общего registry.
- Скрипт упаковки корректно использует quoting, `set -euo pipefail` и ограниченный выбор debug/release. Hardcoded версия/minimum OS и отсутствие release validation - долг воспроизводимости; переписывать его на другой язык не требуется.

## 4. Что в коде стоит сохранить

1. Разделение App/Core и отсутствие сторонних package dependencies.
2. Protocol injection для capture factory, permissions, encoder, catalog и Finder; это позволило проверить manager без доступа к микрофону.
3. `@MainActor` ViewModel и actor для состояния manager как основа, при исправлении reentrancy.
4. Immutable Codable metadata, атомарную запись JSON и отдельные модели дорожек.
5. Сохранение WAV при ошибке encoder и честные startup warnings при single-track fallback. Сам fallback принят старым ADR и не является дефектом code quality.
6. Отдельный hermetic smoke executable. Он проверяет layout/metadata и не заявляет проверку реального аудио.

## 5. Проверки и покрытие

Во временной копии выполнены чистая сборка тестового набора и 25 тестов в 6 suites: 20 исходных + 5 characterization probes. Все завершились за 5.044 s тестового времени, 0 failures. Compiler warnings/errors в журнале этого запуска не обнаружены.

| Проба | Что наблюдалось | Что этим не доказано |
|---|---|---|
| Реальный makeCopy, 6 буферов | `[2229, 0, 0, 0, 0, 0]` | Поведение всех аппаратных форматов |
| Два Start через барьер | Два успеха, один Stop на источник | Двойной Start через текущий UI |
| Quit preparation при pending Stop | Возврат со статусом processing | Реальный kill процесса и размер повреждения файла |
| Коллизия каталога | Удалён предыдущий временный артефакт | Потеря существующих пользовательских записей; они не затрагивались |
| Повторный prepare writer | Метрика 32, файл 16 кадров | Ошибка обычного flow, где factory создаёт новый writer |

Это не «25 тестов подтвердили, что код исправен». Пять дополнительных проб специально assert-ят наблюдаемые дефекты. После исправления их нужно превратить в regression tests с ожидаемым корректным результатом.

Тестовые doubles encoder пишут строку `mp3`, поэтому успех этих тестов не доказывает декодируемость. Factory в тестах создаёт пустые PCM-файлы заранее, включая некоторые failed-start сценарии; проверки удаления inactive files действительно имеют предмет, но не проверяют закрытие настоящего AVAudioFile. Тест stop failure подставляет строку про Bluetooth, а не отключает реальное устройство.

Приоритет новых regression tests: последовательность буферов и tail; manager start/stop/cancel interleavings; prepareForTermination во всех состояниях; session collision; finalize на ошибках; ошибки записи после Start; корректное значение unknown/partial; долгий/зависший exporter при сохранении subprocess path. Затем живые device tests. Набор тестов следует расширять вокруг контрактов, а не процентом coverage ради процента.

## 6. Рекомендованный объём исправлений именно качества кода

1. Зафиксировать инварианты manager/capture/writer и ожидаемые результаты probes. Исправить CQ-01/02/03/05/07 небольшими проверяемыми изменениями.
2. Добавить typed capture events и корректную модель результата - CQ-04/10. Избежать переименования всего проекта одновременно с изменением поведения.
3. Определить ownership/isolation и bounded writer path - CQ-08; одновременно закрыть restart contract CQ-09.
4. Исправить cancellation/timeout там, где код останется после решения по экспорту - CQ-06.
5. Сделать тестовые fixtures изолированными и детерминированными - CQ-11/12; затем убрать точечный технический долг из раздела 3.

Сравнение подходов: локальные исправления сохраняют уже работающие границы модулей и уменьшают риск регрессии; полная замена capture backend или внедрение тяжёлой архитектуры добавит новых непроверенных контрактов. Новый backend оправдан только отдельными измерениями аппаратных ограничений, а не самим фактом найденных ошибок concurrency.

## 7. Источники и связь с предыдущим аудитом

- Первичный источник - текущий код 27 файлов; снимок SHA-256 и текст проб сохранены в evidence-файле.
- [S1: Swift, Concurrency и suspension points](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html).
- [S2: Swift structured concurrency, task group waits for children](https://github.com/swiftlang/swift-evolution/blob/main/proposals/0304-structured-concurrency.md).
- [Apple, AVAudioConverterOutputStatus](https://developer.apple.com/documentation/avfaudio/avaudioconverteroutputstatus).
- [Предыдущий продуктовый аудит](2026-09-08_audit-and-work-plan.md) остаётся планом доведения продукта. Настоящий документ отдельно оценивает качество реализации и не изменяет approved требования или ADR.

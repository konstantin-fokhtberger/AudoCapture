# Итерация I1: непрерывная конвертация аудио

- Статус: B01 done; это не live acceptance приложения.
- Изменён `AudioConversion.makeCopy`: после потребления текущего входного буфера возвращается `.noDataNow`, поскольку источник продолжает запись. `.endOfStream` ошибочно завершал переиспользуемый converter и давал ноль кадров в последующих вызовах.
- Добавлен `Tests/AudoCaptureCoreTests/AudioConversionTests.swift`: реальные преобразования mono 16/44.1/48/96 kHz -> 48 kHz и stereo Float32 -> interleaved Int16. Проверяются продолжение звука и сохранение обоих каналов.
- До исправления новые тесты завершились с 157 failed assertions. После исправления полный набор: 22 теста, 6 suites, 0 failures, 0.544 s. Параметризованный mono-тест имеет 4 варианта.
- Smoke executable: `Smoke checks passed.`
- Использован полный Xcode, scratch path `/tmp/audocapture-iteration1-build`. Журналы: `/tmp/audocapture-iteration1-before.log`, `/tmp/audocapture-iteration1-after.log`.
- Архитектура, форматы файлов и существующие ADR в I1 не изменялись. Drain на Stop, финализация и контроль lifecycle - следующие задачи B02-B03. Нельзя считать хвост converter проверенным этими тестами непрерывного входа.
- Бэклог и требования обновлены по уточнениям пользователя: один итоговый M4A, имя по локальной дате и времени старта. Экспорт/именование ещё не реализованы (I3).

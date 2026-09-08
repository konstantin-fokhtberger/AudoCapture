

Artifact Storage & Context Management (для Codex)

1. Общий принцип

Все артефакты проекта должны храниться локально в репозитории в виде Markdown-файлов, чтобы обеспечить:

* полный и воспроизводимый контекст
* трассируемость решений
* контроль версий через Git
* независимость от истории чатов

Codex обязан:

* читать эти файлы перед внесением изменений
* обновлять их при изменении контекста
* не полагаться на “память” чата, если есть расхождения

⸻

2. Структура папок

Создай и используй следующую структуру:

/docs
  /00-overview
  /01-requirements
  /02-decisions
  /03-architecture
  /04-constraints
  /05-implementation
  /06-testing
  /07-reports
  /08-changelog
  /09-logs (optional)

⸻

3. Назначение разделов

Папка	Назначение
00-overview	Общее описание проекта
01-requirements	Требования и их версии
02-decisions	Принятые решения (ADR)
03-architecture	Архитектура и схемы
04-constraints	Ограничения
05-implementation	Детали реализации
06-testing	Тесты и сценарии
07-reports	Отчеты, анализ, проблемы
08-changelog	История изменений
09-logs	Технические логи (опционально)

⸻

4. Формат и правила именования

4.1 Общие правила

* Формат: .md
* Кодировка: UTF-8
* Язык: единый (рекомендуется English)
* Имена файлов:

YYYY-MM-DD_<short-name>.md

Примеры:

2026-04-17_initial-requirements.md
2026-04-17_audio-capture-decision.md

⸻

5. Requirements (01-requirements)

Структура файла

# Requirements - Version X
## Metadata
- Date:
- Author:
- Version:
- Status: draft | approved | deprecated
## Objective
...
## Scope
...
## Functional Requirements
...
## Non-Functional Requirements
...
## Acceptance Criteria
...
## Open Questions
...

Правила

* не перезаписывать старые версии
* каждая новая версия - новый файл
* обязательно указывать статус

⸻

6. Decisions (02-decisions) - ADR формат

Каждое решение = отдельный файл

# ADR-XXX: <Title>
## Status
proposed | accepted | rejected | deprecated
## Context
...
## Decision
...
## Alternatives considered
...
## Consequences
...
## References
...

Пример

ADR-001: Use ScreenCaptureKit for system audio capture

Правила

* не изменять принятое решение задним числом
* новые изменения = новый ADR
* ссылаться на требования

⸻

7. Architecture (03-architecture)

# Architecture Overview
## Components
...
## Data Flow
...
## Audio Pipeline
...
## Key Design Decisions
...

⸻

8. Constraints (04-constraints)

# Constraints
## Platform Constraints
...
## Technical Constraints
...
## Legal / OS Restrictions
...
## Known Limitations
...

⸻

9. Implementation (05-implementation)

# Implementation Notes
## Modules
...
## Key Classes
...
## Critical Flows
...
## Known Tradeoffs
...

⸻

10. Testing (06-testing)

# Test Strategy
## Test Scenarios
1. ...
2. ...
## Manual Test Cases
...
## Edge Cases
...
## Known Gaps
...

⸻

11. Reports (07-reports)

Используется для:

* багов
* расследований
* performance анализа

# Report: <Title>
## Problem
...
## Investigation
...
## Findings
...
## Resolution
...
## Follow-ups
...

⸻

12. Changelog (08-changelog)

# Changelog
## YYYY-MM-DD
- Added:
- Changed:
- Fixed:
- Removed:

⸻

13. Правила работы для Codex

Codex ОБЯЗАН:

1. Перед началом:
    * прочитать:
        * latest requirements
        * все ADR
        * constraints
2. При изменениях:
    * обновить:
        * changelog
        * implementation notes (если архитектура изменилась)
        * decisions (если принято новое решение)
3. При неясности:
    * НЕ додумывать
    * зафиксировать вопрос в:

01-requirements (Open Questions)
или
07-reports

4. При конфликте:
    * приоритет:

ADR > Requirements > Implementation

⸻

14. Versioning правила

* Git - основной механизм версий
* Внутри MD:
    * фиксировать версии требований
    * фиксировать статус решений
* Нельзя:
    * переписывать историю
    * удалять старые решения без причины

⸻

15. Минимальный набор для MVP

Codex должен создать минимум:

/docs/01-requirements/2026-04-17_initial.md
/docs/02-decisions/ADR-001_audio-capture.md
/docs/03-architecture/overview.md
/docs/06-testing/test-scenarios.md
/docs/08-changelog/changelog.md

⸻

16. Критерий качества документации (DoD)

Документация считается корректной, если:

* можно восстановить:
    * зачем сделано
    * что сделано
    * какие альтернативы были
* новый разработчик понимает систему без чата
* все ключевые решения задокументированы
* нет противоречий между файлами

⸻

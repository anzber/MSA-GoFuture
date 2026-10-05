# MSA-GoFuture - итоговый проект курса "Микросервисная архитектура"

Проект по кейсу компании **"GoFuture"** (платформа агрегирования такси): переход от монолита
на Django к доменно-ориентированной микросервисной архитектуре.

- **500 000** конкурентных поездок в пике
- **99,99 %** доступности критических сервисов (Задание 3); бизнес-минимум 99,95 % (кейс) выполняется с запасом; MTTR <= 1 ч
- **<= 2 недель** time-to-market новой функции
- развёртывание в **>= 3 георегионах**, соответствие локальным регуляторикам
- динамическое ценообразование и "умное" перераспределение водителей в реальном времени

## Принятые допущения и отклонения

- **99,99 % / год** для критических сервисов - окно измерения в кейсе не задано, принято как
  допущение (годовой бюджет ~52,6 мин).
- **Полная потеря юрисдикции** (оба её региона одновременно) - катастрофа, вынесена из бюджета
  99,99 % и принята как допущение.
- **Сингапур** - город-государство: второго региона внутри страны нет, поэтому отказ его
  региона равен потере юрисдикции (принятое отклонение).

---

## Задание 1. Проектируем домены

Поэтапный план декомпозиции монолита на доменные сервисы (горизонт - год):
**NFR -> карта сервисов -> очерёдность выделения -> C2 To-Be -> обратная совместимость -> миграция данных.**

 Директория: [`Task1/`](Task1/) - полное описание решения: [`Task1/README.md`](Task1/README.md)

| Артефакт | Файл |
|---|---|
| Список нефункциональных требований | [`Task1/ADR-001-nonfunctional-requirements.md`](Task1/ADR-001-nonfunctional-requirements.md) |
| Карта доменов и сервисов (bounded contexts) | [`Task1/ADR-002-domain-service-map.md`](Task1/ADR-002-domain-service-map.md) |
| Очерёдность выделения сервисов (6 волн) | [`Task1/ADR-003-extraction-order.md`](Task1/ADR-003-extraction-order.md) |
| Диаграмма C2 сервисов To-Be | [`Task1/ADR-004-tobe-c2-services.md`](Task1/ADR-004-tobe-c2-services.md), [`C2_ToBe_GoFuture.png`](Task1/C2_ToBe_GoFuture.png) |
| Механизмы обратной совместимости | [`Task1/ADR-005-backward-compatibility.md`](Task1/ADR-005-backward-compatibility.md) |
| План миграции данных | [`Task1/ADR-006-data-migration.md`](Task1/ADR-006-data-migration.md) |

**Ключевая идея:** выделение сервисов идёт по DDD-границам продуктовых команд, каждый сервис
владеет своей БД, а бесшовность обеспечивает "слой обратной совместимости" (Strangler Facade +
ACL + Schema Registry + outbox/CDC). Миграция - волнами: фундамент -> Notification/Analytics ->
Geography/Fraud -> Driver/Pricing -> Booking/Payments -> Payouts + вывод монолита.

---

## Задание 2. Проектируем Event-Driven архитектуру

Полное описание: [`Task2/README.md`](Task2/README.md)

| Артефакт | Файл |
|---|---|
| Модель доменных событий (каталог, конверт, версии) | [`Task2/ADR-001-domain-events.md`](Task2/ADR-001-domain-events.md) |
| Схема топиков Kafka с партиционированием по регионам | [`Task2/ADR-002-kafka-topics.md`](Task2/ADR-002-kafka-topics.md) |
| Потребители событий (Kafka Streams, Flink) | [`Task2/ADR-003-event-consumers.md`](Task2/ADR-003-event-consumers.md) |
| Saga: вид и события | [`Task2/ADR-004-saga.md`](Task2/ADR-004-saga.md) |
| Надёжная доставка (outbox, идемпотентность, DLQ) | [`Task2/ADR-005-reliable-delivery.md`](Task2/ADR-005-reliable-delivery.md) |
| Мониторинг: подход, метрики, инструменты | [`Task2/ADR-006-monitoring.md`](Task2/ADR-006-monitoring.md) |
| Диаграмма C2 событийной платформы | [`C2_EventDriven_GoFuture.puml`](Task2/C2_EventDriven_GoFuture.puml) / [`Task2/C2_EventDriven_GoFuture.png`](Task2/C2_EventDriven_GoFuture.png) |

---

## Задание 3. Глобальное развёртывание и высокая нагрузка

Полное описание: [`Task3/README.md`](Task3/README.md)

| Артефакт | Файл |
|---|---|
| Обоснование выбора регионов | [`Task3/ADR-001-region-selection.md`](Task3/ADR-001-region-selection.md) |
| Схема репликации данных | [`Task3/ADR-002-data-replication.md`](Task3/ADR-002-data-replication.md), [`Replication.png`](Task3/Replication.png) |
| Схема геомаршрутизации | [`Task3/ADR-003-geo-routing.md`](Task3/ADR-003-geo-routing.md), [`GeoRouting.png`](Task3/GeoRouting.png) |
| Аварийное переключение (C4) и сценарии отказа | [`Task3/ADR-004-failover.md`](Task3/ADR-004-failover.md), [`Failover_C4.png`](Task3/Failover_C4.png) |
| Стратегия комплаенса | [`Task3/ADR-005-compliance.md`](Task3/ADR-005-compliance.md) |
| Инструменты защиты (WAF, Firewall и др.) и доработка C2 | [`Task3/ADR-006-security-tools.md`](Task3/ADR-006-security-tools.md), [`C2_Global_Security.png`](Task3/C2_Global_Security.png) |

---

## Задание 4. Платформа данных для ML и BI

Полное описание: [`Task4/README.md`](Task4/README.md)

| Артефакт | Файл |
|---|---|
| Пайплайн данных (C4): микросервисы -> ML и BI | [`Task4/ADR-001-data-pipeline.md`](Task4/ADR-001-data-pipeline.md), [`C4_DataPipeline.png`](Task4/C4_DataPipeline.png) |
| Механизмы обеспечения качества данных | [`Task4/ADR-002-data-quality.md`](Task4/ADR-002-data-quality.md) |

---

## Задание 5. Мультитенантная платформа

Полное описание: [`Task5/README.md`](Task5/README.md)

| Артефакт | Файл |
|---|---|
| Модель изоляции данных между партнёрами | [`Task5/ADR-001-tenant-isolation.md`](Task5/ADR-001-tenant-isolation.md) |
| IAM: SSO, ролевой доступ, таблица ролей | [`Task5/ADR-002-iam-sso.md`](Task5/ADR-002-iam-sso.md) |
| Автоматизированный онбординг партнёров | [`Task5/ADR-003-onboarding.md`](Task5/ADR-003-onboarding.md), [`Onboarding_Flow.png`](Task5/Onboarding_Flow.png) |
| Мониторинг мультитенантного окружения | [`Task5/ADR-004-tenant-monitoring.md`](Task5/ADR-004-tenant-monitoring.md) |
| Диаграмма C2 мультитенантной платформы | [`Task5/C2_Multitenant.png`](Task5/C2_Multitenant.png) |


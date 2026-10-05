# ADR-002. Карта доменов и сервисов "GoFuture" (bounded contexts)

## Общая информация

1. **Родительский артефакт** - `ADR-001-nonfunctional-requirements.md`, исходная диаграмма C3 (`source/C3.puml`).
2. **Автор ADR** - Анзор Березгов, архитектор.
3. **Статус** - Принят.
4. **Согласующие** - продуктовые команды (Booking, Driver, Pricing, Payments, Notification, Geography, Analytics, Fraud), архитектурный комитет.

## Контекст

В монолите C3 явно выделены 9 доменных компонентов, но они связаны "кошмарной" сетью
синхронных вызовов и пишут в **одну общую БД** (`C3.puml`: все домены имеют прямые SQL-связи
с `db_main`). Такая структура не даёт независимого деплоя и изоляции отказов.

Задача этапа - провести границы доменов по **функциональной связанности и владению командами**
(а не по техническим слоям), чтобы каждый сервис можно было развивать, деплоить и
масштабировать независимо.

Принципы нарезки:

1. **Один домен = одна команда** (Conway's Law): 8 продуктовых команд -> 8 доменов.
2. **Bounded context = граница данных**: каждая сущность пишется ровно одним сервисом.
3. **Минимум синхронных связей**: предпочтение событиям; синхронные вызовы - только там,
   где нужен немедленный ответ.
4. **Стабильные контракты**: сервис скрывает свою БД и внутреннюю модель.

## Требования

| No. | Требование |
|---|---|
| 1 | Сохранить все доменные компоненты из C3 (Booking, Driver, Pricing, Payments, Payouts, Notification, Geography, Analytics, Fraud). |
| 2 | Обеспечить владение данными по модели database-per-service. |
| 3 | Развязать синхронные связи доменов, где это возможно, через события. |
| 4 | Соответствовать NFR: изоляция отказов, независимый деплой, масштабируемость по регионам. |
| 5 | Обеспечить понятную карту "команда <-> сервис <-> данные". |

## Решение

### Классификация поддоменов (DDD)

| Тип поддомена | Домены | Логика |
|---|---|---|
| **Core** (конкурентное преимущество) | Booking (матчинг/поездка), Geography (гео/ETA), Pricing (динамические цены), Driver (доступность/умное перераспределение) | Именно здесь создаётся ценность "умного" такси-агрегатора; максимальные инвестиции и собственные алгоритмы |
| **Supporting** | Payments (и сервис Payouts), Fraud | Критичны, но во многом опираются на индустриальные практики; можно покупать/интегрировать, но доменную логику держим у себя |
| **Generic** | Notification, Analytics | Типовые платформенные возможности; допустимо использование готовых решений (FCM/APNS, ClickHouse/BI) |

### Каталог сервисов

| Сервис | Домен / команда | Ответственность (bounded context) | Владеемые данные | Ключевые API | Публикует события | Потребляет события |
|---|---|---|---|---|---|---|
| **API Gateway / BFF** | Платформа | Единая точка входа, версионирование, strangler-маршрутизация, BFF для клиентов | - (только маршруты/кэш) | REST для всех клиентов | - | - |
| **Identity & Access (IAM)** | Платформа | Аутентификация, SSO, RBAC, токены, тенанты | users (идентификаторы/креды), roles, sessions | OIDC/OAuth2 | - | - |
| **Booking Service** | Booking | Жизненный цикл поездки, офферы, оркестрация матчинга (Saga), подпроцесс диспетчеризации и умное перераспределение | bookings, offers, rides | CreateBooking, GetRide, CancelRide | `BookingCreated`, `DriverSearchStarted`, `DriverOfferCreated`, `DriverOfferExpired`, `DriverReserved`, `DriverAssigned`, `RideStarted`, `RideCompleted`, `BookingCancelled` | `DriverOfferAccepted`, `DriverOfferDeclined`, `ZoneBalanceUpdated`, `DemandForecastUpdated`, `PaymentCaptured`, `DriverStatusChanged` |
| **Driver Service** | Driver | Профиль, ТС, документы, статус/доступность, рейтинг | drivers, vehicles, driver_documents, driver_ratings, shifts | GetDriver, SetAvailability, GetCandidates | `DriverStatusChanged`, `DriverLocationUpdated`, `DriverOfferAccepted`, `DriverOfferDeclined` | `DriverOfferCreated`, `DriverReserved`, `BookingCreated`, `PayoutCompleted` |
| **Geography Service** | Geography | Геоиндекс, поиск кандидатов по зоне, ETA, маршруты, геозоны, баланс зон (`ZoneBalance`) | geo_index, zones, routes, zone_balance (PostGIS/ES/KStreams) | FindDrivers, GetEta, GetRoute | `ZoneEntered`, `EtaUpdated`, `ZoneBalanceUpdated`, `ZoneDeficitDetected` | `DriverLocationUpdated`, `BookingCreated` |
| **Pricing Service** | Pricing | Тарифы, котировки, динамическое ценообразование | tariffs, pricing_rules, dynamic_price_state | Quote, GetTariff | `PriceUpdated` | `BookingCreated`, `DriverLocationUpdated`, `ZoneDeficitDetected`, `ZoneBalanceUpdated`, `DemandForecastUpdated` |
| **Payments Service** | Payments | Платежи пассажиров, авторизация/списание/возврат, журнал операций (входящие), интеграция PSP | payments, transactions, refunds | Authorize, Capture, Refund | `PaymentAuthorized`, `PaymentCaptured`, `PaymentFailed`, `PaymentRefunded` | `RideCompleted`, `FraudCleared` |
| **Payouts Service** | Payments | Балансы, начисления водителям, выплаты, журнал операций (исходящие) | payouts, balances, журнал операций | CreatePayout, GetBalance | `PayoutInitiated`, `PayoutCompleted`, `PayoutFailed` | `RideCompleted`, `PaymentCaptured` |
| **Notification Service** | Notification | Push/Email/SMS, шаблоны, предпочтения, ретраи доставки | notifications, templates, devices | SendNotification | `NotificationSent`, `NotificationFailed` | события многих доменов |
| **Analytics Service** | Analytics | Потоковая аналитика, витрины, фичи для ML и BI | analytics_facts, marts (ClickHouse) | Query datamart | `DemandForecastUpdated` (Flink-топология домена) | все доменные события |
| **Fraud Service** | Fraud | Скоринг рисков, правила, ML, чёрные списки | fraud_cases, risk_profiles, rules | Screen, Report | `FraudDetected`, `FraudCleared` | `BookingCreated`, `PaymentAuthorized`, `DriverStatusChanged` |

> **Про Payouts.** Кейс называет 8 продуктовых команд и не перечисляет Payouts среди них,
> но C3 содержит отдельный `Payouts Domain`. Решение: Payouts - отдельный **сервис** (своя БД,
> свой журнал операций, отдельные регуляторные требования к исходящим платежам), но в границах
> **домена Payments**. Команда Payments владеет обоими сервисами, что сохраняет соответствие
> "8 команд <-> 8 доменов".

### Карта контекстов и паттерны интеграции

| Отношение | Паттерн | Обоснование |
|---|---|---|
| Booking -> Pricing, Geography, Driver | **Customer-Supplier** с синхронным Query (gRPC) | Нужен немедленный ответ для матчинга (NFR-PE-01, NFR-PE-04); вызовы идемпотентны и деградируемы |
| Booking -> Payments, Payouts, Notification | **Event-driven (Publisher-Subscriber)** через Kafka | Нет необходимости в немедленном ответе; развязывает домены, повышает отказоустойчивость |
| Booking -> Fraud | Синхронная проверка риска (gRPC) в режиме **советника**: **fail-open** с асинхронной до-проверкой | Fraud не должен блокировать критический путь (NFR-RE-05); отказ Fraud не роняет Booking |
| Payments <-> Payouts -> Fraud | **Customer-Supplier** (async + sync screen) | Fraud должен успеть проверить до подтверждения операции |
| Все домены -> Analytics | **Conformist/Open Host Service** (события) | Analytics - потребитель; домены не знают о нём |
| Домены -> внешние PSP/карты/банки | **Anti-Corruption Layer** | Изоляция от чужих моделей и от локальных провайдеров по регионам |
| Домены -> IAM | **Open Host Service** (OIDC) | Единая аутентификация/авторизация |
| Монолит <-> новые сервисы (на время) | **Strangler Facade + ACL** | Совместимость и постепенный перенос (см. ADR-005) |

### Умное перераспределение водителей (механика)

Отличие "умного" перераспределения от простого "ближайший водитель": система учитывает не
только ETA, но и баланс спроса и предложения по зонам, чтобы пассажир получал подходящего
водителя, а не формально самого близкого.

Поток:

1. Driver и Geography публикуют `DriverLocationUpdated` / `DriverStatusChanged`; потоковая
   задача `ZoneBalance` (Kafka Streams, владелец - Geography) строит тепловую карту спроса и
   предложения по зонам в реальном времени и публикует `ZoneBalanceUpdated` /
   `ZoneDeficitDetected`.
2. Booking оценивает кандидата по функции полезности: `score = w1 * ETA + w2 * дефицит зоны +
   w3 * прогноз следующего спроса + w4 * рейтинг`, где веса настраиваются под регион и время суток.
3. При устойчивом дефиците зоны офферы смещаются к водителям на её границе, а Pricing усиливает
   сигнал динамической ценой (`PriceUpdated`).
4. Решение пересчитывается периодически (несколько секунд), офферы имеют тайм-аут, все действия
   идемпотентны (повторный оффер не создаёт дубль).

Правила и ограничения:

- Не нарушать SLA подачи для уже назначенных заказов; приоритет у пассажира, который ждёт дольше.
- Избегать резких "перебросов" водителей: изменения вводятся постепенно.
- Механика живёт в существующих доменах (Booking, Driver, Geography, Pricing) - новый сервис
  не вводится, границы доменов не разрываются.

Метрики эффекта: среднее время ожидания подходящего водителя в часы пик (NFR-FS-07),
неравномерность распределения водителей по зонам (NFR-FS-08), доля выполненных заказов.

Реализация в событийной модели: Booking ведёт подпроцесс диспетчеризации событиями
`DriverSearchStarted`, `DriverOfferCreated`, `DriverOfferAccepted` / `Declined` / `Expired`,
`DriverReserved`; дефицит зоны (`ZoneDeficitDetected`) усиливает цену (`PriceUpdated`) и
смещает офферы из переполненных зон. Полное описание, тайм-ауты и компенсации - в Task2/ADR-004.

### Правила владения данными

1. Каждый сервис имеет **собственную БД** (PostgreSQL/специализированное хранилище).
2. Запрещены прямые SQL-запросы к БД другого сервиса - только через API или события
   (проверяется fitness-function в CI, см. Task1/ADR-005).
3. Межсервисная согласованность - через Saga + transactional outbox
   (Task2/ADR-004 - Saga, Task2/ADR-005 - надёжная доставка/outbox).
4. Общая БД `legacy_db` существует только на переходный период и удаляется по завершении волн.

## Альтернативы

| Альтернатива | Преимущества | Недостатки | Вердикт |
|---|---|---|---|
| **Нарезка по доменам (выбрано)** | Независимость команд, изоляция отказов, соответствует NFR | Требует времени на выравнивание моделей | Принято |
| Нарезка по техническим слоям (api-layer, data-layer, notifications-layer) | Просто резать монолит механически | Не даёт автономии, повторяет монолит в распределённом виде, "распределённый монолит" | Отклонено |
| Нарезка по сущностям БД (по таблицам) | Формально "микросервисы" | Не совпадает с границами бизнеса и команд; транзакции внутри домена рвутся | Отклонено |
| Оставить 9-й домен Payouts с отдельной командой | Чистая граница | Нарушает соответствие "8 команд", лишняя координация | Отклонено в пользу "сервис внутри домена" |

## Недостатки, ограничения и риски

- **"Правильные" границы требуют проработки.** Нарезка сделана по текущему пониманию доменов;
  рекомендуется серия event-storming сессий перед каждой волной (ADR-003).
- **REST/gRPC для матчинга** создаёт синхронную связку Booking<->Geography/Pricing/Driver.
  Митигируется: circuit breaker, таймауты, кэш (ADR/chaos-тесты), а также выносом тяжёлых
  расчётов в асинхронные обновления.
- **Аналитика как consumer всех событий** может стать "узким горлом" при росте; митигируется
  независимым масштабированием потребителей Kafka и ClickHouse.
- **Соблазн общего "доменного" сервиса** (shared kernel) - если позже возникнет желание
  вынести общие сущности (например, адреса), это должно быть отдельным сервисом с
  явным контрактом, а не общей БД.
- **Дублирование данных** (например, `driver_id` в Booking) неизбежно в database-per-service;
  митигируется событиями и версионированием снапшотов.

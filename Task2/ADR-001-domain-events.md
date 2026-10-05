# ADR-001 (Task2). Модель доменных событий

## Общая информация

1. **Родительский артефакт** - `Task1/ADR-002-domain-service-map.md` (карта сервисов), Задание 2.
2. **Автор ADR** - Анзор Березгов, архитектор.
3. **Статус** - Принят.

## Контекст

Чтобы обрабатывать 500 тыс. конкурентных поездок и считать цены в реальном времени, домены
должны обмениваться не синхронными вызовами, а событиями. Событие описывает уже произошедший
факт (в прошедшем времени) и не требует немедленного ответа. Такой обмен реализует паттерн
"шина событий": продюсер публикует событие, потребители подписываются и реагируют независимо.

## Требования

| No. | Требование |
|---|---|
| 1 | Единая модель доменных событий с понятными именами и полями. |
| 2 | События версионируются и не ломают существующих потребителей. |
| 3 | Каждое событие имеет однозначного продюсера (владельца). |
| 4 | Событие несёт достаточно данных, чтобы потребителю не требовался синхронный вызов. |
| 5 | События пригодны и для реакций сервисов, и для потоковой обработки в реальном времени. |

## Решение

### Формат имени и время

- Имя события - `<Сущность><Действие>` в прошедшем времени: `BookingCreated`, `DriverAssigned`,
  `RideCompleted`, `PaymentCaptured`, `PayoutCompleted`, `DriverLocationUpdated`, `PriceUpdated`,
  `FraudDetected`.
- Время события (`occurredAt`) ставит продюсер; время публикации (`publishedAt`) - шина.

### Конверт (envelope) события

```json
{
  "eventId": "uuid",
  "eventType": "BookingCreated",
  "version": 1,
  "occurredAt": "2026-10-04T10:15:00Z",
  "region": "ru",
  "tenantId": null,
  "partitionKey": "ride-123",
  "correlationId": "uuid",
  "causationId": "uuid",
  "producer": "booking-service",
  "payload": { }
}
```

- `eventId` - уникальный идентификатор (для дедупликации у потребителей).
- `correlationId` / `causationId` - сквозная трассировка цепочки событий.
- `region` - регион события (совпадает с префиксом топика).
- `partitionKey` - ключ партиционирования (идентификатор сущности).

### Каталог ключевых доменных событий

| Событие | Продюсер | Ключ партиции | Основные потребители | Назначение |
|---|---|---|---|---|
| `BookingCreated` | Booking | rideId | Pricing, Fraud, Driver, Geography, Analytics | старт жизненного цикла поездки |
| `DriverAssigned` | Booking | rideId | Notification, Analytics | назначение водителя |
| `DriverLocationUpdated` | Driver | driverId | Geography (ZoneBalance), Analytics | актуализация позиции, расчёт спроса |
| `DriverStatusChanged` | Driver | driverId | Booking, Fraud | доступность водителя |
| `PriceUpdated` | Pricing | region + zoneId | Booking, Notification, Analytics | обновление динамической цены |
| `RideCompleted` | Booking | rideId | Payments, Payouts, Analytics, Fraud | завершение поездки |
| `PaymentAuthorized` / `PaymentCaptured` | Payments | paymentId | Booking, Payouts, Analytics | деньги по поездке |
| `PaymentFailed` | Payments | paymentId | Booking, Notification | ошибка оплаты, компенсация |
| `PayoutCompleted` | Payouts | driverId | Driver, Notification, Analytics | выплата водителю |
| `FraudDetected` | Fraud | rideId | Booking, Payments, Analytics | риск-реакция |
| `FraudCleared` | Fraud | rideId | Booking, Payments | разрешение риска, продолжение процесса |
| `ZoneEntered` | Geography | driverId | Pricing, Analytics | смена зоны |
| `EtaUpdated` | Geography | rideId | Booking, Notification, Analytics | обновление оценки времени прибытия по поездке |
| `RideStarted` | Booking | rideId | Payments, Analytics | начало оказания услуги (поездка стартовала) |
| `BookingCancelled` | Booking | rideId | Fraud, Payments, Driver, Analytics | отмена/компенсация саги |
| `NotificationSent` | Notification | notificationId | Analytics | фиксация доставки уведомления (для аналитики) |

Правило: **один тип события - один владелец-продюсер**. Другие сервисы его не публикуют.
Kafka Streams/Flink-топологии - **часть домена-владельца**: например, расчёт динамической цены
относится к Pricing, поэтому `PriceUpdated` публикует владелец Pricing, а не отдельный
"потоковый" продюсер.

> Каталог выше - **ключевые** доменные события. Полный набор событий процесса (саги), включая
> `DriverReleased`, `PaymentRefunded`, `PayoutInitiated`, `PayoutFailed`, `RideInterrupted`,
> `PayoutReversed`, определён в Task2/ADR-004.

### События диспетчеризации и баланса зон (умное перераспределение)

Отдельная группа событий обеспечивает "умный" подбор водителя (не "ближайший", а "подходящий")
и выравнивание загрузки зон. Диспетчеризацией владеет Booking, балансом зон - Geography
(потоковая задача `ZoneBalance`), ценовой реакцией - Pricing.

| Событие | Продюсер | Ключ партиции | Основные потребители | Назначение |
|---|---|---|---|---|
| `DriverSearchStarted` | Booking | rideId | Analytics, Notification | старт окна подбора водителя |
| `ZoneBalanceUpdated` (компактированный) | Geography (`ZoneBalance`) | region + zoneId | Booking, Pricing, Analytics | спрос/предложение/дефицит зоны в реальном времени |
| `ZoneDeficitDetected` | Geography (`ZoneBalance`) | region + zoneId | Booking, Pricing, Notification | устойчивый дефицит зоны - сигнал цене и офферам |
| `DemandForecastUpdated` | Flink (домен Analytics) | region + zoneId | Booking, Pricing | прогноз спроса для скоринга кандидатов |
| `DriverOfferCreated` | Booking | driverId | Driver, Notification | оффер конкретному водителю (score, offerId, TTL) |
| `DriverOfferAccepted` | Driver | driverId | Booking | водитель принял оффер |
| `DriverOfferDeclined` | Driver | driverId | Booking, Analytics | отказ (сигнал для обучения скоринга) |
| `DriverOfferExpired` | Booking (таймер) | driverId | Booking, Analytics | оффер истёк |
| `DriverReserved` | Booking | rideId | Driver, Analytics | водитель зарезервирован под поездку |
| `DispatchFallbackTriggered` | Booking | rideId | Analytics, Notification | поиск не уложился в SLA, включён fallback |
| `RedistributionIncentiveOffered` | Booking | driverId | Driver, Notification, Analytics | мягкое перераспределение свободных водителей из переполненных зон |

Шаги подпроцесса, тайм-ауты и компенсации - в Task2/ADR-004; партиционирование и retention -
в Task2/ADR-002; расчёт баланса зон - в Task2/ADR-003.

### Типы событий по назначению

- **Event notification** - короткое уведомление о факте (`RideCompleted`), потребитель сам решает,
  что запросить.
- **Event-carried state transfer** - событие несёт снимок нужных полей (`DriverLocationUpdated`),
  чтобы потребителю не нужен был синхронный вызов.

Для высокочастотных потоков (позиции водителей) используется уведомительный тип с последней
известной позицией; для денег - снимок с суммами и идентификаторами для сверки.

### Версионирование

- Схемы событий регистрируются в Schema Registry.
- Изменения только аддитивные (новые поля необязательные); совместимость обратная
  (`BACKWARD_TRANSITIVE`).
- Поле `version` в конверте позволяет потребителям обрабатывать разные версии.

## Альтернативы

| Альтернатива | Преимущества | Недостатки | Вердикт |
|---|---|---|---|
| Доменные события (выбрано) | развязка, realtime, аудит | итоговая согласованность | Принято |
| Event Sourcing как основной способ хранения | полная история, воспроизведение состояния | тяжёлая миграция, сложность, не нужно бизнесу | Отклонено (храним состояние, а не поток как источник правды) |
| Синхронные вызовы между доменами | простота трассировки | связность, каскадные отказы | Отклонено |
| Общие "толстые" события со всем состоянием сущности | потребителю не нужны доп. вызовы | рост объёма, утечка внутренних полей | Отклонено |

## Недостатки, ограничения и риски

- **Итоговая согласованность**: потребители видят события с задержкой; критичные сценарии
  (матчинг, оплата) требуют явных правил и компенсаций (см. ADR-004).
- **Эволюция схем**: без дисциплины в Schema Registry легко сломать потребителей.
- **Дубли и порядок**: шина даёт at-least-once и порядок только внутри партиции; потребители
  обязаны быть идемпотентными (см. ADR-005).
- **Размер каталога**: при росте числа событий нужен реестр владельцев и ревью новых типов.

# Eblogram для iOS

## Сборка IPA

1. В репозитории открой **Settings → Secrets and variables → Actions** и задай `TELEGRAM_API_ID` и `TELEGRAM_API_HASH` со страницы [my.telegram.org/apps](https://my.telegram.org/apps). Workflow проверяет формат и передаёт значения в Bazel, не выводя их в журнал. Работоспособность пары проверяется при подключении к Telegram.
2. В **Actions** выбери **Build Eblogram IPA → Run workflow** и укажи ветку с изменениями. До обновления основной ветки GitHub может показывать старое имя workflow, поскольку путь `.github/workflows/build.yml` остался прежним.
3. Для Sideloadly выбери `standalone` и скачай `Eblogram-standalone-IPA`. В архиве лежит `Eblogram.ipa`. Сборка `full` предназначена для подписи с доступом к App Groups и содержит iOS-расширения.
4. Переподпиши IPA в Sideloadly. Если в Sideloadly уже настроен отдельный Bundle ID для Eblogram, сохрани его для обновлений. Исходный Bundle ID IPA соответствует профилям в репозитории. `standalone` хранит данные отдельно от `full`. На чистой установке потребуется войти в аккаунт. При удалении приложения его локальное хранилище удаляется.

`standalone` не включает расширения Share, Siri, виджет, трансляцию экрана через расширение и расширения уведомлений. Push-уведомления зависят от возможностей итоговой подписи. Локальные функции форка включены в обоих вариантах.

## Проверка запуска

В ранее снятом `eblogram.log` на строке 14184 процесс `Swiftgram` получил `client is not entitled` при запросе App Group. В старом `AppDelegate` это приводило к выходу до открытия базы аккаунтов и загрузки интерфейса. Отказ зарегистрирован на уже установленной сборке. По этому логу нельзя определить, какой именно этап переподписи привёл к отсутствию доступа.

1. Подключи iPhone по USB. На Windows открой [Device Console в iMazing](https://imazing.com/guides/how-to-access-iphone-ipad-console-log). На Mac можно использовать **Console** и выбрать подключённый iPhone.
2. Начни захват, закрой Eblogram через переключатель приложений и запусти снова. Подожди до 30 секунд.
3. Проверь, появился ли экран входа. Если экран по-прежнему чёрный, отфильтруй `[EblogramStartup]` и скопируй в чат только текст меток в исходном порядке, начиная с `main.entered`. В метках нет телефонов, токенов и путей. Сырые логи приложения, provisioning profile и значения API Secrets присылать не нужно.

| Метка | Что удалось проверить |
| --- | --- |
| `main.entered` | Загрузчик дошёл до точки входа приложения. |
| `delegate.didFinish.entered`, `window.created` | UIKit запустил делегат и создал окно с корневым контроллером. |
| `storage.privateReady` или `storage.appGroupReady` | Выбран и открыт контейнер приложения. |
| `storage.appGroupUnavailable` | iOS отказала в доступе к App Group сборке `full`. |
| `storage.keychainConfigured`, `storage.writeReady` | Настроен доступ к Keychain и прошла пробная запись на диск. |
| `accounts.opened`, `accounts.contextReady` | Создан менеджер аккаунтов и получен контекст приложения. |
| `scene.windowVisible` | Окно с корневым контроллером подключено к сцене. |
| `interface.loginPresented` или `interface.accountPresented` | Приложение запросило показ экрана входа или интерфейса аккаунта. |

Если меток нет, проверь журнал сбоя iOS за время запуска. Для диагностики достаточно полей `Exception Type` и `Termination Reason` с удалёнными личными данными, например указания на `DYLD` или watchdog. После успешного запуска проверь отправку кода входа. Затем повторно запусти приложение и проверь, сохранилась ли сессия.

На Mac структуру переподписанной IPA, если она доступна отдельным файлом, можно проверить командой `python3 scripts/check_eblogram_ipa.py Eblogram.ipa --variant standalone`. Для извлечённой `.app` используй `codesign --verify --deep --strict /path/to/Eblogram.app` и `codesign -d --entitlements - /path/to/Eblogram.app`. Сравни `application-identifier` с итоговым `CFBundleIdentifier`. У `full` должен быть доступ к `group.<итоговый CFBundleIdentifier>` у приложения и расширений, которые используют общие данные. Для анализа зависимостей исполняемого файла используй `otool -L /path/to/Eblogram.app/Eblogram`.

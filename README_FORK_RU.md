# Как загрузить изменения Swiftgram Pro в свой GitHub Fork (Windows)

Этот маленький архив предназначен **для настоящего Fork** репозитория `Swiftgram/Telegram-iOS`, в отличие от прежнего overlay-пакета. Workflow собирает **именно ветку твоего форка**.

## Подготовка

1. Создай Fork репозитория: https://github.com/Swiftgram/Telegram-iOS → Fork → Create fork.
2. Установи Git for Windows и Python 3, открой PowerShell.
3. Замени `USERNAME` своим логином GitHub:

```powershell
git clone https://github.com/USERNAME/Telegram-iOS.git
cd Telegram-iOS
```

4. Распакуй **содержимое** этого ZIP в корень открытой папки `Telegram-iOS` с заменой `.github/workflows/build.yml`. В PowerShell, если ZIP лежит в Downloads:

```powershell
Expand-Archive "$env:USERPROFILE\Downloads\Swiftgram_Pro_Fork_GitHubActions.zip" -DestinationPath . -Force
```

5. Примени локальный патч Swiftgram 13.1.3:

```powershell
py -3 scripts/apply_local_features.py .
```

6. Отправь изменения в GitHub:

```powershell
git status
git add .github/workflows/build.yml scripts patches README_FORK_RU.md Swiftgram/SGStatus Swiftgram/SGTelegramUIExtensions Swiftgram/SGPeerInfoRows Swiftgram/SGProUI submodules/TelegramUI/Components/MessageInputPanelComponent submodules/TelegramUI/Components/Chat/ChatTextInputPanelNode submodules/TelegramUI/Components/PeerInfo/PeerInfoScreen submodules/SettingsUI/Sources/Themes
git commit -m "Enable local Swiftgram features and Actions build"
git push
```

Если Git попросит настроить имя и email, настрой `git config --global user.name "..."` и `git config --global user.email "..."` (используй свои значения). Если скрипт пишет `Expected Swiftgram 13.1.3`, значит в твоём форке другая версия, и патч нельзя применять без адаптации.

## Сборка

В своем форке открой Settings → Secrets and variables → Actions и добавь два repository secrets:

- `TELEGRAM_API_ID`
- `TELEGRAM_API_HASH`

Получить их для собственного Telegram-приложения можно на https://my.telegram.org/apps. Значения не публикуй и не присылай в чат.

Затем Actions → **Build Swiftgram Fork (Local Features IPA)** → Run workflow. После успешной сборки забери **Swiftgram-Fork-LocalFeatures-IPA** в Artifacts.

IPA с фиктивной подписью не подходит для прямой установки или TestFlight: для установки на свой iPhone нужно переподписать его (например, с помощью AltStore/Sideloadly). Серверные сервисы Swiftgram Pro и Telegram Premium не открываются.

Указанный workflow **не проверен реальной сборкой на macOS**, и может потребовать исправлений вследствие различий в runners, зависимостях или конфигурации Bazel.

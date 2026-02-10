# Quiz Trainer Flutter (MVP)

Flutter-версия тренажера вопросов из Excel:
- импорт `.xlsx/.xls`
- AI-категоризация через `OpenRouter`
- локальный fallback-классификатор (если API ключ не задан)
- компетенции в отдельной колонке `competency` + заполнение пустых компетенций по правилам
- режимы обучения: Quiz, Flashcards, Review, Category Drill, Weak Spots
- локальная база SQLite
- аналитика по категориям и прогрессу
- библиотека вопросов (поиск, фильтры, редактирование, удаление, экспорт CSV)

## Запуск

```powershell
cd C:\Users\Slavonishe\quizKnowing\quiz_trainer_flutter
flutter pub get
flutter run
```

## AI provider и ключи

В приложении нажмите иконку ключа в правом верхнем углу:
- выберите `OpenRouter` или `Local rules`
- вставьте соответствующий API key

## Проверка качества

```powershell
flutter analyze
flutter test
```

## GitHub (публикация проекта)

В PowerShell, из папки проекта:

```powershell
cd C:\Users\Slavonishe\quizKnowing\quiz_trainer_flutter
git init
git branch -M main
git add .
git commit -m "Initial Quiz Trainer Flutter"
```

Дальше создайте пустой репозиторий на GitHub и привяжите remote:

```powershell
git remote add origin https://github.com/<YOUR_USERNAME>/<YOUR_REPO>.git
git push -u origin main
```

## Vercel (деплой Flutter Web)

В проект уже добавлены:
- `vercel.json`
- `scripts/vercel-build.sh`

Шаги:
1. Загрузите проект в GitHub.
2. На Vercel нажмите `Add New Project` и импортируйте репозиторий.
3. Vercel возьмет настройки из `vercel.json`:
   - Build Command: `bash scripts/vercel-build.sh`
   - Output Directory: `build/web`
4. Нажмите `Deploy`.

После первого деплоя любой push в `main` будет деплоиться автоматически.

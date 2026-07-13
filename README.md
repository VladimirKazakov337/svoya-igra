# Svoya Igra (Своя Игра)

Настольная игра "Своя игра" с ведущим и игроками по локальной сети.

## Возможности

- Создание шаблона: 3 раунда по 25 вопросов + финал (10 тем)
- Загрузка картинок и аудио к вопросам/ответам (drag & drop, Ctrl+V)
- Сохранение и загрузка черновиков
- Комнаты до 5 игроков
- Ведущий на проекторе управляет игрой
- Игроки подключаются с телефонов по коду комнаты
- Круглая кнопка ответа на весь экран
- Финальный раунд: ставки, ответы, таблица результатов
- Экран победителя

## Быстрый старт

```bash
git clone https://github.com/VladimirKazakov337/svoya-igra.git
cd svoya-igra
python -m venv venv
source venv/Scripts/activate  # Windows
# source venv/bin/activate     # Linux/Mac
pip install -r server/requirements.txt
cd server && python main.py
Сервер: http://localhost:8000

Как играть
Ведущий:

Открыть http://localhost:8000

Create Game → заполнить шаблон → Start Game

Появится код комнаты

Дождаться игроков → START GAME

Игроки (с телефона, тот же Wi-Fi):

Узнать IP компьютера ведущего:

bash
python -c "import socket; print(socket.gethostbyname(socket.gethostname()))"
Открыть http://IP:8000/player.html

Ввести код комнаты и имя → Join

Структура проекта
text
svoya-igra/
├── server/               # FastAPI + WebSocket
│   ├── main.py
│   ├── game_manager.py
│   └── requirements.txt
├── client/web/
│   ├── index.html        # Ведущий
│   └── player.html       # Игрок
├── drafts/               # Черновики (JSON)
└── uploads/              # Медиафайлы
API
Документация Swagger: http://localhost:8000/docs
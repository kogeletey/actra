# Командная строка из браузера

Идея состоит в том, чтобы создать браузер, который сможет превращать api интерфес
в интерфейс командной строки.

Схема 

```sh
pwact <tool.dns> <api_header> <api_methods>
```

А так же установить локально

```sh
pwact <tool.dns> install
```

Чтобы это заработало, необходимо использовать `.well-know` URL 

```json
{
    "api": "https://codeberg.org/api/v1",
    "bin": {
        "<platform>": [{
            "<architecture>": "<path_for_file" 
        }]
    }
    "settings": {
        "aliases": [{
            "alias": "i", 
            "type": "path",
            "path": "<path>"
        }]
    }
}
```


Например:

```json
{
    "api": "https://codeberg.org/api/v1",
    "settings": {
        "aliases": [
            {
                "alias": "i",
                "type": "path",
                "path": "/repos/{owner}/{repo}/issues"
            },
            {
              "alias": "create",
              "type": "method",
              "method": "POST"
            },
            {
              "alias": "tea",
              "type": "bin",
              "bin": "tea"
            }
        ]
    },
    "bin": {
      "linux": [{"x86": "https://dl.gitea.com/tea/main/tea-main-linux-amd64.xz"}]
    }
}
```



Метод REST API - `https://codeberg.org/api/v1/repos/{owner}/{repo}/issues` превратиться в следующий код

По умолчанию get запрос

```sh
pwact api codeberg.org repos issues [owner] [repo]
```

Если нужно отправить post запрос, то

```sh
pwact api codeberg.org post --auth repos issues [owner] [repo]
```

токены хранятся в отдельной базе данных, независимо от репозитория.

Методы перед pwact можно переопределить

```sh
pwact api codeberg.org create --auth repos issues [owner] [repo]
```

Установить и запустить инструмент в изолированном контексте можно

```sh
pwact api codeberg.org install
```

Все те же методы работают с бинарниками.

```sh
pwact bin codeberg.org install
```

В настройка самого инструмента может быть настройка, которая определить по умолчанию запускать бинарники или api. Так же можно не писать `api` или `bin` если в манифесте указан только один параметр

По умолчанию все запросы в clearnet иду по `https`, tor и i2p - `http`.
Но можно указать и конкретный протокол

```sh
pwact bin "http://codeberg.org" install
```

В случае выполнения команды по установки бинарников, даже если они не указаны в manifest на сайте, то могут быть скачаны с [репозиториия pkgx](https://github.com/pkgxdev/pantry)
Устанавливаются в случае пользователя в директорию `~/.local/bin`, в случае root `/usr/local/bin/`

# Salesforce API Contract

## Base

- `GET /services/apexrest/game/config`
- `GET /services/apexrest/game/player?playerId=...`
- `POST /services/apexrest/game/player`
- `POST /services/apexrest/game/feedback`
- `POST /services/apexrest/game/reward-code`
- `POST /services/apexrest/game/recovery`

## Resposta padrao

Sucesso:

```json
{
  "success": true,
  "data": {}
}
```

Erro:

```json
{
  "success": false,
  "errorCode": "ERROR_CODE",
  "message": "Mensagem amigavel."
}
```

Observacao:
- alguns endpoints retornam `config`, `player`, `reward` ou `data` no topo para manter o contrato mais direto para o app.
- nenhum endpoint retorna stack trace.

## GET config

Retorna configuracao publica da `GAME_CONFIG`.

Resposta:

```json
{
  "success": true,
  "config": {
    "betaServerUrl": "https://dbm-beta.myftp.biz",
    "ddnsHostname": "dbm-beta.myftp.biz",
    "rewardCodesEnabled": true,
    "labModeEnabled": true,
    "timerAttackEnabled": true,
    "nervesOfSteelEnabled": true,
    "rankedEnabled": true,
    "maintenanceMode": false
  }
}
```

## GET player

Query param:

- `playerId` obrigatorio

Resposta:

```json
{
  "success": true,
  "player": {
    "accountId": "001...",
    "playerId": "abc123",
    "displayName": "Rodrigo",
    "loginProvider": "google",
    "profile": {},
    "progress": {},
    "rewards": {}
  }
}
```

Erros comuns:
- `REQUIRED_FIELD`
- `INVALID_PLAYER_ID`
- `PLAYER_NOT_FOUND`

## POST player

Payload exemplo:

```json
{
  "playerId": "abc123",
  "displayName": "Rodrigo",
  "loginProvider": "google",
  "googleId": "google-sub",
  "appleId": null,
  "steamId": null,
  "deviceId": "device-id",
  "profile": {},
  "progress": {},
  "rewards": {}
}
```

Comportamento:
- cria `Account` se nao existir
- atualiza dados leves se ja existir
- atualiza `Game_Last_Login_At__c`
- limita payload e JSONs grandes

## POST feedback

Payload exemplo:

```json
{
  "playerId": "abc123",
  "mode": "Timer Attack",
  "stageNumber": 12,
  "boardName": "Classico Mobile",
  "difficulty": "Medio",
  "playerScore": 8,
  "aiScore": 5,
  "result": "win",
  "durationSeconds": 180,
  "aiAverageTimeMs": 450,
  "aiMaxTimeMs": 1200,
  "powersUsed": {
    "masterTip": 1
  },
  "feedbackCategory": "IA lenta",
  "feedbackStars": 4,
  "feedbackComment": "A IA demorou um pouco nessa partida.",
  "appVersion": "0.01.53",
  "deviceInfo": {
    "platform": "android"
  },
  "source": "post_match"
}
```

Resposta:

```json
{
  "success": true,
  "data": {
    "caseId": "500...",
    "subject": "[Dots & Boxes] Laboratorio - IA lenta"
  }
}
```

## POST reward-code

Payload:

```json
{
  "playerId": "abc123",
  "code": "PUTZFORCE"
}
```

Sucesso:

```json
{
  "success": true,
  "message": "Codigo resgatado com sucesso.",
  "reward": {
    "energy": 5,
    "masterTips": 1,
    "freeRetries": 1
  }
}
```

Erros comuns:
- `LOGIN_REQUIRED`
- `INVALID_REWARD_CODE`
- `CODE_ALREADY_REDEEMED`
- `REWARD_CODES_DISABLED`

## POST recovery

Operacoes:
- `registerHash`
- `validateHash`
- `regenerateHash`

Payload com hash:

```json
{
  "operation": "registerHash",
  "playerId": "abc123",
  "recoveryHash": "hash-value"
}
```

Payload com codigo puro:

```json
{
  "operation": "regenerateHash",
  "playerId": "abc123",
  "recoveryCode": "DBM8XQ7M2PL9A4ZK6TNY3RW5CJV"
}
```

Regras:
- Salesforce persiste apenas hash
- hash anterior e sobrescrito em regeneracao
- o endpoint nunca devolve o codigo puro

Erros comuns:
- `INVALID_OPERATION`
- `PLAYER_NOT_FOUND`
- `RECOVERY_HASH_REQUIRED`

## Erros tecnicos cobertos

- `BAD_REQUEST`
- `INVALID_JSON`
- `PAYLOAD_TOO_LARGE`
- `TEXT_TOO_LARGE`
- `JSON_TOO_LARGE`
- `UNEXPECTED_ERROR`

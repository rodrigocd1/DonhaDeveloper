# Salesforce Org Setup

## Componentes criados

- Campos customizados em `Account` para jogador e `GAME_CONFIG`
- Campos customizados em `Case` para feedback e laboratorio
- Classes Apex utilitarias:
  - `GameConstants`
  - `GameRestException`
  - `GameJsonUtil`
  - `GameSecurityUtil`
  - `GameRestResponse`
  - `GameRestRequestValidator`
- Services:
  - `GameConfigService`
  - `GameAccountService`
  - `GameFeedbackService`
  - `GameRewardCodeService`
  - `GameRecoveryService`
- Apex REST:
  - `GameConfigRest`
  - `GamePlayerRest`
  - `GameFeedbackRest`
  - `GameRewardCodeRest`
  - `GameRecoveryRest`
- Testes Apex dedicados para REST e services

## Criar a Account GAME_CONFIG

1. Criar uma `Account` manualmente na org.
2. Preencher:
   - `Name = GAME_CONFIG`
   - `Game_Player_Id__c = GAME_CONFIG`
3. Salvar o JSON global em `Game_Config_JSON__c`.

Exemplo inicial:

```json
{
  "betaServerUrl": "https://dbm-beta.myftp.biz",
  "ddnsHostname": "dbm-beta.myftp.biz",
  "x1BetaEnabled": false,
  "x1ComingSoonEnabled": true,
  "minimumAppVersion": "0.01.53",
  "rewardCodesEnabled": true,
  "bannerAdsEnabled": true,
  "shopBannerEnabled": true,
  "stageMapBannerEnabled": true,
  "profileBannerEnabled": true,
  "feedbackBannerEnabled": false,
  "salesforceFeedbackEnabled": true,
  "labModeEnabled": true,
  "timerAttackEnabled": true,
  "nervesOfSteelEnabled": true,
  "rankedEnabled": true,
  "maintenanceMode": false,
  "maintenanceMessage": "",
  "rewardCodes": [
    {
      "code": "PUTZFORCE",
      "active": true,
      "neverExpires": true,
      "requiresLogin": true,
      "maxRedemptionsPerAccount": 1,
      "reward": {
        "energy": 5,
        "masterTips": 1,
        "freeRetries": 1
      }
    }
  ]
}
```

## CORS, Site e Connected App

### Opcao 1: endpoint publico controlado

- Criar um `Salesforce Site` ou Experience Cloud site dedicado ao jogo.
- Liberar apenas as classes Apex REST do jogo no Guest User:
  - `GameConfigRest`
  - `GamePlayerRest`
  - `GameFeedbackRest`
  - `GameRewardCodeRest`
  - `GameRecoveryRest`
- Dar acesso somente aos campos realmente necessarios em `Account` e `Case`.
- Nao expor `Account`, `Case` ou qualquer objeto diretamente.
- Nao permitir leitura ou escrita ampla no Guest User.

### Opcao 2: OAuth com Connected App

- Criar uma `Connected App` se o app for autenticar por OAuth.
- Configurar callback URLs do app mobile/desktop.
- Definir escopos minimos.
- Associar permission set especifico para o jogo.

### CORS e CSP

- Incluir as origens do app em `CORS`.
- Se o app usar paginas hospedadas no Salesforce, configurar `CSP Trusted Sites` para os dominios externos realmente necessarios.
- Nao adicionar curingas desnecessarios.

## Permissoes recomendadas

- Criar um permission set dedicado ao backend do jogo.
- Liberar:
  - execucao das classes Apex REST do jogo
  - leitura/escrita nos campos `Game_*` de `Account`
  - criacao e leitura dos campos `Game_*` de `Case`
- Se usar Guest User:
  - permitir apenas o minimo
  - revisar sharing e FLS antes de publicar

## Como testar endpoints

### GET config

```bash
curl -X GET https://SEU-DOMINIO/services/apexrest/game/config
```

Resultado esperado:
- `success = true`
- objeto `config`
- sem tokens, secrets ou stack trace

### POST player

```bash
curl -X POST https://SEU-DOMINIO/services/apexrest/game/player \
  -H "Content-Type: application/json" \
  -d "{\"playerId\":\"abc123\",\"displayName\":\"Rodrigo\",\"loginProvider\":\"google\",\"profile\":{\"level\":1}}"
```

Resultado esperado:
- cria ou atualiza `Account`
- retorna `player`
- preenche `Game_Last_Login_At__c`

### POST feedback

```bash
curl -X POST https://SEU-DOMINIO/services/apexrest/game/feedback \
  -H "Content-Type: application/json" \
  -d "{\"playerId\":\"abc123\",\"mode\":\"Timer Attack\",\"feedbackCategory\":\"IA lenta\",\"feedbackComment\":\"A IA demorou um pouco.\"}"
```

Resultado esperado:
- cria `Case`
- relaciona com `Account` quando o jogador existir
- retorna `caseId`

### POST reward code

```bash
curl -X POST https://SEU-DOMINIO/services/apexrest/game/reward-code \
  -H "Content-Type: application/json" \
  -d "{\"playerId\":\"abc123\",\"code\":\"PUTZFORCE\"}"
```

Resultado esperado:
- valida login
- grava resgate em `Game_Rewards_JSON__c`
- impede duplicidade

### POST recovery

```bash
curl -X POST https://SEU-DOMINIO/services/apexrest/game/recovery \
  -H "Content-Type: application/json" \
  -d "{\"operation\":\"registerHash\",\"playerId\":\"abc123\",\"recoveryHash\":\"hash-value\"}"
```

Resultado esperado:
- grava apenas hash
- atualiza `Game_Recovery_Code_Created_At__c`
- nunca retorna codigo puro

## O que nunca expor

- senha
- token
- client secret
- refresh token
- private key
- payload administrativo nao necessario
- stack trace para o app

## Deploy granular sugerido

### 1. Campos de Account

```bash
sf project deploy start --source-dir force-app/main/default/objects/Account/fields -o Donha_Developer
```

### 2. Campos de Case

```bash
sf project deploy start --source-dir force-app/main/default/objects/Case/fields -o Donha_Developer
```

### 3. Classes do jogo

```bash
sf project deploy start --metadata ApexClass:GameConstants,ApexClass:GameRestException,ApexClass:GameJsonUtil,ApexClass:GameSecurityUtil,ApexClass:GameRestResponse,ApexClass:GameRestRequestValidator,ApexClass:GameConfigService,ApexClass:GameAccountService,ApexClass:GameFeedbackService,ApexClass:GameRewardCodeService,ApexClass:GameRecoveryService,ApexClass:GameConfigRest,ApexClass:GamePlayerRest,ApexClass:GameFeedbackRest,ApexClass:GameRewardCodeRest,ApexClass:GameRecoveryRest,ApexClass:GameTestDataFactory,ApexClass:GameConfigServiceTest,ApexClass:GameAccountServiceTest,ApexClass:GameFeedbackServiceTest,ApexClass:GameRewardCodeServiceTest,ApexClass:GameRecoveryServiceTest,ApexClass:GameConfigRestTest,ApexClass:GamePlayerRestTest,ApexClass:GameFeedbackRestTest,ApexClass:GameRewardCodeRestTest,ApexClass:GameRecoveryRestTest -o Donha_Developer
```

### 4. Testes Apex relevantes

```bash
sf apex run test --tests GameConfigRestTest,GamePlayerRestTest,GameFeedbackRestTest,GameRewardCodeRestTest,GameRecoveryRestTest,GameAccountServiceTest,GameConfigServiceTest,GameFeedbackServiceTest,GameRewardCodeServiceTest,GameRecoveryServiceTest -o Donha_Developer
```
